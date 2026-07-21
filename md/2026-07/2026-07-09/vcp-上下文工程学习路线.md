# VCP 上下文工程学习路线

> 学习对象：`~/ce_repos/vcp`（apps/agent 运行时的 LLM 上下文工程）
> 前置要求：会读 TypeScript；不需要懂 VCP 业务。
> 环境要求：Node 24（`nvm use 24`）+ 仓库根先跑 `pnpm install`，否则单测/脚本跑不起来。

## 配套分站文档（同目录，自包含，含已验证的实践命令与自测题答案）

1. [第1站 · 单次调用的prompt组装](./vcp-上下文工程-第1站-单次调用的prompt组装.md)
2. [第2站 · 事件溯源与消息重建](./vcp-上下文工程-第2站-事件溯源与消息重建.md)（最重要的一站）
3. [第3站 · skill系统与按需加载](./vcp-上下文工程-第3站-skill系统与按需加载.md)
4. [第4站 · system-prompt分层组装与守卫测试](./vcp-上下文工程-第4站-system-prompt分层组装与守卫测试.md)
5. [第5站 · prompt缓存断点与成本工程](./vcp-上下文工程-第5站-prompt缓存断点与成本工程.md)
6. [第6站 · 护栏与降级（含全线回顾）](./vcp-上下文工程-第6站-护栏与降级.md)

分站文档内的命令均已实机验证；本文下方各站小节里的行内命令若与分站文档不一致，以分站文档为准。

## 〇、心智模型：只有一个问题

LLM 是无状态的：**每次调用，你发给它什么，它就只知道什么**。
所谓"上下文工程"，就是回答一个问题：

> **这一次模型调用，上下文窗口里到底放什么？**

它分解成四个子问题，VCP 的所有机制都是在回答其中某一个：

| 子问题 | 难点 | VCP 的答案（机制） |
|---|---|---|
| ① 放什么 | 规则太多，全放会淹没模型 | 分层：红线常量常驻 / skill 索引常驻、全文按需 |
| ② 放哪里 | system、历史、最新消息各承担什么 | 静态进 system 和 staticPrefix，动态进最新 user 消息 |
| ③ 怎么记住 | 模型无状态，上一轮的事这一轮怎么办 | 事件溯源落库（有损）+ 每轮从事件流重建 messages |
| ④ 怎么省 | 窗口有限、token 按量计费 | 预算裁剪、工具结果截断、prompt 缓存断点 |

**学习顺序就按 ①→④ 走，从最简单的一次性调用，走到多轮迭代的完整体系。**

---

## 第 1 站：一次最简单的模型调用（约 30 分钟）

**目标**：看懂"prompt 不是一篇文章，是一次函数调用的返回值"。

读两个文件（都不长）：

1. `apps/agent/src/agents/prompt-redlines.ts`（~100 行，整个体系的最小内核）
   - 红线常量：`SECURITY_REDLINE`、`WORKSPACE_WRITE_REDLINE` —— 规则是**导出常量**，不是散落在字符串里
   - `PROMPT_DYNAMIC_BOUNDARY`：一行文本标记"这条线以下每次请求都不同"
   - `composeUserPrompt({staticPrefix, dynamicSuffix})`：把 user prompt 拆成"稳定前缀 + 动态尾部"
   - `cacheableSystem()`：把 system 包上缓存标记（第 5 站再深究）
2. `apps/agent/src/agents/clarify/clarify.service.ts` 里的 `buildClarifySystemPrompt` / `buildClarifyPrompt`（约 :1135-1194）
   - 这是最简单的 agent：单次 `generateObject`，没有历史、没有工具循环
   - 观察 dynamicSuffix 里放的是什么（brief 原文、locale 指令）

**自测**：为什么 brief 要放 dynamicSuffix、工具/规则说明放 staticPrefix？
（答案方向：brief 每个站点都不同，放前面会让每次请求的"公共前缀"从第一个字节就分叉，缓存全废。）

---

## 第 2 站：多轮对话的记忆问题（约 1-2 小时，最重要的一站）

**目标**：理解"模型无状态"下多轮记忆的两种做法，以及 VCP 为什么选难的那种。

先想清楚天真做法：把每轮完整的 messages（含工具返回的文件全文）原样存数据库，下轮取出来接着用。问题：存储爆炸、落库副本会过期（文件后来又被改了）、无法给前端做轻量回放。

VCP 的做法是**两套表示**：

- **内存侧**：AI SDK `streamText` 循环里的 `ModelMessage[]`，含工具完整输出——只活在单个 run 内
- **持久侧**：`agent_events` 表，append-only 事件日志——**有损**：工具结果只存一行摘要（`result_summary`），文件全文/skill 全文从不落库

每轮新对话时从事件流**重建** messages。读这两个文件：

1. `packages/contracts/src/index.ts` 搜 `AgentEventSchema`（:2183 附近）——看事件类型：`user.message` / `message.delta` / `tool.started` / `tool.finished`
2. `apps/agent/src/agents/workspace/build-model-messages.ts`（核心！先读顶部 :21-34 的注释，再读主折叠循环）
   - `tool.started/finished` 如何配对折叠回 tool-call + tool-result
   - **:178-189**：历史读工具的结果被替换成 stale 占位符 `[历史读取结果正文已不在上下文，需要时重新调用...]`
   - **:106-171**：澄清问答的三态归并（pending/answered/abandoned）

**自测**：
- 为什么历史 read 结果换成占位符而不是保留原文？（存储 + 过期 + 模型可自行重读）
- 为什么占位符必须**显式说明**"正文不在了"，而不是直接删掉那条消息？（静默有损 → 模型基于一行摘要幻觉文件内容）

---

## 第 3 站：大块知识怎么进上下文——skill 系统（约 1 小时）

**目标**：学会"索引常驻 + 全文按需 + 跨轮补偿"这个三段式（Claude Code 同款范式）。

读四个文件，按数据流顺序：

1. `skills/page-editing/motion-and-scroll/SKILL.md` —— 看 frontmatter（name/description/model_invocable）；注意 description 是一段含正反向触发条件的长句（"Use when... Do NOT use for..."）
2. `apps/agent/src/knowledge/skills/fs-skill-source.ts` —— `listModelInvocableSkills()`：扫盘 + 进程缓存 + 单文件损坏跳过（fail-soft）
3. `apps/agent/src/agents/workspace/tools/load-skill.tool.ts` —— 返回 `{summary, content}`：content 是本轮模型可见的全文；summary（`Launching skill: X`）是**唯一落库的东西**
4. `apps/agent/src/agents/workspace/workspace-loaded-skills.ts` —— 下一轮的补偿：从落库摘要解析出"加载过哪些 skill"，**从磁盘重读 fresh 正文**，前置注入最新 user 消息（只进内存，不回写数据库）

**自测**：
- skill 全文为什么不落库？（磁盘就是权威源，落库=第二事实源+会过期）
- 下一轮模型还"记得"skill 吗？靠什么？（不靠持久化，靠回放期确定性重注入）
- `LOADING_SKILL_SUMMARY_PREFIX` 为什么必须是 producer/consumer 共享常量？（摘要格式漂移 → 重注入静默失效）

---

## 第 4 站：system prompt 的分层组装（约 1 小时）

**目标**：看懂"prompt 即代码"——规则是常量、拼装是函数、一致性靠测试。

1. `apps/agent/src/agents/workspace/workspace-domain-contract.ts` —— 三组硬规则常量，被首轮生成和迭代 prompt **两端同时消费**
2. `apps/agent/src/agents/workspace/workspace-websocket.service.ts:8839` `buildWorkspaceSystemPrompt` —— 看拼装顺序：红线 → 契约展开 → 条件措辞 → 末尾追加 skill 索引段（无条件）+ CMS 段（绑定才有）
3. **守卫测试**（这一站的精华）：`workspace-domain-contract.test.ts:107` —— 逐行断言每条红线同时出现在两个 prompt 里；`workspace-system-prompt.test.ts` —— 锁条件段的双态

**自测**：CMS 段按 `cmsSiteId` 决定注入与否，但段内容为什么刻意不含 site id 值？
（答案方向：缓存分桶数 = 布尔组合数，而不是站点数。）

---

## 第 5 站：成本工程——prompt 缓存断点（约 1-2 小时）

**前置知识**（先搞懂再看代码）：Anthropic prompt caching 按**最长公共前缀**匹配；缓存写付 1.25x 溢价、读只付 0.1x；最多 4 个断点；断点打在"稳定前缀的最远端"才有价值。

1. `apps/agent/src/agents/workspace/workspace-context-window.ts`（~160 行短文件）
   - `WORKSPACE_CONTEXT_TOKEN_BUDGET = 110_000`：预算裁剪
   - `markIterationHistoryCacheBreakpoint`：迭代双断点——#1 打在最新 user 的**前一条**（跨轮历史），#2 打在**当前 user**（本轮注入块）
   - 首行 `if (dropped > 0) return`：发生头部驱逐时前缀已位移，打标只亏写溢价
2. 看两个真实提交（带实测数据，是最好的教材）：
   - `git show 60a3249b`：迭代历史断点 + section 并发预热（命中率 8% → 全 READ）
   - `git show 5ffdaff3`：轮内第二断点（tool 循环每步重发 ~19K 注入块的问题）
3. `apps/agent/src/agents/workspace/workspace-cache-prime.ts`：fan-out 前发一次 `maxOutputTokens: 1` 的预热请求，先把共享前缀写进缓存

**自测**：
- 断点 #2 为什么不打在 tool 结果之后？（tool 结果每步都变，不构成稳定前缀）
- 预热请求为什么只要 1 个输出 token？（目的只是让服务端 prefill 并 commit 缓存前缀）

---

## 第 6 站（可选）：护栏与降级

- `workspace-stop-conditions.ts`：stopWhen 谓词是"**成功才停**"（失败结果喂回模型自纠），`stepCountIs` 只是止血兜底
- `timeout-stream-text.ts`：90s chunk 空闲看门狗；迭代刻意不设总超时（长工具链会被误杀）
- `workspace-patch-runtime.service.ts`：工具结果硬截断 + `truncated` 标志（read 默认 60KB、grep 50 命中），**不做二次 LLM 摘要**
- 各类有界循环：`MAX_PATCH_REPAIR_ATTEMPTS=2`、`MAX_TOOL_ERROR_FEEDBACK_ATTEMPTS=2`

---

## 动手实验（比读代码更有效）

**实验 A：体验守卫测试怎么锁 prompt**（完整步骤见第 4 站文档，已实测）
把 `workspace-domain-contract.ts` 里任意一条红线行改一个词 → 跑
`cd apps/agent && pnpm exec vitest run src/agents/workspace/workspace-domain-contract.test.ts` → 看测试怎么红 → `git checkout --` 恢复 → 复跑确认绿。
体感：prompt 漂移在这个仓库是测试期可捕获的缺陷。
（注意：`pnpm --dir apps/agent test -- <文件>` 的过滤参数会被忽略、跑成全量；单文件必须用 `exec vitest run` 形式。）

**实验 B：体验 skill 索引的动态性**（完整步骤见第 3 站文档，已实测 7→8→7）
在 `skills/page-editing/` 下新建一个 `my-test-skill/SKILL.md`（抄 motion-and-scroll 的 frontmatter，`model_invocable: true`）→ 用 tsx 脚本调 `listModelInvocableSkills()` 确认新 skill 入列 → 删掉 → 再跑确认消失。
注意 FsSkillSource 有进程级缓存，增删前后必须是两个独立进程。
体感：索引是扫盘动态生成的，加 skill 不需要改任何注册代码。

---

## 一句话总结

这套体系的骨架是：**常驻的进 system（红线+索引），大块的按需拉（load_skill/read 工具），跨轮的靠事件流有损落库 + 回放期从权威源重建补偿，所有钱的问题靠"保住最长稳定前缀"的缓存断点解决，所有增强组件 fail-soft 不阻断主流程。**
