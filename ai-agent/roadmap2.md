# AI Agent 开发转型学习路径 v2（快速上手版）

> 制定日期：2026-04-28
> 适用对象：已有较扎实 Python 工程经验、目标**快速**转型 AI Agent 开发
> 学习预算：每天 4 小时，**4 个月内具备求职能力**
> 与 v1 的差异：第 1 周就动手写代码、MCP 提升为硬产出、新增缓存设计专题、新增多 Agent 小项目、新增求职阶段

---

## 0. 心智模型（最先建立，决定后续一切）

**Agent 的本质**：

```
while not done:
    response = llm_call(history + tools)
    tool_calls = parse(response)
    results = execute(tool_calls)
    history.append(results)
```

所有"高级"框架（LangGraph / Claude Agent SDK / AutoGen）本质都在优化这个循环里的 4 件事：
1. **状态管理**（State）
2. **工具调度**（Tool dispatch）
3. **错误恢复**（Resilience / Retry）
4. **可观测性**（Observability）

**作为 Python 工程师的优势**：Agent 系统 90% 是工程问题，10% 是 ML 问题。重点不是训练模型，而是把 LLM 当做"**一个不稳定的、概率性的、会幻觉的远程函数**"来构建可靠系统。

**Mental Anchor（一句话锚点，反复回顾）**：
> Agent = 一个会自我循环调用工具的、不稳定的远程函数。我的工作是让这个不稳定函数构成的系统**可观测、可控、可恢复**。

---

## 快速通道：第 1 周就要跑出能 Demo 的东西（约 28h）

> 与 v1 的最大区别：不再用 1 整周读理论。理论与动手并行，第 1 周末就有能展示的 Agent。

### Day 1–2（8h）：心智模型 + 第一个能跑的 Agent
- 通读 Anthropic《Building Effective Agents》博客（**这一周会反复读 3 遍**）
- 跟着 Anthropic Cookbook 跑通 `tool_use.ipynb`
- **当天就要写出**：~150 行 Python 的最小 Agent（裸 SDK + while 循环 + 1 个 file_read 工具 + 1 个 shell_exec 工具）

### Day 3–4（8h）：理论快速补齐
- 3Blue1Brown Transformer 系列（不深究数学）
- Karpathy "Let's build GPT" + "Let's build the GPT Tokenizer"（**必看，v1 漏了 Karpathy 是错误**）
- 读 ReAct 论文（其他论文延后到阶段 1 再读）

### Day 5–7（12h）：第 1 周硬产出
- 把 Day 1–2 的最小 Agent 升级为 **CLI 版 "Claude Code Lite v0.1"**
    - 多轮对话、文件读写、shell 执行
    - 加上 prompt caching（先用最简单的两段式：system / messages）
    - 加上 cost / token 日志
- 推到 GitHub，写 README

**第 1 周末交付物**：一个能在终端用、能自我演示、能贴到简历上的玩具 Agent。

---

## 阶段 1：API 与 SDK 精通（第 2-4 周，~84h）

**目的**：直接控制底层，框架黑盒就不再是黑盒。

### 1.1 Anthropic Claude API 全特性
- tool use（深入理解 schema 设计）
- streaming
- **prompt caching**（重点！决定生产成本是否可控，用得好可降本 90%）
- extended thinking
- batch、files、citations
- computer use（先了解，不深入）

### 1.2 Prompt Caching 专题（**v2 新增半天专题**）
> Prompt Caching 不是"省钱技巧"，而是 **Agent 架构设计**。它决定 system prompt / tools / history 怎么排序、缓存断点放哪。**写第一行 Agent 代码前就要想清楚**。

- 阅读 Anthropic 缓存断点最佳实践
- 自己设计一个"缓存友好的 prompt 结构模板"，放到 `~/knowledges/llm/prompt-caching.md`
    - 哪些是 stable header（系统级，缓存）
    - 哪些是 semi-stable（每天变一次，独立断点）
    - 哪些是动态部分（不缓存）
- 在 v0.1 Claude Code Lite 上验证缓存命中率，目标 ≥ 70%

### 1.3 OpenAI API 对照学习（1 天）
- function calling、structured outputs，看差异即可

### 1.4 MCP (Model Context Protocol) — **v2 提升为硬产出**
> v1 把 MCP 列为"跑通示例 + 写一个 server"，v2 把它升级为阶段 1 的**主交付物**之一。理由：MCP 让你写的工具能被 Claude Code / Cursor / 任意 MCP 客户端复用，是 2026 年复利最高的技能之一。

- 跑通 MCP 官方示例
- 写一个**真正对自己有用**的 MCP server，不是 toy 例子。建议二选一：
    - 包装本地 SQLite/数据库：暴露查询、schema 探查工具
    - 包装 `~/knowledges/` 知识库：暴露按主题搜索、读取笔记的工具
- 配到自己的 Claude Code 里日常使用，**用一周时间打磨**直到顺手

### 阶段 1 产出（3 个项目）
1. **CLI 版 "Claude Code Lite" v1.0**：在 v0.1 基础上加 prompt caching、streaming、错误恢复
2. **缓存友好的 prompt 设计文档**（笔记，不是代码）
3. **一个日常自用的 MCP server**

> **为什么先学裸 API 再学框架？**
> LangChain/LangGraph 是抽象层，但生产环境出问题（比如 token 飙升、工具调用循环、流式中断）调试要钻到底层 API 调用。直接学框架的人，遇到诡异 bug 就抓瞎。

---

## 阶段 2：LangGraph + 主流框架（第 5-9 周，~140h）

**目的**：聚焦 LangGraph 单点突破，**别陷入框架战争**。

### LangGraph 系统学习（占 60%）
- StateGraph 核心：节点、边、状态、条件路由
- Human-in-the-loop / Interrupts
- **Persistence（checkpointer）** — 决定 Agent 能否"暂停-恢复"
- Subgraphs、Multi-agent 编排（Supervisor / Swarm 模式）
- Streaming（events / values / updates 三种模式的差异）
- **必做**：把官方 cookbook 里 10+ 个 example 全部跑通并改造

### LangChain 选学（占 15%）
- 只学 Runnable / LCEL / Output Parsers，其他模块快速浏览

### Claude Agent SDK（占 10%）
- Anthropic 官方 Agent 框架，了解其哲学（最小抽象）

### 对比认知（占 5%）
- 扫一眼 AutoGen、CrewAI、PydanticAI，理解差异即可，不深入

### 多 Agent 协作小项目（占 10%，**v2 新增**）
> v1 把多 Agent 放到阶段 5 作为论文阅读，太晚。手感比读论文重要。

- 用 LangGraph 实现一个 **3-Agent 写作系统**：作者 / 评审 / 编辑
- 关键学习点：状态共享、Supervisor 路由、循环停机条件
- 周末两天搞定即可，不必精雕

### 阶段 2 主产出
**Deep Research Agent**：用 LangGraph 实现多步搜索 → 子查询规划 → 综合 → 引用。
- 这是面试和作品集的**硬通货**
- 必须做：subgraph 拆分、checkpointer 持久化、streaming 输出
- 必须有：可重放的 trace、能回答"为什么生成这个结论"

---

## 阶段 3：RAG 与检索（第 10-12 周，~84h）

**目的**：80% 的企业 Agent 落地场景都涉及 RAG。

- **Embedding 原理 + 主流模型**：OpenAI、Voyage、BGE、Cohere
- **向量数据库**：Qdrant 或 Chroma 选一个深入，了解 Pinecone / Weaviate 差异
- **进阶检索**：
    - Hybrid Search（BM25 + 向量）
    - Reranker（Cohere / Jina / BGE-reranker）
    - HyDE、Query Expansion
    - Parent-Child / Sentence-Window 切块策略
- **Agentic RAG**：让 Agent 自己决定检索什么、何时检索、如何重写查询
- **LlamaIndex 速通**（仅作工具库使用，2-3 天）

**产出**：基于自己 `~/knowledges/` 笔记的 Agentic RAG，能正确处理多跳问题。
**加分项**：把它和阶段 1 的 MCP server 合并，让你的 Claude Code 能直接搜自己的知识库。

---

## 阶段 4：工程化与可观测性（第 13-14 周，~56h）

**目的**：从"能跑"到"能上线"。这是 Python 工程师转型的**护城河**——AI 出身的人 90% 不会做这个。

| 主题 | 关键工具 |
|------|---------|
| Tracing & Debugging | **LangSmith**（必学）、Langfuse（开源备选） |
| Evaluation | LangSmith Eval、Ragas（RAG 专用）、自定义 LLM-as-Judge |
| 部署 | FastAPI + LangServe / 自定义 streaming endpoint、SSE |
| 缓存与成本 | Prompt caching、语义缓存（GPTCache） |
| 安全 | Prompt injection 防御、PII 过滤、tool use 沙箱化 |

**产出**：把阶段 2 的 Deep Research Agent 部署成 web 服务，加上完整 trace + eval 数据集 + cost dashboard。

---

## 阶段 5：求职准备（第 15-16 周，~56h，**v2 新增**）

> v1 没有这一阶段。对"快速转型"诉求来说，这是最关键的一步。

### 5.1 项目精修（5 天）
从已有产出中选 **2 个最强项目**（推荐：MCP server + Deep Research Agent），做：
- 完整 README（中英文版本各一份）
- 1 篇技术博客深度拆解架构决策
- 1 段 2-3 分钟 demo 视频
- 公开仓库整理、commit 历史清理

### 5.2 简历改写（2 天）
- 突出复合背景：**X 年 Python 工程经验 + Agent 系统设计能力**
- 关键词：MCP / LangGraph / RAG / Prompt Caching / Eval / Tracing
- 量化指标：缓存命中率、Agent 任务成功率、成本下降幅度

### 5.3 面试准备（7 天）
- **设计题**："设计一个客服 Agent" / "设计一个能写代码的 Agent"
- **对比题**：ReAct vs Plan-and-Execute / RAG vs Fine-tune / 各框架取舍
- **源码题**：手写简化版 ReAct loop / 简化版 LangGraph StateGraph
- **场景题**：Agent 陷入循环怎么办？token 爆炸怎么办？工具调用幻觉怎么办？

### 5.4 投递（持续）
- 重点关注：AI 应用层公司（不是大模型公司）、有真实 Agent 业务的中型团队
- 不要海投，每份简历针对岗位定制 cover letter

---

## 阶段 6：前沿与差异化（第 17 周+，持续）

- **Multi-Agent 范式**：阅读 AutoGen、ChatDev、MetaGPT 论文与源码
- **Memory 系统**：Mem0、Letta（前 MemGPT）、自己设计长期记忆
- **Computer Use / Browser Agent**：Claude Computer Use、Browser-use
- **Code Agent 深度**：Claude Code、Cursor、aider 的实现思路；SWE-bench
- **持续追踪**：
    - Anthropic Engineering Blog
    - LangChain blog
    - X 关注：Harrison Chase、Logan Kilpatrick、Simon Willison

---

## 每天 4 小时分配

| 时段 | 内容 | 时长 |
|------|------|------|
| 第 1 段 | 概念学习/读论文/读源码 | 1h |
| 第 2-3 段 | **动手编码**（核心，AI 工程极度依赖手感） | 2h |
| 第 4 段 | 复盘 + 写笔记到 `~/knowledges/` + 刷推/读 blog | 1h |

**关键纪律**：
1. **代码量优先于课程数**。看 10 节课不如自己写 100 行调通。
2. **每周末做 mini-project**，不要只跟教程。
3. **写学习日志**到 `~/knowledges/`。
4. **第 1 周就要有能 demo 的产出**——这是 v2 的核心理念。

---

## 3 个非主流建议

1. **不要先学"Agent 理论"再动手**。先用 Claude API 写个能跑的玩具，再倒回去看理论，留存率高 5 倍。
2. **盯紧 Anthropic 官方资源**。Anthropic 的工程哲学（"Build minimal abstractions"）是当前最干净的 Agent 心智模型，且 Claude Agent SDK / MCP 都来自这里。
3. **别陷入框架战争**。LangGraph 学透就够，其他框架知道存在与差异即可 — 真正稀缺的是**系统设计能力**，不是框架熟练度。

---

## 资源清单（速查）

### 官方文档
- Anthropic API: https://docs.anthropic.com
- Anthropic "Building Effective Agents": https://www.anthropic.com/research/building-effective-agents
- Anthropic Cookbook: https://github.com/anthropics/anthropic-cookbook
- LangGraph: https://langchain-ai.github.io/langgraph/
- MCP: https://modelcontextprotocol.io

### 必读论文
- ReAct (2022)
- Reflexion (2023)
- Toolformer (2023)
- Tree of Thoughts (2023)

### 视频/课程
- 3Blue1Brown — Neural Networks 系列
- Karpathy — "Let's build GPT" / "Let's build the GPT Tokenizer"
- Anthropic Prompt Engineering 课程（免费）

### 持续关注
- Anthropic Engineering Blog
- LangChain Blog
- Simon Willison 的 weblog
- Harrison Chase / Logan Kilpatrick / Simon Willison 的 X

---

## 进度跟踪

> 在这里勾选完成情况，便于跨 session 续接

- [ ] 快速通道：第 1 周硬产出（Claude Code Lite v0.1）
- [ ] 阶段 1：API 与 SDK 精通（含 MCP server 主交付）
- [ ] 阶段 2：LangGraph + Deep Research Agent + 多 Agent 小项目
- [ ] 阶段 3：RAG 与 Agentic RAG
- [ ] 阶段 4：工程化与可观测性
- [ ] 阶段 5：求职准备（项目精修 / 简历 / 面试）
- [ ] 阶段 6：前沿与差异化（持续）

---

## 求职时间线（基于"快速转型"诉求）

| 时间节点 | 状态 |
|---------|------|
| 第 1 周末 | 有第一个能 demo 的玩具 Agent |
| 第 4 周末 | 有 MCP server 在自己 Claude Code 里日用 |
| 第 9 周末 | 有 Deep Research Agent 作为简历主项目 |
| 第 14 周末 | 有完整工程化案例（trace + eval + 部署） |
| 第 16 周末 | **可以开始投简历** |
| 第 17 周+ | 持续学习 + 持续面试 |
