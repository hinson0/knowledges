# AI 应用核心概念

★ Insight ─────────────────────────────────────
- AI 应用技术栈的本质：LLM 是个无状态的"文字接龙函数"——它不会记忆、不会查资料、不会调用代码。其他所有概念（Prompt / RAG / Tool / Agent）都是在它外面加补丁，让它能干实际工作
- 所以这些概念不是平级的——它们是层层叠加的关系。理解这个层次比记定义重要 100 倍
─────────────────────────────────────────────────

## 一、AI 应用技术栈全景图

按"从底层到上层"分 6 层：

```
┌─────────────────────────────────────────────────┐
│  6. 评估 / 可观测层                              │
│     RAGAS · Langfuse · LangSmith · OpenTelemetry │
├─────────────────────────────────────────────────┤
│  5. 编排层（Agent / Workflow）                   │
│     LangGraph · AutoGen · AgentScope · CrewAI    │
├─────────────────────────────────────────────────┤
│  4. 增强能力层                                   │
│     Tool Calling │ RAG │ Memory │ Code Sandbox   │
├─────────────────────────────────────────────────┤
│  3. 检索 / 数据层                                │
│     向量库(Chroma/Qdrant/Milvus) · Embedding ·   │
│     Reranker · BM25 · 数据库 · API               │
├─────────────────────────────────────────────────┤
│  2. Prompt 层                                    │
│     Prompt Engineering · Context Engineering ·   │
│     模板引擎(Jinja2) · 输出解析                  │
├─────────────────────────────────────────────────┤
│  1. 模型层                                       │
│     OpenAI · Anthropic · DeepSeek · 通义/豆包 ·  │
│     本地部署(vLLM/Ollama)                        │
└─────────────────────────────────────────────────┘
```

JD 里那段话翻译过来就是：让你做 5 + 4 层的活，要求你懂 1-3 层，做出来能用 6 层指标证明。

---

## 二、5 个核心概念逐个讲清

### 1. LLM（Large Language Model）

**一句话：一个吃文本、吐文本的无状态概率函数。**

它**不能**干什么（理解这点最重要）：

- ❌ 记不住之前说过的话（每次调用都是全新的）
- ❌ 不能上网、不能查数据库
- ❌ 不能执行代码、不能调 API
- ❌ 不知道训练截止日期之后的事
- ❌ 没有"思考"——只是预测下一个 token

最小代码：

```python
from openai import OpenAI
client = OpenAI(api_key="...", base_url="https://api.deepseek.com")

resp = client.chat.completions.create(
    model="deepseek-chat",
    messages=[{"role": "user", "content": "1+1=?"}]
)
print(resp.choices[0].message.content)  # "2"
```

就这 5 行——这是 AI 应用的唯一原子操作。后面所有概念都是围着这 5 行打补丁。

★ Insight ─────────────────────────────────────
- 你以前写 Python 调 LLM 的那些代码，本质就是在第 1 层。接下来 8 周你要爬到第 5 层
- "它没有记忆"是后面所有设计的根源——为什么需要 messages 数组？因为每次都得把历史塞回去；为什么需要 Memory 系统？因为 messages 会爆 token
- 模型选型口诀：复杂推理用 R1、走量用 V3、要 Function Calling 用 V3（R1 不支持 tool calling）
─────────────────────────────────────────────────

---

### 2. Prompt Engineering（提示词工程）

**一句话：用文字精确控制 LLM 输出格式和质量的交互设计。**

**解决什么问题**：LLM 不听话——你说"返回 JSON"，它给你包一层 ` ```json ` 代码块；你说"简短回答"，它给你写 500 字。

**核心技巧（实战常用 5 个）：**

| 技巧             | 例子                                    | 用途                 |
| ---------------- | --------------------------------------- | -------------------- |
| Role 设定        | "你是一个资深 Python 代码评审员"        | 让输出风格一致       |
| Few-shot         | 给 2-3 个输入输出示例                   | 比解释 10 句规则有效 |
| Chain-of-Thought | "先思考再回答，分步骤推理"              | 复杂问题准确率↑      |
| 结构化输出       | "严格按以下 JSON 返回: {...}"           | 让代码能解析         |
| 拒绝示例         | "如果遇到 X 情况，回复 'CANNOT_HANDLE'" | 避免瞎编             |

**Prompt Engineering vs Context Engineering**（JD 出现的术语）：

- **Prompt Engineering**：写好"那一段指令"——静态的
- **Context Engineering**：动态决定"每次塞什么进 context"——比如保留哪几轮历史、塞哪几条 RAG 结果、什么时候压缩

★ Insight ─────────────────────────────────────
- 2026 年的趋势：单纯的 Prompt Engineering 在贬值（模型越强越不挑 prompt），Context Engineering 在升值——因为 token 成本和延迟才是生产瓶颈
- JD 写"设计 Prompt Pipeline 与 Context Engineering"——你简历上要能讲：我怎么决定哪些 context 进 / 哪些被压缩 / 哪些直接丢弃
- Coding Agent 场景的典型 Context 决策：用户问题(必留) + 最近 N 轮工具调用(滑窗) + RAG top-5 代码片段(动态) + 错误信息(临时塞)
─────────────────────────────────────────────────

---

### 3. Tool Calling / Function Calling（工具调用）

**一句话：让 LLM 告诉你它想调用什么函数，然后你的代码去执行——LLM 自己不调。**

这是最容易误解的概念——很多人以为是 LLM 真的执行了函数。实际流程：

```
你   → 给 LLM 发：[消息 + 工具列表的 JSON Schema]
LLM  → 返回："我要调用 read_file('main.py')"  (这是文本/JSON)
你   → 解析，执行 read_file('main.py')，拿到结果
你   → 把结果作为新消息发给 LLM
LLM  → 基于结果继续输出
```

最小代码：

```python
tools = [{
    "type": "function",
    "function": {
        "name": "read_file",
        "description": "读取本地文件内容",
        "parameters": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"]
        }
    }
}]

resp = client.chat.completions.create(
    model="deepseek-chat",
    messages=[{"role": "user", "content": "看看 main.py 写了啥"}],
    tools=tools
)

tool_call = resp.choices[0].message.tool_calls[0]
# tool_call.function.name = "read_file"
# tool_call.function.arguments = '{"path": "main.py"}'

# 你的代码真正执行
result = open("main.py").read()

# 把结果回传给 LLM
messages.append({"role": "tool", "content": result, "tool_call_id": tool_call.id})
```

**为什么这是 Agent 的基石**：

- 没有 Tool Calling → LLM 只能聊天
- 有了 Tool Calling → LLM 能"操作世界"（改文件、发邮件、查数据库、调 API）

★ Insight ─────────────────────────────────────
- Function Calling 本质上是让 LLM 输出受 Schema 约束的 JSON——所以现代模型连"非 function calling 场景"也用它做结构化输出
- 模型可能"瞎调工具"或"该调不调"——这就是为什么需要 system prompt 强约束 + 错误处理 + 重试。这块的工程经验是面试拷打重点
- DeepSeek 的 tool_calls 偶尔会返回多个 tool 在一条消息里——你的 dispatcher 必须支持并发执行（asyncio.gather）
─────────────────────────────────────────────────

---

### 4. RAG（Retrieval-Augmented Generation 检索增强生成）

**一句话：回答前先从知识库捞相关资料，把资料塞进 prompt 一起发给 LLM。**

**解决什么问题**：LLM 不知道你公司的代码、不知道最新文档、不知道私有数据。微调成本高、慢、还要重训——RAG 是最便宜的"让 LLM 懂你领域"的方法。

**完整流程（生产级 RAG，不是 demo）：**

```
[离线阶段：建索引]
原始文档 → 切分(Chunking) → Embedding 向量化 → 存入向量库
                          ↓
                       同时建 BM25 倒排索引

[在线阶段：查询]
用户问题
  ├─→ Embedding 查询 → 向量库召回 top-20
  ├─→ BM25 召回 top-20
  └─→ (可选) 改写查询(HyDE)
        ↓
   合并去重 → Reranker 精排 → top-5
        ↓
   把 top-5 拼进 prompt → 发给 LLM → 答案
```

**5 个关键决策点（每个都是面试题）：**

| 决策             | 选项                                | 我推荐                           |
| ---------------- | ----------------------------------- | -------------------------------- |
| 怎么切分         | 固定长度 / 语义切分 / 结构化切分    | 代码场景：按函数/类切            |
| 用什么 Embedding | OpenAI / bge-m3 / bge-large-zh      | 中文代码：bge-m3                 |
| 用什么向量库     | Chroma / Qdrant / Milvus / pgvector | 学习用 Chroma，简历写 Qdrant     |
| 用不用混合检索   | 纯向量 / BM25+向量                  | 必须混合——纯向量是 demo          |
| 用不用 Reranker  | 用 / 不用                           | 必须用——这是 demo 到生产的分水岭 |

★ Insight ─────────────────────────────────────
- "RAG 召回率低"是面试常考——根本原因 80% 是切分策略错了，不是 embedding 差。"How RAG works"的图人人会画，但"我怎么调好它"才值钱
- 评估指标三件套：Context Precision（召回的相关吗）、Context Recall（相关的都召回了吗）、Faithfulness（答案忠于上下文吗）——RAGAS 库一键跑
- Coding Agent 里的 RAG 不一样：除了语义检索，符号检索（find_definition）和文本检索（grep）反而更准——这是 Cursor/Aider 的核心 know-how
─────────────────────────────────────────────────

---

### 5. Agent（智能体）

**一句话：Agent = LLM + 工具 + 循环 + 状态——能自主完成多步任务的程序。**

**和"调一次 LLM"的本质区别：**

|              | 普通 LLM 调用 | Agent                  |
| ------------ | ------------- | ---------------------- |
| 调用次数     | 1 次          | N 次循环               |
| 谁决定下一步 | 你的代码写死  | LLM 自己决定           |
| 工具         | 通常没有      | 必须有                 |
| 状态         | 无            | 有（历史、记忆、计划） |

**最小 Agent 伪代码（这就是你 Week 1 要写的）：**

```python
def agent_loop(user_query, tools, max_iter=10):
    messages = [{"role": "user", "content": user_query}]
    for i in range(max_iter):
        resp = llm(messages, tools=tools)

        if resp.tool_calls:
            for call in resp.tool_calls:
                result = execute_tool(call.name, call.args)
                messages.append({"role": "tool", "content": result})
        else:
            return resp.content  # 完成
    return "达到最大轮次"
```

**Agent 的几种常见架构（JD 里"多 Agent 协作"指这个）：**

| 架构             | 说明                        | 用途         |
| ---------------- | --------------------------- | ------------ |
| ReAct            | Reasoning + Acting 循环     | 通用单 Agent |
| Plan-and-Execute | 先规划再执行                | 复杂任务     |
| Reflection       | 自我评估 + 修正             | 提升质量     |
| Multi-Agent      | 多个 Agent 协作（角色分工） | 复杂业务     |
| Swarm / Handoff  | Agent 之间互相转交          | 客服场景     |

★ Insight ─────────────────────────────────────
- Agent 不是新概念——它就是把"原本写死的 if/else 工作流"换成"LLM 决定下一步"。所以 Agent 工程师本质是工作流工程师 + LLM
- "Multi-Agent" 经常被滥用——很多场景单 Agent + 好工具就够了。能讲清"什么时候不该上 Multi-Agent" 比会写 Multi-Agent 更值钱
- JD 里的"Session/State / Planning / Tool-use / Memory" → 全是 Agent 的子模块。LangGraph 的 StateGraph 就是把这些子模块图形化编排
─────────────────────────────────────────────────

---

## 三、这些概念怎么串起来？

用一个 Coding Agent 例子串一遍，你看着这张图就懂了：

```
用户："给这个项目加一个用户登录接口"
                ↓
        [Agent 主循环 ← 第 5 层]
                ↓
  ┌─────────────┼─────────────┐
  ↓             ↓             ↓
[Plan 节点]  [Code 节点]  [Review 节点]
  ↓             ↓             ↓
  └────→ 调用 LLM (deepseek-chat) ←── 第 1 层
                ↑
         [Prompt 模板] ← 第 2 层
                ↑
         拼入：用户问题
              + RAG 检索的相关代码 ← 第 3-4 层
              + 历史对话(滑窗压缩) ← Context Engineering
              + 工具列表 JSON Schema ← Tool Calling
                ↓
         LLM 决定调用 read_file / apply_patch / run_tests
                ↓
         你的代码执行 → 结果回传 → 下一轮
                ↓
         全程被 Langfuse 监控 ← 第 6 层
```

记住这个图，你已经超过 80% 的"AI 应用培训班毕业生"。

---

## 四、一句话学习排序（避免你抓瞎）

按重要性 → 给学习投入排序：

1. **Tool Calling**（必须 100% 掌握）—— Agent 的基石，面试必考代码题
2. **Agent Loop + LangGraph**（必须）—— JD 主考点
3. **RAG 端到端**（必须，含混合检索 + Reranker）—— 简历核心项目
4. **Prompt / Context Engineering**（边做边学）—— 不是孤立学，是在项目里磨
5. **LLM 模型选型 / 调参**（够用即可）—— 知道 temperature/top_p/seed 干嘛即可
6. **底层原理（Transformer/Attention）**（不用学）—— 算法岗的事，应用岗不考
