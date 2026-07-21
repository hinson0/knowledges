# VCP 上下文工程 · 第 6 站：护栏与降级

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 这是收官站：前 5 站解决"上下文放什么、怎么记、怎么省"，本站解决"失控时怎么兜住"——循环终止、超时、重试预算、结果截断。文末有全线回顾。

## 0. 本站要解决的问题

一个带工具循环的 LLM agent 有四种典型失控方式：

1. **停不下来**——模型反复失败重试，步数烧穿；
2. **卡死**——provider 不再吐字，流永远挂起；
3. **重试预算被错误的失败类型烧光**——一次"忘了先 read"的小失误消耗了真正编辑失败的修复机会；
4. **工具结果撑爆窗口**——一次 grep 命中一万行，直接顶穿上下文预算。

VCP 对每一种都有一个显式护栏，且所有护栏共享一个设计哲学：**失败喂回模型自纠（在预算内），预算耗尽如实收口为失败；护栏自身绝不成为新的挂起点**。

## 1. 核心代码导读

### 1.1 循环终止："成功才停"谓词族

文件：`apps/agent/src/agents/workspace/workspace-stop-conditions.ts`（94 行，可通读）。头注释先声明了设计家族：

```
All predicates here belong to the same success-only design family: a
condition fires only when the model completed an action successfully, so
the loop keeps running on failures and lets the model self-correct within
its step budget.
```

三个谓词，全部是"只认成功"：

```ts
// :24-41 —— patch 成功才停；failed 结果不停，让模型在步预算内重试
export function hasAppliedPatchBatchResult() {
  return ({ steps }) => {
    const lastStep = steps[steps.length - 1];
    return lastStep?.toolResults?.some((toolResult) => {
      if (toolResult.toolName !== "apply_patch_batch") return false;
      const parsed = ApplyPatchBatchResultSchema.safeParse(toolResult.output);
      return parsed.success && parsed.data.status === "applied";  // ← 只认 applied
    }) ?? false;
  };
}
```

```ts
// :56-72 —— 只有 schema 校验通过的 ask_user_clarification 才停
toolCall.toolName === "ask_user_clarification" && toolCall.invalid !== true
// :80-93 —— complete_task 同款：invalid 调用不停，让模型自纠
```

两个关键认知：

- **为什么不是"步数到了就停"**：`stepCountIs(N)` 会在模型刚好失败的那一步一刀切断，用户拿到的是半成品；"成功才停"让失败结果作为 tool result 喂回模型，模型读诊断、修正、重发——步数上限只是**兜底硬止血**，不是正常终止方式。迭代主循环的实际组合（`workspace-websocket.service.ts:4585-4589`）：`stopWhen: [stepCountIs(maxSteps), hasCompleteTaskToolCall(), hasValidClarificationToolCall()]`；首生 section worker 是 `[hasAppliedPatchBatchResult(), stepCountIs(6)]`。
- **为什么要过滤 `invalid: true`**：AI SDK 对 zod 输入校验失败的 tool-call 会写入 `invalid: true` 标记；裸的 `hasToolCall("ask_user_clarification")` 按名字匹配会连非法调用也停——模型就失去了消费校验失败信息、自纠的下一步。这是一个"框架默认行为在 agent 场景下是坑"的实例。

### 1.2 超时看门狗：两级计时 + race 兜底 + 弃读排空

文件：`apps/agent/src/agents/workspace/timeout-stream-text.ts`（270 行）。它包裹 `streamText`，注入两级看门狗：

- **`chunkMs`**：相邻两个流 part 之间的最大等待——"多久没有新东西出来就算卡死"；
- **`totalMs`**（可选）：从流开始的总时长上限。

三个精妙之处：

**① race 兜底（`:191-221`）**——不信任 provider 会响应 abort：

```ts
const raced = await Promise.race([
  innerIterator.next().then((r) => ({ kind: "next", r })),
  abortAwaiter.then(() => ({ kind: "aborted" })),
]);
```

即使底层 `inner.next()` 对 abortSignal 无反应（网络层挂死），超时后 race 也立即从 `abortAwaiter` 分支退出。**护栏不能依赖被守护对象的配合**。

**② chunkMs 的计时语义（`:183-188` 注释）**——覆盖的是"上一个 part 到下一个 part 的整段间隔"，**包含下游工具执行时间**，不只是模型空闲。所以 chunkMs 不能小于单次工具执行的合理上限，否则工具正常跑着就被误杀。

**③ 弃读排空 `drainAbandonedInner`（`:37-80`）**——消费者提前 return/throw 时，AI SDK v6 的惰性管线若被直接弃读，telemetry span 永不收口（LangSmith 上整个 run 的子 span 全部孤儿化，这是 2026-06-10 一次真实排障的根因）。排空自身也有软上限 2s（abort 止损）+ 硬上限 5s（放弃，span 泄漏退化为旧行为）——**连"收尾清理"都不允许无限等**。

超时值分路径配置（`workspace-websocket.service.ts:213-225`），注释直接写明了理由：

```ts
const DEFAULT_WORKSPACE_MODEL_TIMEOUT = { chunkMs: 90_000 };   // 迭代：只有空闲超时
// 首轮全站生成是一次合法的多分钟构建……迭代只用 chunkMs 作为"无新事件"的空闲超时，
// 不设置 totalMs，避免模型持续调用工具时被固定总时长误杀。
const DEFAULT_WORKSPACE_INITIAL_GENERATION_TIMEOUT = { totalMs: 1_200_000, chunkMs: 1_200_000 };
```

**为什么迭代不设总超时**：迭代的合法时长方差极大（1 步 vs 24 步、每步可能带真实的 sandbox 工具执行）。固定 totalMs 要么设太长失去意义，要么误杀长而健康的 run。真正要防的是"卡死"（没有新事件），90s 空闲超时精准对应这个故障模式。**超时要对准故障模式，不是对准时长直觉。**

### 1.3 重试预算：分池计数，互不挪用

`workspace-websocket.service.ts:232-252` 的常量区是一张"预算分池表"，每个常量的注释都写明了为什么单开一池：

```ts
const MAX_PATCH_REPAIR_ATTEMPTS = 2;        // 真正的编辑失败修复预算
const MAX_WORKER_PATCH_FAILURES = 2;        // 首生 worker 同轮自修复（对齐上者，独立计数）
const MAX_READ_GATE_ATTEMPTS = 3;           // "未先 read"前置门——不是编辑失败，
                                            // 不该烧 MAX_PATCH_REPAIR_ATTEMPTS 的编辑预算
const MAX_SPLIT_GUARD_ATTEMPTS = 4;         // 一文件一调用拆批守卫——有意进度信号，同理单开
const MAX_TOOL_ERROR_FEEDBACK_ATTEMPTS = 2; // 其余工具的 zod 校验失败喂回（per-run 全局共享）
```

设计逻辑：失败有**类型**——"忘了先 read"（教育一下就好）、"拆批提醒"（甚至不算错）、"真正的编辑失败"（昂贵、值得修复预算）、"参数 schema 写错"（模型笔误）。**不同类型的失败共享一个计数器时，廉价失败会挤占昂贵失败的修复机会**，把本可自愈的 run 提前判死。分池后每类失败有自己的自愈上限，耗尽才如实收口。

步数与输出上限（`:259-264` 及 `workspace-model-output-limits.ts`）：

```ts
const DEFAULT_ITERATION_MAX_STEPS = 24;
const DEFAULT_ITERATION_ONE_FILE_PER_CALL_MAX_STEPS = 48;  // 一文件一调用时"加3页"≈26步，24 会顶穿
const DEFAULT_INITIAL_GENERATION_MAX_STEPS = 48;
// 迭代单轮输出 32K、worker/repair 60K——显式设值是因为经网关的 Vertex 形态 model id
// 不在 @ai-sdk/anthropic 内置能力表里，缺省会退化到 4096，把大 patch 截断丢弃
```

最后一条是个隐蔽的坑：**输出上限没显式设时，SDK 按内置模型表取默认值；自定义网关的 model id 不在表里 → 4096 → 大文件 patch 被静默截断**。

### 1.4 工具结果硬截断：上限 + `truncated` 标志，不做二次摘要

文件：`apps/agent/src/agents/workspace/workspace-patch-runtime.service.ts`。关键行：

| 工具 | 默认上限 | schema 硬上限 | 位置 |
|---|---|---|---|
| read（单/多文件） | `max_bytes ?? 60_000` 字节，超出 `subarray(0, maxBytes)` 截断 | 200_000 | `:777-791`、`:2631` |
| grep | `max_matches ?? 50` 条命中即 break；每条 `preview: line.slice(0, 240)` | 200 | `:964-1012` |
| glob/list | `limit ?? 200` 条 | 500 | `:727-735`、`:920` |

所有截断都回传 `truncated: true` 标志。**取舍：为什么硬截断而不是"用小模型摘要一下再喂回"？**

- 截断是**确定性、零成本、零延迟**的；LLM 摘要引入新的调用（钱+延迟）、新的失败点、以及最糟的——**摘要幻觉**（摘要器漏掉关键行，主模型基于失真信息做编辑决策）；
- `truncated: true` 让模型**知情**：需要更多内容时可以带更精确的参数（更窄的 grep、指定 max_bytes）再读一次——把"要多少上下文"的决策权还给模型，而不是由一个摘要器替它做主；
- 同款思路也用在历史管理上：第 5 站的 110K 预算裁剪是"丢最旧 + 保配对"的窗口裁剪，同样不做 LLM 压缩（`compaction` intent 在 `model-config.ts` 里定义了 Haiku 档位，但全仓零调用方——刻意留白的未来选项）。

## 2. 动手实践

### 实践 a：跑护栏单测（已验证可运行）

```bash
cd ~/ce_repos/vcp/apps/agent
pnpm exec vitest run src/agents/workspace/workspace-stop-conditions.test.ts src/agents/workspace/timeout-stream-text.test.ts
# 预期：2 个文件、25 个测试全绿，约 1.5s
```

重点读 `workspace-stop-conditions.test.ts` 里 `invalid` 相关用例（`:59-99` 附近）：它们锁死"schema 校验失败的 tool-call 不触发停止"这一行为——这正是 §1.1 讲的框架默认行为陷阱的回归锁。
`timeout-stream-text.test.ts` 则值得看它怎么**测试超时**：用假的 AsyncIterable 模拟"永不吐 part 的 provider"，断言 race 兜底在 chunkMs 后 yield 出 abort part。

### 实践 b：纸面练习——用常量表估算一轮迭代的最坏 token 成本

已知：迭代 `DEFAULT_ITERATION_MAX_STEPS = 24`；某轮请求的稳定前缀（system + 历史 + 注入 + 当前 user）≈ 30K tokens；每步平均新增（assistant tool-call + tool result）≈ 1K tokens；忽略输出侧。

问：跑满 24 步时，(1) 无任何缓存断点、(2) 有第 5 站的双断点（假设全部命中），输入侧计费 token 各约多少？差多少倍？

<details><summary>答案（量级估算）</summary>

- **无缓存**：第 k 步重发 `30K + (k-1)×1K`。总计 ≈ 24×30K + (0+1+…+23)×1K ≈ 720K + 276K ≈ **996K 全价 tokens**。
- **双断点全命中**：step1 写 30K（×1.25 ≈ 37.5K 等效）；step k≥2 读回前缀（30K×0.1=3K 等效）+ 新增部分全价（平均约 12K 累计尾部……粗略按每步读 3K + 新增 fresh 1~23K 递增再被后续步读回——保守估算总等效 ≈ 37.5K + 23×3K + 276K×0.1~0.3 ≈ **150K~200K 等效 tokens**。
- 量级结论：**约 5~7 倍差距**。这就是提交信息里"砍迭代 token 成本"的数学来源；精确数字不重要，重要的是看到"每步重发前缀"在多步循环里是平方级累积，而缓存把它压回近线性。
</details>

### 实践 c：考古"护栏为什么长这样"

```bash
cd ~/ce_repos/vcp
git log --oneline --grep="喂回\|超时\|看门狗\|stopWhen" | head
git log -1 --format=%B $(git log --format=%H --grep="工具 tool-error 喂回容错已泛化" -1 2>/dev/null || echo HEAD) 2>/dev/null | head -20
```

也可直接在 `docs/context/CURRENT_STATUS.md` 里搜「run_b9a94e44」——那段记录了 `MAX_TOOL_ERROR_FEEDBACK_ATTEMPTS` 的由来：模型对 `connect_form` 输出空参数 `{}`，被旧的按工具名特判的通杀分支杀成不可重试死局；修复是把"工具校验失败喂回"**泛化成统一机制**而不是继续加特判——护栏演化的典型路径：事故 → 特判 → 第三次同款事故 → 泛化成结构性机制。

## 3. 自测题（答案在文末）

1. "成功才停"设计下，`stepCountIs(24)` 在 stopWhen 数组里的角色是什么？
2. 为什么 `ask_user_clarification` 的停止谓词必须检查 `invalid !== true`？
3. 迭代路径为什么只设 90s chunkMs、不设 totalMs？首生路径为什么反过来两个都设 20 分钟？
4. read-gate（"未先 read 就 str_replace"）的重试为什么不计入 `MAX_PATCH_REPAIR_ATTEMPTS`？
5. 工具结果为什么用硬截断 + `truncated` 标志，而不是用 Haiku 把超长结果摘要后喂回？

## 4. 全线回顾：六站串回四个子问题

| 子问题 | 站点 | 核心机制 | 一句话心法 |
|---|---|---|---|
| ① 放什么 | 第 1、4 站 | 红线常量 + 分层拼装 + 守卫测试；skill 只放一行索引 | prompt 即代码，规则是常量，漂移是可测试的缺陷 |
| ② 放哪里 | 第 1、3 站 | 静态进 system/staticPrefix；动态全部集中到最新 user 消息 | 稳定的在前，多变的在后——为缓存和注意力同时服务 |
| ③ 怎么记住 | 第 2、3 站 | 事件溯源有损落库 + 回放期确定性重建 + 从权威源重读补偿 | 持久层存"发生过什么"，不存"内容本身"；有损必须显式（stale 占位符） |
| ④ 怎么省 | 第 5 站 | 110K 预算裁剪 + 双断点 + 并发预热 | 断点打在稳定前缀最远端；最坏情况钉在与现状持平；数据闭环驱动 |
| （兜底）失控怎么办 | 第 6 站 | 成功才停 + 分池重试预算 + 两级看门狗 + 硬截断 | 失败喂回自纠、预算耗尽如实失败；护栏不依赖被守护者的配合 |

贯穿全线的三条元原则：

1. **确定性优先**：能用纯函数/常量/硬截断解决的，不引入 LLM（重建消息、裁剪、截断全是确定性的；LLM 压缩留作未来选项）。
2. **fail-soft，永不成为单点**：skill 索引读失败、注入失败、缓存预热失败、排空超时——一律降级继续，上下文工程组件的故障绝不阻断用户主流程。
3. **可观测闭环**：cf-aig-metadata 打标、LangSmith trace、缓存命中率数据——每个优化都始于测量、终于复测。

---

### 自测题答案

1. **兜底硬止血**，不是正常终止方式。正常终止靠 `hasCompleteTaskToolCall` / `hasValidClarificationToolCall`（成功信号）；步数上限只防"模型反复失败也停不下来"的退化，触发它意味着 run 大概率以失败收口。
2. AI SDK 对 zod 校验失败的 tool-call 打 `invalid: true` 但仍计入 step 内容；按名字裸匹配会让非法调用也终止循环，模型失去读取校验错误、修正参数重发的机会——一次笔误直接杀死整轮。
3. 迭代的故障模式是"卡死"（无新事件），空闲超时精准对应；总时长方差太大，totalMs 会误杀长而健康的多工具 run。首生是一次结构可预期的"多分钟构建"，两个大文件之间可能静默 30s+，短 chunkMs 会误判卡死，所以用宽松的 20 分钟做纯安全网。
4. read-gate 是前置纪律门，不是编辑能力失败——模型只需先 read 再重发同一 patch 即可恢复。让它烧编辑修复预算，会导致"忘了 read 两次 + 真实编辑失败一次"就把本可自愈的 run 判死。失败类型不同，预算池必须隔离。
5. 摘要引入额外调用成本、延迟和新失败点，且摘要幻觉会让主模型基于失真信息做编辑决策；硬截断是确定性零成本的，`truncated: true` 让模型知情并自主决定是否用更精确的参数重读——把上下文取舍的决策权留给主模型。
