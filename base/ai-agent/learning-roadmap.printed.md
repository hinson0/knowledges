# AI Agent 开发转型学习路径（Python 工程师视角）

> 制定日期：2026-04-28
> 适用对象：已有较扎实 Python 工程经验、目标转型 AI Agent 开发
> 学习预算：每天 4 小时，预计 4 个月（~480h）走完阶段 0-4

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

**作为 Python 工程师的优势**：Agent 系统 90% 是工程问题，10% 是 ML 问题。重点不是训练模型，而是把 LLM 当做"一个不稳定的、概率性的、会幻觉的远程函数"来构建可靠系统。

---

## 阶段 0：心智模型校准（第 1 周，~28h）

| 内容 | 推荐方式 | 时间 |
|------|---------|------|
| Transformer 原理（不深入数学，理解 token / context / attention） | 3Blue1Brown 视频 + Karpathy "Let's build GPT" | 6h |
| Prompt Engineering 工程化 | Anthropic 官方 Prompt Engineering 课程（免费） | 6h |
| 读 ReAct、Reflexion、Toolformer 三篇核心论文 | arxiv 原文 + 任意中文解读 | 8h |
| 通读 Anthropic 的 "Building Effective Agents" 博客 | 反复读 3 遍，是路线图 | 4h |
| 手写最小 Agent（裸 Claude API + while 循环 + 1 个工具） | 不用框架，~200 行 Python | 4h |

**产出**：能用一句话说清"Agent / Workflow / Chain 的区别"。

---

## 阶段 1：API 与 SDK 精通（第 2-4 周，~84h）

**目的**：直接控制底层，框架黑盒就不再是黑盒。

### Anthropic Claude API 全特性
- tool use
- streaming
- **prompt caching**（重点！决定生产成本是否可控，用得好可降本 90%）
- extended thinking
- batch
- files
- citations
- computer use

### OpenAI API 对照学习（1 天）
- function calling、Assistants API、structured outputs，看差异即可

### MCP (Model Context Protocol)
- Anthropic 推的 Agent-Tool 标准协议，未来 1-2 年会是基建
- 跑通官方示例
- 写一个自己的 MCP server（如包装本地 SQLite/数据库）

### 本阶段产出（2 个项目）
1. **CLI 版 "Claude Code Lite"**：能读写文件、执行 shell、多轮对话、带 prompt caching
2. **一个 MCP server**（如 SQLite 查询服务器）

> **为什么先学裸 API 再学框架？**
> LangChain/LangGraph 是抽象层，但生产环境出问题（比如 token 飙升、工具调用循环、流式中断）调试要钻到底层 API 调用。直接学框架的人，遇到诡异 bug 就抓瞎。

---

## 阶段 2：LangGraph + 主流框架（第 5-9 周，~140h）

**目的**：工作目录就叫 `LangGraph`，重点突破。

### LangGraph 系统学习（占 60%）
- StateGraph 核心：节点、边、状态、条件路由
- Human-in-the-loop / Interrupts
- **Persistence（checkpointer）** — 决定 Agent 能否"暂停-恢复"
- Subgraphs、Multi-agent 编排（Supervisor / Swarm 模式）
- Streaming（events / values / updates 三种模式的差异）
- **必做**：把官方 cookbook 里 10+ 个 example 全部跑通并改造

### LangChain 选学（占 20%）
- 只学 Runnable / LCEL / Output Parsers，其他模块快速浏览

### Claude Agent SDK（占 10%）
- Anthropic 官方 Agent 框架，了解其哲学（最小抽象）

### 对比认知（占 10%）
- 扫一眼 AutoGen、CrewAI、PydanticAI，理解差异即可，不深入

### 本阶段产出（1 个稍大项目）
**Deep Research Agent**：用 LangGraph 实现多步搜索 → 子查询规划 → 综合 → 引用。这是面试和作品集的硬通货。

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

**产出**：基于自己技术笔记/某领域文档的 RAG 系统，能正确处理多跳问题。

---

## 阶段 4：工程化与可观测性（第 13-14 周，~56h）

**目的**：从"能跑"到"能上线"。

| 主题 | 关键工具 |
|------|---------|
| Tracing & Debugging | **LangSmith**（必学）、Langfuse（开源备选） |
| Evaluation | LangSmith Eval、Ragas（RAG 专用）、自定义 LLM-as-Judge |
| 部署 | FastAPI + LangServe / 自定义 streaming endpoint、SSE |
| 缓存与成本 | Prompt caching、语义缓存（GPTCache） |
| 安全 | Prompt injection 防御、PII 过滤、tool use 沙箱化 |

**产出**：把阶段 2 的 Deep Research Agent 部署成 web 服务，加上完整 trace + eval 数据集。

---

## 阶段 5：前沿与差异化（第 15-16 周+，持续）

- **Multi-Agent 范式**：阅读 AutoGen、ChatDev、MetaGPT 论文与源码
- **Memory 系统**：Mem0、Letta（前 MemGPT）、自己设计长期记忆
- **Computer Use / Browser Agent**：Claude Computer Use、Browser-use
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

- [ ] 阶段 0：心智模型校准
- [ ] 阶段 1：API 与 SDK 精通
- [ ] 阶段 2：LangGraph + 主流框架
- [ ] 阶段 3：RAG 与检索
- [ ] 阶段 4：工程化与可观测性
- [ ] 阶段 5：前沿与差异化
