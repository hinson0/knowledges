# Agentic Workflow Design — 让 AI 自主工作的架构范式

## 1. 定义与分水岭

**Agentic Workflow** = 让 LLM 作为"能自主规划、调用工具、观察结果、迭代推进"的 agent,来完成端到端的复杂任务。

它不是一个模型、不是一个框架,而是一种**系统架构范式**。核心分水岭在"谁在 loop 里":

| 维度 | 传统 LLM 应用 | Agentic 应用 |
|------|---------------|-------------|
| Loop 主体 | 人类在 loop 里,AI 一问一答 | AI 在 loop 里,人类给目标后退出 |
| 决策粒度 | 每一步都由人决定 | AI 自主决定下一步做什么 |
| 能力边界 | 仅生成文本 | 规划 → 调工具 → 观察 → 反思 → 再行动 |
| 状态 | 无状态 / 对话上下文 | 有短期 + 长期记忆 |
| 确定性 | 高(每步可控) | 低(AI 自由裁量) |
| 适合任务 | 回答问题、单次转换 | 调研、重构、CI 编排、多轮交互 |

一个判断法则:**如果任务能写死流程图就不是 agentic,必须让 AI 临场判断才是**。

## 2. 七大核心模式

### 2.1 ReAct(Reasoning + Acting)

最基础的 agent 循环:思考 → 行动 → 观察,三步一转,直到任务完成。

```
while not done:
    thought = llm.reason(context)        # "我需要先找到 login 函数"
    action  = llm.pick_tool(thought)     # Grep("login")
    result  = execute(action)            # tool 返回文件列表
    context.append(thought, action, result)
```

cc 的每次对话其实就是一个 ReAct 主循环。

### 2.2 Plan-and-Execute

先让 AI 列出完整计划(多步),再逐步执行,执行中可以回看 plan 是否需要调整。

```python
plan = llm.plan(goal)                    # ["1. 查 diff", "2. 分组", "3. 逐组 commit"]
for step in plan:
    result = llm.execute(step)
    if result.needs_replan:
        plan = llm.replan(plan, result)
```

对应 cc 的:**plan mode**、`TaskCreate/TaskUpdate`、`/smart:push` 的三阶段流水线。

### 2.3 Tool Use / Function Calling

给 AI 装"手" — 定义一批 schema 化工具(`name + params + description`),AI 用结构化方式调用。

```json
{
  "name": "grep",
  "params": { "pattern": "login", "path": "src/" },
  "description": "Search file contents"
}
```

cc 的 `Bash/Read/Edit/Grep/Glob` 就是最基础的 tool set。MCP 协议则是把 tool 集合"外挂化"。

### 2.4 Multi-Agent Collaboration

多个专门化 agent 分工协作。典型角色分配:

- **Planner** — 拆解目标
- **Worker** — 执行单步
- **Reviewer** — 审核产出
- **Router** — 决定把任务派给谁

```
planner -> [worker_a, worker_b, worker_c] -> reviewer -> done?
                                                      ↓ no
                                                   planner (replan)
```

cc 的 `Agent` 工具 + `subagent_type` 就是做这件事。`pr-review-toolkit` 的五个专家 agent(code / comment / type / silent-failure / test)并行审代码是一个教科书案例。

### 2.5 Reflection / Self-Critique

AI 自己审查自己的输出,发现问题就重做。关键在于"审查者"和"生产者"用不同的 prompt 甚至不同的模型实例。

```python
draft    = llm.generate(task)
critique = llm.critique(task, draft)     # 刻意换个角色 prompt
if critique.has_issues:
    draft = llm.revise(draft, critique)
```

cc 的 `/simplify`、`code-reviewer` agent 都是 reflection 模式的应用 — 甚至 `/security-review` 自己的 prompt 里就显式写了"每个发现再起一个子任务做 false-positive 过滤"。

### 2.6 Memory(短期 + 长期)

| 类型 | 实现 | 容量 | 生存期 |
|------|------|------|--------|
| 短期 | 对话 context | 模型上下文窗口(如 1M token) | 本次会话 |
| 中期 | 跨 session 的 summary / checkpoint | 中 | 数天 |
| 长期 | 向量库 / 文件落盘(MEMORY.md) | 大 | 永久 |
| 工作记忆 | 当前 TodoList、Plan | 小 | 当前任务 |

cc 的自动 memory 系统(`~/.claude/.../memory/MEMORY.md`)就是长期记忆 — 关键是它用**自然语言+文件**存,不是向量库,可读可审。

### 2.7 Human-in-the-Loop(HITL)

在"危险/不可逆/高不确定"的节点停下来等人类确认。关键是**不要在每步都问**(那就退化成 chatbot 了),只在:

- 破坏性操作(`rm -rf`、`git push --force`)
- 跨越信任边界(push 到 main、修改共享资源)
- 高歧义的设计决策(选 A 还是 B 架构)

```python
if action.is_risky():
    answer = ask_user(options=[...])
    if answer == "cancel": abort()
```

cc 的 `AskUserQuestion` 工具、本项目 CLAUDE.md 里的"main 分支操作必须询问"就是这一模式。

## 3. 与 Context Engineering 的关系

Context Engineering 和 Agentic Workflow 是**因果对偶**:

```
context-engineering             (给 AI 装什么"脑子")
         ↓  准备好知识、规则、记忆、工具描述
agentic-workflow-design         (AI 用这些脑子怎么"干活")
         ↑  执行中产生新状态,反哺 context
```

- **Context Engineering 解决"输入"**:系统 prompt、CLAUDE.md、记忆、检索文档、工具 schema
- **Agentic Workflow 解决"控制流"**:ReAct 循环、多 agent 编排、反思、HITL

没有好的 context,再精密的 workflow 也会跑偏(agent "幻觉"做错事);反之,再完美的 context,如果 workflow 是一次性问答,也浪费了 AI 的自主能力。

**判断法则**:当你发现 agent 常跑偏,先问是 context 没给够,还是 workflow 没约束好。两个方向的药不一样。

## 4. cc 里的对应实现

Claude Code 本身就是一个**活的 agentic workflow 样本**:

| 模式 | cc 里的对应机制 |
|------|----------------|
| ReAct | 每次对话的基础循环 |
| Plan-and-Execute | Plan mode、`TaskCreate/TaskUpdate`、`/smart:push` 多阶段 |
| Tool Use | `Bash/Read/Edit/Grep/Glob/WebFetch`(内置)+ MCP(外挂) |
| Multi-Agent | `Agent` 工具 + `subagent_type`(如 `pr-review-toolkit` 五专家并行) |
| Reflection | `/simplify`、`code-reviewer`、`/security-review` 的 FP 过滤子任务 |
| Memory(短期) | 当前对话 context(1M window) |
| Memory(长期) | `~/.claude/.../memory/MEMORY.md` 自然语言落盘 |
| Memory(工作记忆) | Todo 任务列表 |
| HITL | `AskUserQuestion`、危险操作确认、Plan mode 退出时的 `ExitPlanMode` |
| Event-driven | hooks(SessionStart / PreToolUse / PostToolUse / Stop) |
| Skill 复用 | `Skill` 工具 + `~/.claude/skills/` 可重用能力模块 |

特别值得注意的是 **hooks** — 这是传统 agentic 框架(LangGraph、AutoGen)少见的机制:把"事件驱动"引入 agent 运行时,让外部脚本在 agent 的任何事件点插入逻辑(审计、拦截、注入)。

## 5. 项目落地:什么时候该上 agentic,什么时候别上

### 该上 agentic 的信号

- 任务**无法写死流程图**,中间需要 AI 临场判断下一步
- 需要**多轮迭代**才能收敛(如重构、调研、debug)
- 涉及**多种工具的组合**调用(查代码 + 写代码 + 跑测试 + 提交)
- 同一类任务**反复出现且每次细节不同**(如每周的 PR review)
- 产出需要**自审机制**(code review、security review)

### 别上 agentic 的信号

- 任务能**一个 prompt 一次搞定**(写个文案、翻译、分类)
- **延迟敏感**(用户同步等待 < 1s)— agentic 往往多轮 LLM 调用累加
- **成本敏感**(每次调用便宜一点就差很多)— multi-agent + reflection 成本是单次调用的 5~10 倍
- 任务**可完全用传统代码实现**(正则、SQL、规则引擎)
- 输出必须**100% 确定性**(财务、医疗、法律合规)— agent 的"自由裁量"会变成风险

### coco 项目的实际锚点

项目里已经在用的 agentic 设计,可以直接当案例:

| coco 里的场景 | 用到的模式 |
|--------------|-----------|
| `pr-review-toolkit` 五 agent 并行审代码 | Multi-Agent + Reflection |
| `/smart:push` 的 commit → version → push 流水线 | Plan-and-Execute |
| `AskUserQuestion` 在 main 分支拦截 | Human-in-the-Loop |
| `CLAUDE.md` + 自动 memory | Long-term Memory |
| `just mv` + `.printed.md` 归档约定 | 不是 agentic(纯脚本,确定性) |
| 记账规则引擎 `parse()` | 不是 agentic(NLP 规则,不需要自主) |
| 后端 ASR/OCR 调用 | 不是 agentic(单次工具调用) |

注意**最后三行**:不是所有 AI 相关的东西都该 agentic 化。记账 `parse()` 如果做成 agent,每次调用成本 ×10,结果反而不稳定 — 传统规则引擎才是对的选择。

## 关键记忆点

1. **Agentic ≠ 更智能,而是更自主** — 自主意味着更强也意味着更不可控
2. **先 context 后 workflow** — context 不够,workflow 设计再精巧也白搭
3. **HITL 是必备而非可选** — 不可逆操作必须有人类闸门
4. **Reflection 几乎总能提升质量** — 代价是 2~3 倍成本,看场景值不值
5. **Multi-agent 不是越多越好** — 超过 5 个 agent 协调成本会压垮收益
6. **Memory 用文件存优于向量库** — 可读、可审、可手动编辑

## 延伸阅读锚点

- 同目录 `context-engineering.printed.md` — 对偶主题,一起看
- 同目录 `what-is-ai-native.printed.md` — 更上位的概念定位
- 同目录 `ai-code-review-standards.printed.md` — 对 agentic 输出的质量要求
- `cc/pr-review-toolkit.printed.md` — multi-agent 的具体工程案例
