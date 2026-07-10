# VCP 上下文工程 · 第 2 站：事件溯源与消息重建（多轮记忆的核心）

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 前置：已读第 1 站（单次调用的 prompt 组装）。本站是六站中最重要的一站——它回答"模型无状态，多轮对话怎么记住之前的事"。

---

## 0. 本站要解决的问题

LLM 是无状态的。工作台（Workspace）是多轮的：用户第 1 轮说"把首页 hero 改成深色"，模型读了文件、打了 patch、回了话；第 2 轮用户说"再把按钮换成圆角"——**这一轮的模型调用里，第 1 轮发生的事怎么进上下文？**

### 先推演"天真做法"会死在哪

最直接的方案：把第 1 轮结束时的完整 `messages` 数组（含工具返回的文件全文）原样序列化存数据库，第 2 轮取出来接着 append。它会死在四个地方：

1. **存储爆炸**：每轮工具会读回几十 KB 的文件正文、grep 命中、skill 全文。全部落库，一个活跃站点的历史很快到 MB 级，而且绝大部分内容磁盘/快照里本来就有——存的是冗余副本。
2. **副本过期**：落库的文件正文是"读取那一刻"的内容。后续轮次文件又被改了，库里的旧正文变成**过期的第二事实源**——模型基于它做编辑就是基于错误认知改代码。
3. **无法支撑前端回放**：前端刷新页面后要重建聊天时间线（谁说了什么、调了什么工具、进度如何）。完整 messages 是给模型看的形状，不是给 UI 看的形状；两个消费方硬共用一份全量数据，谁都不好用。
4. **断线恢复会重跑模型**：如果"恢复会话"意味着"把 messages 拿回来重新发起推理"，那刷新一次页面就可能重复触发一次昂贵且有副作用的模型运行。

### VCP 的答案：两套表示，单向转换

| | 内存侧（AI SDK） | 持久侧（agent_events 表） |
|---|---|---|
| 形态 | `ModelMessage[]`，含工具**完整输出** | append-only 事件日志，工具结果只有**一行摘要** |
| 生命周期 | 只活在单个 run 的 `streamText` 循环内 | 跨 run 永久保存 |
| 消费方 | 模型 | 前端时间线回放 + 下一轮重建模型消息 |
| 保真度 | 全量 | **刻意有损** |

每轮新对话开始时，从事件流**确定性重建**模型消息（纯函数 `buildModelMessages`），有损的部分靠"回放期从权威源重读"来补偿（第 3 站细讲）。本站讲清楚这条链路的四个环节：落库 → 去重与序号 → 游标回放 → 折叠重建。

---

## 1. 核心代码导读

### 1.1 持久层：`agent_events` 表（`apps/api/src/db/schema.ts:548-591`）

```ts
export const agentEvents = pgTable(
  "agent_events",
  {
    id: text("id").primaryKey(),
    tenant_id: text("tenant_id").notNull().references(() => tenants.id),
    site_id: text("site_id").notNull().references(() => sites.id),
    agent_run_id: text("agent_run_id").notNull().references(() => agentRuns.id),
    sequence: integer("sequence").notNull(),
    event_type: text("event_type").notNull(),
    payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
    client_message_id: text("client_message_id"),
    created_at: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("agent_events_run_sequence_idx").on(table.agent_run_id, table.sequence),
    uniqueIndex("agent_events_client_msg_idx")
      .on(table.agent_run_id, table.client_message_id)
      .where(sql`client_message_id IS NOT NULL`),
    // ...
    index("agent_events_site_sequence_idx").on(table.tenant_id, table.site_id, table.sequence),
  ],
);
```

三个索引各管一件事：

- `(agent_run_id, sequence)` **唯一**索引——run 内事件序号单调且不重复，这是"游标续传"和"回放顺序"的地基；
- `(agent_run_id, client_message_id) WHERE client_message_id IS NOT NULL` **partial 唯一**索引——用户消息幂等去重的**数据库级**保障（应用层预检只是优化，最终防线在这）；
- `(tenant_id, site_id, sequence)` 普通索引——支撑**跨 run** 的站点级历史拉取（下一轮迭代重建模型消息用它）。

### 1.2 事件合同：判别联合（`packages/contracts/src/index.ts`）

`AgentEventSchema = z.discriminatedUnion("type", [...])`（:2183）。跟本站相关的三个分支：

```ts
// :2194-2201 —— 用户消息
z.object({
  type: z.literal("user.message"),
  client_message_id: z.string().min(1),      // 幂等去重键（客户端生成）
  message_id: z.string().min(1),
  parts: z.array(AiSdkUiMessagePartSchema).min(1),
  in_reply_to_tool_call_id: z.string().min(1).optional(),  // 回答澄清问题时关联 tool_call
  at: z.string().min(1),
}),
// :2287-2300 —— 工具事件
z.object({
  type: z.literal("tool.started"),
  tool_call_id: z.string().min(1),
  name: z.string().min(1),
  summary: z.string().min(1),          // 静态工具描述
  at: z.string().min(1),
}),
z.object({
  type: z.literal("tool.finished"),
  tool_call_id: z.string().min(1),
  name: z.string().min(1),
  result_summary: z.string().min(1),   // ← 持久化的只有这一行摘要！
  at: z.string().min(1),
}),
```

**看清关键点**：`tool.finished` 的 payload 里根本没有"完整工具输出"这个字段。文件正文、grep 命中、skill 全文在 schema 层面就进不了数据库——有损不是运行时省略，是**合同级设计**。

### 1.3 写入：序号生成 + 幂等去重（`apps/api/src/agent-runs/agent-runs.repository.ts`）

`appendAgentEvent` 全程在一个事务里，先 `FOR UPDATE` 锁 run 行，然后：

```ts
// :142-164 —— user.message 按 (run_id, client_message_id) 预检去重：
// 命中直接返回 duplicate_ignored，避免 onConflictDoNothing 命中时白白消耗一个 sequence
if (client_message_id) {
  const [existing] = await tx.select().from(agentEvents).where(...).limit(1);
  if (existing) return { status: "duplicate_ignored", ... };
}

// :166-172 —— 序号 = 当前 run 的 max(sequence) + 1
const [latestEvent] = await tx.select({ sequence: agentEvents.sequence })
  .from(agentEvents).where(eq(agentEvents.agent_run_id, input.run_id))
  .orderBy(desc(agentEvents.sequence)).limit(1);
const sequence = (latestEvent?.sequence ?? 0) + 1;

// :187-191 —— 插入时再挂 onConflictDoNothing 兜底并发窗口
.onConflictDoNothing({
  target: [agentEvents.agent_run_id, agentEvents.client_message_id],
  where: sql`client_message_id IS NOT NULL`,
})
```

插入返回 0 行时（两个事务同时通过了预检的极小窗口），补查已存在行返回 `duplicate_ignored`；若 `client_message_id` 为空却插入 0 行，说明不变式被违反，**直接抛错**（:193-226）——防御性代码把"不可能发生"显式写成断言。

去重语义还上升到了契约层：`AppendAgentEventResponseSchema` 是 `status: "appended" | "duplicate_ignored"` 的判别联合，调用方能区分"写入了"和"早就写过了"。

为什么用户消息需要幂等？前端 WebSocket 断线重连、用户双击发送、HTTP 重试——同一条消息可能被投递多次。`client_message_id` 由**客户端**生成并随消息携带，服务端只认第一次。

### 1.4 读取之一：`after_sequence` 游标续传（回放不重跑模型）

```ts
// agent-runs.repository.ts :264-275 —— 按序号取增量
const rows = await tx.select().from(agentEvents)
  .where(and(
    eq(agentEvents.tenant_id, input.context.tenant_id),
    eq(agentEvents.agent_run_id, input.run_id),
    gt(agentEvents.sequence, input.after_sequence),   // ← 游标
  ))
  .orderBy(asc(agentEvents.sequence))
  .limit(input.limit);
```

暴露为 `GET /agent-runs/:run_id/events?after_sequence=N`（`agent-runs.controller.ts:117-124`）。前端的用法：

- **刷新重进**：从 `after_sequence=0` 拉全量事件，重建整个聊天时间线——**纯读，不触发任何模型运行**；
- **断线续传**：WebSocket 断开时前端**不**当作 run 失败，转 HTTP 用上次的 `next_cursor` 继续拉，直到读到 `run.finished`/`run.failed` 终态事件（`apps/web/src/lib/real/workspace-socket.ts:317` 附近）；
- run 还在跑：非终态就带游标轮询续传——因为 run 的执行在服务端是 detach 的后台任务，连接只是"观看窗口"，断开观看不影响执行。

这就是"事件溯源"对上下文工程的第一重价值：**UI 状态 = 事件流的确定性投影**，投影可以随时重算，绝不需要重跑昂贵且有副作用的模型。

### 1.5 读取之二：站点级历史（给下一轮模型重建用）

```ts
// agent-runs.repository.ts :291-307 —— 保留"最近 N 条"而非"最旧 N 条"
// 三键必须同向 desc：(created_at, agent_run_id, sequence) 的"尾部 N 升序"
// 严格等价于全键 desc 取 N 再 reverse。
const rows = await tx.select().from(agentEvents)
  .where(and(...conditions))
  .orderBy(desc(agentEvents.created_at), desc(agentEvents.agent_run_id), desc(agentEvents.sequence))
  .limit(input.limit ?? 5000);
return rows.slice().reverse().map(mapAgentEvent);
```

细节里有一个真实教训：早期实现是 `asc + limit`，长寿站点超过 limit 时会**丢最新历史、保远古历史**——模型只看得到几个月前的对话。改成三键全 `desc` 取最近 N 再 reverse，消费侧契约（按时间升序）不变。

### 1.6 折叠重建：`buildModelMessages`（`apps/agent/src/agents/workspace/build-model-messages.ts`）

顶部注释先立规矩（:21-34）：

```ts
/**
 * 把 agent_event 流折叠成 AI SDK 标准 `ModelMessage[]`。
 *
 * - 纯函数，无 I/O，无副作用
 * - fail-soft：遇到无法处理的 payload 直接跳过、不抛错
 *
 *   - `user.message`            → 1 条 user message（仅 text part）
 *   - 连续 `message.delta`      → 合并到上一条 assistant message 的尾部 text part
 *   - `tool.started`/`finished` → 配对生成 assistant.tool-call + tool.tool-result
 */
```

主循环是一个对事件数组的 `switch (payload.type)`（:56-263）。逐条规则：

**① `user.message` → user 消息**（:61-73）：抽出全部 text part 拼接；空文本直接丢弃；`consumedUserMessageIds` 里的跳过（见④）。

**② `message.delta` 合并**（:75-89）：流式输出被持久化成许多小 delta 事件；折叠时若上一条消息是 assistant 且尾部是 text part，就地追加文本，否则新开一条 assistant 消息。持久化按"发生了什么"记录（流式片段），重建按"模型消息该长什么样"合并——两种粒度各自服务自己的消费方。

**③ 工具配对**（:90-104 + :190-215）：`tool.started` 先进 `pendingTools` 暂存，等到同 `tool_call_id` 的 `tool.finished` 才**一次性**产出 tool-call + tool-result 两条消息。有 started 没 finished（run 中途死掉）→ 丢弃；有 finished 没 started → 丢弃。**绝不产出不配对的 tool 消息**——不配对的 tool-call/result 会被模型 API 直接拒绝，这是重建最容易踩的坑。

另外 `shouldReplayToolCall`（:348-354）过滤两类：非模型可见的后端工具（如 `prepare_preview`）不回放；`tool_call_id` 含 provider 不安全字符（如 `toolu_vrtx_abc:xxx`）的不回放；`complete_task` 收尾工具也不回放。

**④ 澄清问答三态归并**（:106-171）——最精巧的一段：

`ask_user_clarification` 的 `result_summary` 恰好是 JSON（问题+选项），折叠时把它 parse 回来当 tool-call 的 `input`（问题原文得以保留），然后**向后扫描**下一条 `user.message` 决定 tool-result 的 output：

```ts
// :122-144（骨架）
let outputValue: unknown = { status: "pending" };                 // 没有后继用户消息
for (let j = i + 1; j < events.length; j += 1) {
  const next = events[j];
  if (!next || next.payload.type !== "user.message") continue;
  if (np.in_reply_to_tool_call_id === payload.tool_call_id) {
    outputValue = { status: "answered", answer };                 // 回答了
    consumedUserMessageIds.add(next.id);                          // ← 该用户消息被"吸收"
  } else {
    outputValue = { status: "abandoned",
      reason: "user proceeded without answering" };               // 问了但用户干了别的
  }
  break;
}
```

效果：**问题（tool-call input）+ 答案（tool-result output）成对自包含**。用户的回答被吸收进 tool-result 后标记 consumed，不会再作为独立 user 消息出现一次——历史里没有"悬空的答案"，模型不需要跨消息猜"Bright 是在回答哪个问题"。

**⑤ 有损折叠的显式化：stale 占位符**（:174-189）：

```ts
// "读且可重取"的工具（read_*/grep/list）跨轮折叠时正文已不在上下文，
// 只剩一行 result_summary（如 "Read N files"）会被模型误当完整结果。
// 改渲染为显式 stale 占位符，提示需要时重读，避免基于陈旧/缺失认知改错。
let outputValue: unknown;
if (isRetrievableReadTool(payload.name)) {
  outputValue = {
    stale: true,
    note: "[历史读取结果正文已不在上下文，需要时重新调用 read_*/grep/list 获取当前内容]",
    summary: payload.result_summary,
  };
} else { /* 其余工具：JSON parse 摘要，parse 不动就 { summary: raw } 兜底 */ }
```

为什么必须显式？考虑静默方案：历史 tool-result 直接放 `"Read 1 file: hero.tsx"`。模型看到这条会**以为自己读过且记得内容**，于是基于（并不存在的）记忆去写 str_replace 的 old_string——必然失败甚至改错。占位符把"有损"变成模型**可感知、可行动**的状态：知道自己不知道，需要就重读。白名单只圈"可重取"的读工具（`read_*`/`grep`/`glob`/`list`），写工具 `apply_patch_batch` 的结果摘要本来就是权威事实（写成功了就是写成功了），不加 stale。

**⑥ 末尾 inline 注入**（:266-294）：折叠完成后，把运行时上下文**前置**到最新一条 user 消息的首个 text part：

```ts
const contextLine = `[Context: site_id=${runtime.site_id} base_snapshot_id=${baseSnap}]`;
// + 可选的 [Attached component context: ...]（用户在画布上选中的组件）
// + 可选的 [Previous preview build failed] / [Previous preview refresh failed] 诊断块
for (let k = messages.length - 1; k >= 0; k -= 1) {
  const m = messages[k];
  if (!m || m.role !== "user") continue;
  firstText.text = `${contextLines.join("\n")}\n\n${firstText.text}`;
  break;   // 只注入最新一条
}
```

**只注入最新一条 user 消息、历史消息保持字节不变**——这是第 5 站缓存断点能成立的前提（历史前缀逐轮字节一致才可缓存）。注入的自由字段全部经 `JSON.stringify` 编码（`quotePromptField`，:390-392），防止组件名/预览文本里藏换行或 `[Context:...]` 字样做 prompt 边界注入（测试 :872-898 专门锁这个）。

### 1.7 两套表示的转换点在哪

`apps/agent/src/agents/workspace/workspace-websocket.service.ts` 每轮迭代入口（约 :1416-1487）：

```
listBySite 拉跨 run 事件流
  → appendCurrentUserMessageEvent（补上当前这轮的用户消息）
  → buildModelMessages(events, runtime)          ← 单向转换：事件流 → ModelMessage[]
  → applyLoadedSkillsReminder(...)               ← 第 3 站：skill 正文补偿注入
  → applyRecentFilesReminder(...)                ← 第 3 站：最近文件现状注入
  → trimMessagesToBudget(...)                    ← 第 5 站：110K token 预算裁剪
  → markIterationHistoryCacheBreakpoint(...)     ← 第 5 站：缓存断点
  → streamText({ system, messages, tools, ... })
```

而 run 执行**过程中**，同一个消费循环边流边投影回事件：`text-delta → message.delta`、`tool-call → tool.started`、`tool-result → summarizeWorkspaceToolResult() → tool.finished`。闭环：内存全量 →（有损投影）→ 事件流 →（下轮确定性重建+补偿）→ 内存。转换永远单向，两套表示互不假装是对方。

---

## 2. 动手实践

> 环境前置（本机已验证）：仓库要求 Node 24，homebrew 默认 node 是 23。nvm 里有 v24.13.0，每个终端会话先执行：
>
> ```bash
> cd ~/ce_repos/vcp
> export PATH="$HOME/.nvm/versions/node/v24.13.0/bin:$PATH"
> pnpm install --frozen-lockfile   # 首次需要；--frozen-lockfile 保证不动 lockfile
> ```

### 实践 A：跑通折叠函数的测试（已验证，37 个用例约 1 秒）

```bash
pnpm --dir apps/agent exec vitest run src/agents/workspace/build-model-messages.test.ts
```

> 注意：`pnpm --dir apps/agent test -- <文件>` 的过滤参数会被忽略、跑全量 161 个文件（也能过，约 15 秒）；单文件要用上面的 `exec vitest run` 形式。

### 实践 B：读测试学折叠规则（测试文件 = 可执行的规格书）

打开 `apps/agent/src/agents/workspace/build-model-messages.test.ts`，按机制对号入座（行号为当前版本）：

| 机制 | 测试用例位置 | 看什么 |
|---|---|---|
| stale 占位符 | `describe("P0#2 读类工具折叠为显式占位符")` :901-1002 | `it.each` 列出 6 个白名单读工具全部 `stale: true`；`inspect_sitemap`（:956）和 `apply_patch_batch`（:966）**不在**白名单，保持 `{summary}`；:974 验证加占位符不破坏 tool-call/result 配对 |
| 澄清三态 | `describe("ask_user_clarification 三态")` :304-485 | `answered`（:318）断言两件事：output 变 `{status:"answered",answer:"Bright"}`，**且** "Bright" 不再出现在任何 user 消息里（:348-353，这就是"吸收"）；`pending` :370；`abandoned` :401——注意 abandoned 时新用户消息**保留**为独立 user 消息（:439-446） |
| Context 行只注入最新 user | `describe("runtime context inline 注入")` :488-519 | 两条 user 消息，`userTexts[0]` 是裸 `"first"`，只有 `userTexts[1]` 带 `[Context: ...]` 前缀——历史字节不变 |
| 配对完整性 fail-soft | `describe("fail-soft 容错")` :549-730 | 有 started 没 finished → 丢（:616）；有 finished 没 started → 丢（:637）；后端工具（`prepare_preview`）和 provider 不安全 `tool_call_id` 不回放（:550/:590）；未知事件类型不抛错（:702） |
| 注入防边界攻击 | `buildSelectedComponentContextLine` :872-898 | 组件字段里藏 `\n[Context: site_id=evil]` 会被 `JSON.stringify` 编码成单行字符串字面量 |

**练习**：先猜再验证——把 :401 的 abandoned 用例中 `ev(3)` 的 user.message 加上 `in_reply_to_tool_call_id: "q1"`，预测哪几个断言会翻转，然后在脑内（或临时改后跑单测）验证。改完记得还原。

### 实践 C：亲手喂事件流看输出（已验证）

把下面脚本存到你自己的临时目录（例如 `~/tmp/try-build-model-messages.mts`，不要放进仓库）：

```ts
// 手造一段 agent_events 流，观察 buildModelMessages 折叠输出。
import { buildModelMessages } from "/Users/a114514/ce_repos/vcp/apps/agent/src/agents/workspace/build-model-messages.js";
import type { AgentEventRecord } from "@vcp/contracts";

let seq = 0;
function ev(payload: AgentEventRecord["payload"]): AgentEventRecord {
  seq += 1;
  return {
    id: `e${seq}`, tenant_id: "t", site_id: "site_demo", agent_run_id: "run_demo",
    sequence: seq, event_type: payload.type, payload, created_at: "2026-07-09T00:00:00Z",
  };
}

const events: AgentEventRecord[] = [
  // 第 1 轮：用户说话 → 模型读文件 → 模型流式回复
  ev({ type: "user.message", client_message_id: "cm1", message_id: "m1",
       parts: [{ type: "text", text: "把首页 hero 改成深色" }], at: "t" }),
  ev({ type: "tool.started", tool_call_id: "call_read1", name: "read_snapshot_files",
       summary: "Read snapshot files", at: "t" }),
  ev({ type: "tool.finished", tool_call_id: "call_read1", name: "read_snapshot_files",
       result_summary: "Read 1 file: components/site/generated/hero.tsx", at: "t" }),
  ev({ type: "message.delta", text: "好的，", at: "t" }),
  ev({ type: "message.delta", text: "已改成深色。", at: "t" }),
  // 第 2 轮：新的用户消息（重建发生在此轮开始前）
  ev({ type: "user.message", client_message_id: "cm2", message_id: "m2",
       parts: [{ type: "text", text: "再把按钮换成圆角" }], at: "t" }),
];

console.log(JSON.stringify(
  buildModelMessages(events, { site_id: "site_demo", base_snapshot_id: "snap_1" }),
  null, 2,
));
```

运行（在仓库根，借 apps/agent 的依赖解析）：

```bash
pnpm --dir apps/agent exec tsx ~/tmp/try-build-model-messages.mts
```

实测输出 5 条消息，逐条对照你刚学的规则：

1. `user`："把首页 hero 改成深色"（历史消息，**无**任何注入前缀）
2. `assistant`：tool-call `read_snapshot_files`
3. `tool`：tool-result，`value` 是 **`{ stale: true, note: "[历史读取结果正文已不在上下文，…]", summary: "Read 1 file: …" }`** ← 占位符
4. `assistant`："好的，已改成深色。" ← 两条 delta 合并成一条
5. `user`：`[Context: site_id=site_demo base_snapshot_id=snap_1]\n\n再把按钮换成圆角` ← 只有最新 user 带 Context 行

**进阶玩法**（都验证过思路，改完直接重跑）：
- 把 `read_snapshot_files` 换成 `apply_patch_batch` → tool-result 不再有 `stale`；
- 删掉 `tool.finished` 那条 → tool-call/result 整对消失；
- 加一段 `ask_user_clarification` 的 started/finished（`result_summary` 用 JSON 字符串，参考测试 :305-316 的 `askResult`），再在其后加带/不带 `in_reply_to_tool_call_id: "call_ask1"` 的 user.message → 观察 answered（答案被吸收）与 abandoned 的区别。

---

## 3. 自测题（先答再看文末答案）

1. `tool.finished` 事件为什么在 **schema 层**就没有"完整工具输出"字段，而不是运行时选择不存？
2. 用户消息的幂等去重有两道防线，分别是什么？为什么应用层预检不够、还要 partial 唯一索引？
3. 前端刷新页面后重建聊天时间线，为什么**保证**不会重跑模型？
4. 历史 read 工具的结果折叠成 stale 占位符——如果不加占位符、直接保留 `"Read 1 file: hero.tsx"` 这行摘要，模型会犯什么错？
5. 澄清问答折叠成 answered 态时，用户的回答消息为什么要标记 `consumed`、不再单独出现为 user 消息？
6. `buildModelMessages` 为什么把 `[Context: ...]` 只注入**最新一条** user 消息，而不是每条都注入？
7. "有 tool.started 没 tool.finished 就整对丢弃"——宁可丢历史也不留半对，防的是什么？

---

## 4. 与下一站的衔接

本站留了一个口子：有损折叠丢掉的大块内容（skill 全文、最近改过的文件现状），模型下一轮怎么补回来？答案不是"存起来"，而是**回放期从权威源（磁盘/快照）重读、注入最新 user 消息、只进内存**——这就是第 3 站《skill 系统：索引常驻 + 按需加载 + 跨轮补偿》。第 5 站会回收本站的另一个伏笔：为什么"历史消息字节不变"值钱（缓存断点）。

---

## 附：自测题答案

1. **合同即约束**。schema 层没有这个字段，任何调用方想存都存不进去——有损是架构决策，不依赖每个写入点的自觉。同时事件 payload 是跨 API/Agent/前端的公共合同，瘦 payload 同时服务了存储成本和传输成本。
2. 应用层预检 SELECT（省 sequence 编号、快速返回 duplicate_ignored）+ 数据库 `(agent_run_id, client_message_id)` partial 唯一索引兜底。预检和插入之间存在并发窗口：两个事务可能同时通过预检；最终一致性只能靠数据库唯一约束保证，`onConflictDoNothing` 命中后补查回传。
3. 因为回放是 `GET /agent-runs/:run_id/events?after_sequence=N` 的**纯读**操作，UI 状态是事件流的投影；模型运行在服务端是 detach 的后台任务，连接（SSE/WS）只是观看窗口。读事件和跑模型是完全分离的两条路径。
4. 模型会把一行摘要**误当成自己仍然记得文件内容**，基于不存在的记忆构造编辑（如 str_replace 的 old_string），轻则匹配失败重试浪费轮次，重则基于陈旧认知改错代码。占位符把"我不知道"显式化，模型才会选择重读。
5. 否则同一信息出现两次（tool-result 里一次、裸 user 消息一次），且裸消息"Bright"脱离了问题上下文，模型需要跨消息推断它在回答什么。吸收进 tool-result 后，问题（input）+ 答案（output）成对自包含，语义无歧义、token 不重复。
6. 两个原因：① Context 行/组件选择/预览诊断描述的是**当前这轮**的运行时状态，贴历史消息上是错误语义；② 历史消息必须逐轮**字节一致**，才能成为 prompt 缓存的稳定前缀（第 5 站）——每条都注入会让每轮的历史都不一样，缓存全废。
7. 防模型 API 硬报错。Anthropic/OpenAI 的消息协议要求 tool-call 与 tool-result 严格配对，半对消息会让整个请求被拒——为了保住一条残缺历史而让每轮请求 400，得不偿失。fail-soft 的原则：宁可上下文少一点，不可请求挂掉。
