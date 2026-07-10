# VCP 上下文工程 · 第 5 站：prompt 缓存断点与成本工程

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 对应四个子问题中的 ④「怎么省」。前置：已读第 2 站（事件溯源与消息重建）——本站的断点位置依赖那一站的"注入只发生在最新 user 消息"这一结论。

## 0. 本站要解决的问题

Workspace 迭代是一个多步 tool 循环（实测 3~24 步）。AI SDK 的 `streamText` 每一步都把「system + 全部历史 + 当前 user + 已发生的 tool-call/result」**原样重发**给模型，只在尾部追加新内容。没有缓存时，一轮 24 步的迭代要把同一段 10 万 token 级的前缀全价重发 24 次。

本站学两件事：

1. **缓存断点怎么打**——打在哪、为什么打在那、什么时候不打；
2. **一次真实的成本排障**——两个提交（`60a3249b`、`5ffdaff3`）从 LangSmith 命中率数据发现问题 → 定位根因 → 修复 → 真实网关验证的全过程。

## 1. 前置知识：Anthropic prompt caching 的三条规则

看代码前必须先懂计费模型，否则断点位置的每个决策都无法理解：

1. **最长公共前缀匹配**：缓存键是「tools + system + messages 各 content part，直到带 `cacheControl` 标记的那个 part 为止」。下一次请求若拥有字节一致的前缀，就从缓存读回。**前缀中任何一个字节变了，从那个字节起全部失效。**
2. **写 1.25x、读 0.1x**：写缓存要付 25% 溢价，读缓存只付 10%。推论：**只写不读是净亏**（付 1.25x 换回 0 收益）——这解释了后文 `dropped > 0` 为什么跳过打标。
3. **最多 4 个断点，TTL 5 分钟**：一次请求最多标 4 个 `cacheControl` 位置；缓存 5 分钟内没被读就过期。

> ⚠️ **重要**：本仓库经 Cloudflare AI Gateway → Vertex AI 调 Claude。缓存行为只在真实网关请求里发生——本地 `pnpm test` 用 mock adapter，**看不到任何缓存效果**。要验证命中率，必须看真实网关账单 / LangSmith 的 usage 字段（`cache_read_input_tokens` / `cache_creation_input_tokens`）。

## 2. 核心代码导读

### 2.1 断点的物理形态：只加元数据，不改字节

全仓打断点只有两个函数。第一个包 system prompt（所有 agent 共用）：

```ts
// apps/agent/src/agents/prompt-redlines.ts:85-93
export function cacheableSystem(content: string): SystemModelMessage {
  return {
    role: "system",
    content,
    providerOptions: {
      anthropic: { cacheControl: { type: "ephemeral" } },
    },
  };
}
```

第二个给任意消息的**最后一个 content part** 打标（`apps/agent/src/agents/workspace/workspace-context-window.ts:94-112`）：

```ts
/** 在消息最后一个 content part 上追加 ephemeral cacheControl（不可变，返回新消息）。 */
function markLastPartEphemeral(message: ModelMessage): ModelMessage {
  // ...把 providerOptions.anthropic.cacheControl = { type: "ephemeral" }
  // 合并到最后一个 part 上，返回新对象，原消息不动
}
```

注意注释里反复出现的 **billing-only** 三个字：打断点**只追加 `providerOptions`、内容字节完全不变**。这是一条设计红线——缓存优化绝不允许改变发给模型的实际内容，单测用「剥掉 providerOptions 后 JSON 与原始完全一致」来锁死（见 §4 实践 a）。

### 2.2 预算裁剪：`trimMessagesToBudget`

打断点之前先要控制总量。`workspace-context-window.ts:8` 定义预算：

```ts
/**
 * 取 Claude Sonnet 4.x 200K 窗口的保守比例：floor(200K*0.75) - 32K 输出预留 ≈ 118K，
 * 向下收敛到 110K（宁可偏小，避免触顶截断）。system prompt 在 messages 之外，另占。
 */
export const WORKSPACE_CONTEXT_TOKEN_BUDGET = 110_000;
```

裁剪规则（`:56-91`，纯函数）值得逐条品：

- **未超预算 → 返回同一引用**（绝大多数迭代命中，零开销）；
- **锚点 = 最后一条 user 消息**，它及其之后**绝不丢**（那是当前请求 + 本轮注入块）；
- 从**头部**丢最旧消息，且**成组丢**：`assistant(tool-call)` 连同紧随的 `tool(result)` 一起丢——Anthropic API 收到开头是孤儿 tool-result 的消息序列会直接报错；
- 丢光历史仍超预算 → 不再丢，保当前请求完整，交给下游兜底。

token 估算用的是**字符数 / 4** 的粗口径（`estimateMessageTokens`，`:16-32`）——裁剪只需要量级正确，不值得为精确计数引入 tokenizer 依赖。

### 2.3 迭代双断点：`markIterationHistoryCacheBreakpoint`

这是本站核心。先看完整实现（`workspace-context-window.ts:137-159`）：

```ts
export function markIterationHistoryCacheBreakpoint(
  messages: ModelMessage[],
  opts: { dropped: number },
): ModelMessage[] {
  if (opts.dropped > 0) return messages;   // ← 头部驱逐轮：不打标

  let anchor = -1;                          // 找最后一条 user（当前请求）
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    if (messages[i]?.role === "user") { anchor = i; break; }
  }
  if (anchor <= 0) return messages;         // 锚点前无历史 → 没有可缓存前缀

  const next = [...messages];
  // 断点#1：锚点前最后一条历史消息（跨轮历史缓存）。
  next[anchor - 1] = markLastPartEphemeral(next[anchor - 1]!);
  // 断点#2：当前轮 user 消息（轮内全前缀缓存，含 per-turn 注入块）。
  next[anchor] = markLastPartEphemeral(next[anchor]!);
  return next;
}
```

三个决策逐一拆解：

**① 为什么断点 #1 能生效——历史前缀逐轮字节一致。**
这依赖第 2 站的结论：折叠历史由 `build-model-messages` 从事件流**确定性重建**，而每轮的装饰（`[Context:]` 行、设计记忆、recent-files、loaded-skills 注入）**只前置到最新一条 user 消息**，历史 user 消息永远素净。所以 turn N 的历史前缀是 turn N+1 消息序列的字节前缀子序列——断点 #1 打在「锚点前最后一条历史消息」上，下一轮直接读回（受 5 分钟 TTL 约束）。
**教训**：缓存不是打个标就有——它要求上游（消息重建逻辑）纪律性地保证前缀稳定。如果哪天有人往历史 user 消息里加了个时间戳，这个断点就废了。

**② 为什么还要断点 #2——轮内多步重发才是主成本。**
断点 #1 只圈住跨轮历史。而当前轮 user 消息里带着 ~19K 的注入块（DESIGN.md 设计记忆 + recent-files + skill 正文），落在断点 #1 **之后**——tool 循环的 step 2~N 每步都全价重发这 19K。断点 #2 打在当前 user 消息上，让 step 2~N 读回「历史 + 注入 + 当前轮」整段前缀，fresh 部分塌成只剩每步新增的 tool-call/result。
**断点位置判定法则**：断点要打在「稳定前缀的最远端」。打早了浪费（可缓存的没圈进来）；打在每步都变的内容之后（比如 tool 结果之后）则完全无效——tool 结果每步不同，不构成任何请求间共享的前缀。

**③ 为什么 `dropped > 0` 时整个不打。**
`trimMessagesToBudget` 若当轮从头部丢了消息，缓存前缀已经**位移**——上一轮缓存里的前缀和这一轮的字节序列对不上了。此时打标只会发生 cache-write（付 1.25x）而永远没有 cache-read。跳过打标，本轮回退到只有 system+tools 被缓存的现状，把**最坏情况钉在与不做优化持平**。
这是成本工程里很典型的**下界保护**思维：优化必须构造成"最坏时不比现状差"。

断点总数：system(1) + #1 + #2 = 3，符合 Anthropic 4 断点上限，还留了一个余量。

### 2.4 并发预热：`workspace-cache-prime.ts`

首轮生成有另一个完全不同的缓存失效模式。文件头注释把根因写得很清楚（`workspace-cache-prime.ts:3-16`）：

```
根因：DAG 把每页 section group 在 chrome 完成后**同一 while 迭代一次性全放**
（per-group 并发上限 4 不约束总并发），N 个 section worker 在同一毫秒并发发起。
它们共享一个字节一致的缓存前缀（system + tools + staticPrefix ≈ 35.7K），但并发
瞬间无人写已 commit，于是全部 cache-MISS + cache-WRITE（各付 1.25x 写溢价、读回为
0；实测 prod 命中仅 8%、写 2.94M tokens 读回 0.7M）。

解法：fan-out 前用一个代表性 section task 复刻同一前缀，发一次 max_tokens=1 请求
（只 prefill、写缓存、立即返回）并 await 到 commit；随后并发 worker 全部 cache-READ（0.1x）。
```

这就是**缓存的写后读时序问题**：缓存要先有人**写完**（commit），后来者才能读。N 个请求同时到达时谁都不是"后来者"。预热请求的构造（`:46-63`）有两个讲究：

- `maxOutputTokens: 1` + `stopWhen: [stepCountIs(1)]`——预热的目的**只是让服务端 prefill 输入并 commit 缓存前缀**，输出一个 token 就够，多一个都是浪费；
- **staticPrefix 和 tools 必须与真实 worker 字节一致**（经同一个 `buildWorkspaceWorkerPrompt` / `createBoundedWorkerTools` 构造）——缓存键包含 tools，差一个字节就读不回。

fail-safe：无 section task / 预热抛错 → 直接回退到并发踩踏现状（catch 只 warn），**绝不因为省钱手段失败而阻断用户的首轮生成**。

## 3. 实战排障记录（两个真实提交，最有教学价值的部分）

### 第一回合：`60a3249b`（2026-07 初）

完整提交信息摘录（`git log -1 --format=%B 60a3249b`）：

```
修复：补两个 P0 prompt 缓存断点，砍迭代+首生 token 成本

实测 LangSmith：workspace 占 ~96% prompt token，但缓存混合命中仅 11-16%。
两处不同根因，各补一个 ephemeral 断点（均 billing-only / fail-safe）：

C1 迭代折叠历史加缓存断点：迭代主循环原只有 system+tools 一个断点，整段
折叠历史（上限 110K）落在 messages[] 上无 cacheControl、每轮全价重发（命中
12-15%、82-87% 全价）。markIterationHistoryCacheBreakpoint 在 trim 后给"最新
user 锚点前最后一条历史消息"打 ephemeral 断点；折叠历史逐轮字节一致（历史 user
消息不带 [Context:] 与各注入），按最长公共前缀 cache-read 复用。dropped>0 头部
驱逐轮跳过打标避免只写不读的写溢价。只加 providerOptions、内容字节不变。

worker 首生 section 缓存预热：DAG 把每页 section group 在 chrome 后同一迭代一次
性全放（per-group 上限 4 不约束总并发），N 个 section worker 同毫秒并发、共享同
一 35.7K 前缀但无人写已 commit → 全部 cache-MISS+WRITE（prod 命中仅 8%、写 2.94M
读回 0.7M）。primeSectionWorkerCache 在 fan-out 前用代表性 section task 复刻同构
system+tools+staticPrefix，发一次 max_tokens=1 预热写好前缀，随后并发 worker 全
cache-READ。无 section task / 预热抛错直接回退现状，绝不阻断首生。
```

**读法**：注意问题是怎么被**发现**的——不是有人觉得"好像有点贵"，而是 LangSmith 数据给出精确画像：workspace 占 96% 的 prompt token、命中率只有 11-16%、首生写 2.94M tokens 只读回 0.7M。**成本问题的第一步永远是让账单可观测、可归因**（这个仓库的 `cf-aig-metadata` 按 intent/tenant/site/run 打标，就是为此）。

### 第二回合：`5ffdaff3`（几天后）

```
修复：迭代缓存补第二个断点（轮内全前缀），收住注入块每步重发

实测真实迭代发现 C1 只缓存了折叠历史（read 平在 ~10.8K），而当前轮的注入块
（DESIGN.md/recent-files/当前 user，~19K）落在断点之后，被多步 tool 循环每步全价
重发（fresh 每步增长）。这是迭代主成本，被原断点位置漏掉。

markIterationHistoryCacheBreakpoint 改打两个断点：#1 锚点前历史（跨轮，原有）+
#2 当前轮 user 消息（轮内全前缀）。tool 循环 step2~N 改为读回"历史+注入+当前轮"
整段前缀，fresh 塌成只剩新 tool 结果。断点#2 写是#1 超集、不增写量；system+#1+#2
=3 个断点，遵守 4 上限。billing-only。

真实 Vertex 网关验证：两断点下 step2 读回整段前缀（write 5443→read 5443）。
```

**读法**：第一回合修完之后**又回去看了数据**——发现 read 稳定停在 ~10.8K（只有历史），fresh 每步还在涨（注入块没被圈住）。修复方式是把断点从一个改成两个；验证方式是真实网关下观察 `write 5443 → read 5443`（step 1 写了多少，step 2 就读回多少，说明整段前缀全部命中）。
两个回合合起来是一个完整的**测量 → 假设 → 修复 → 再测量**闭环。缓存优化没有"改完就完"，只有数据闭环。

另一个细节：「断点 #2 的写是 #1 的超集」——两个断点在同一条前缀延长线上，服务端写缓存本来就写到最远断点，所以加 #2 **不增加写量**，纯赚。

## 4. 动手实践

### 实践 a：跑断点单测，读懂三个关键用例（已验证可运行）

```bash
cd ~/ce_repos/vcp/apps/agent
pnpm exec vitest run src/agents/workspace/workspace-context-window.test.ts src/agents/workspace/workspace-cache-prime.test.ts
# 预期：2 个文件、13 个测试全绿，耗时 <1s
```

然后打开 `workspace-context-window.test.ts:111-155`，重点读三个用例（用例名就是设计意图）：

1. **"打两个断点：锚点前历史（跨轮）+ 当前 user 消息（轮内全前缀），且不改任何内容字节"**——注意它怎么断言 billing-only：`stripProviderOptions(out)`（剥掉 providerOptions 再序列化）必须与打标前的 JSON **逐字节相等**；
2. **"发生头部驱逐（dropped>0）当轮跳过打标，避免只写不读的缓存写溢价"**——断言返回**同一引用**（连新数组都不建）；
3. **"当前 user 之前没有历史 → 原样返回，不打标"**——首轮对话没有可缓存的历史前缀。

### 实践 b：提交历史考古（已验证可运行）

```bash
cd ~/ce_repos/vcp
git log --oneline --grep=缓存          # 挖出全部缓存相关提交
git log -1 --format=%B 60a3249b        # 读完整提交信息（含实测数据）
git show --stat --format= 60a3249b     # 看这次改了哪 5 个文件
git show 5ffdaff3                      # 看第二回合的完整 diff（不大，79 行）
```

建议把 `git show 5ffdaff3` 的 diff 完整读一遍——它是"一个断点改两个断点"的最小改动样例，测试怎么跟着改也在同一个 diff 里。

### 实践 c：纸面练习——你来打断点

某轮迭代（`dropped = 0`）的消息序列如下：

```
system                          ← cacheableSystem 已打断点 (0)
[0] user      "turn1: 把首页标题改大"
[1] assistant tool-call read_snapshot_files
[2] tool      result(文件内容)
[3] assistant tool-call apply_patch_batch
[4] tool      result(applied)
[5] assistant "改好了"
[6] user      "turn2: 再加一个联系页"   ← 前置有 [设计记忆]+[recent files] 注入
```

问题：断点 #1、#2 应打在哪两条消息上？如果打在 [4] 和 [6] 上会怎样？如果这轮 `dropped = 3` 呢？

<details><summary>答案</summary>

- **#1 打在 [5]**（锚点 [6] 前的最后一条历史消息）：圈住 [0]~[5] 的跨轮稳定历史；
- **#2 打在 [6]**（当前 user，注入块就在它的文本里）：让本轮 tool 循环 step 2~N 读回 system+[0..6] 整段。
- 打在 [4] 而不是 [5]：**合法但浪费**——[5] 这条 assistant 消息本来也是逐轮字节一致的稳定历史，却被排除在缓存前缀之外，每步全价重发。断点要打在稳定前缀的**最远端**。
- `dropped = 3`：**一个都不打**。头部被驱逐后前缀相对上一轮已位移，打标只写不读，净付 1.25x 写溢价；跳过打标让最坏情况与"没有这个优化"持平。
</details>

## 5. 自测题（答案在文末）

1. 缓存键包含哪些部分？为什么预热请求的 `tools` 必须与真实 worker 字节一致？
2. 断点 #2 为什么不增加缓存写量？
3. 迭代双断点 + system 一共 3 个断点，为什么不把第 4 个也用掉（比如打在最后一条 tool result 上）？
4. 为什么本地 `pnpm test` 验证不了缓存效果？在这个仓库里应该看什么来确认命中率？
5. `trimMessagesToBudget` 为什么必须"成组丢弃"assistant(tool-call) 和它的 tool(result)？

## 6. 与下一站的衔接

缓存解决"重发的钱"；但如果模型循环本身失控——无限重试、卡死不返回、工具结果撑爆窗口——再好的缓存也兜不住。第 6 站看这套系统的**护栏**：成功才停的 stopWhen 谓词、分池的重试预算、两级超时看门狗、工具结果硬截断。

---

### 自测题答案

1. `tools + system + messages 各 content part（直到断点 part 为止）`。tools 在缓存键里，预热请求的 tools 与真实 worker 差一个字节，前缀就对不上，写好的缓存读不回——白付 1.25x。
2. 服务端写缓存写到**最远断点**处；#2 与 #1 在同一条前缀的延长线上（#2 圈的内容包含 #1 圈的），所以写量由最远断点决定，加 #2 不变。
3. 最后一条 tool result 每步都不同，不构成任何请求间共享的稳定前缀——打上去只写不读，纯亏写溢价。断点只值得打在"下次请求还会以相同字节出现"的位置。
4. 本地测试走 mock/fake adapter，请求根本不经过 Anthropic/Vertex，没有缓存这回事。要看真实 Cloudflare AI Gateway 账单或 LangSmith usage 里的 `cache_read_input_tokens` / `cache_creation_input_tokens`（提交信息里的"write 5443→read 5443"就是这么来的）。
5. Anthropic API 要求 tool_result 必须紧跟对应的 tool_use；从头部丢消息若只丢了 assistant(tool-call) 留下孤儿 tool-result，请求直接报错。所以裁剪必须保持配对原子性。
