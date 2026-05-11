# Memory 摘要：是什么 / 为什么是摘要 / 怎么写

> 来源：week2/day5_workspace/0510_2/1833.md。memory 摘要 = 把一整段对话压缩成 1-2 句"对未来有用的事实"，存起来供以后召回。

## 1. "memory" 在 day5 里指什么？

**不是 LLM 的"记忆能力"**（LLM 本身没记忆，每次对话都是新的）。
**而是 day5 自己造的一个 SQLite 表 + 检索逻辑**，功能是"记住跨 thread 的事实"。

回顾 day3-4 已会的：

- **checkpointer**（`SqliteSaver`）= 记住"thread A 跑到第几步了" → 解决**续跑**
- **memory**（day5 新做的）= 记住"thread A 里用户告诉过我啥" → 解决**跨 thread 知识**

```text
Thread 1（周一）：
  用户：我电脑是 Mac M2，Python 3.12
  Agent：好的（thread 结束）
  ↓
  ↓ ★ 关键问题：Thread 1 结束后，这个事实存哪？
  ↓

Thread 2（周三，新对话）：
  用户：我环境配置是啥来着？
  Agent：???  ← 没 memory 系统的话，Agent 完全不知道
```

**memory 库的作用就是接住周一那条事实，周三能召回**。

## 2. 为什么是"摘要"不是"原文"？

`Thread 1` 的实际对话可能是这样：

```text
SystemMessage: "你是一个简洁的代码助手。"
HumanMessage:  "我电脑是 Mac M2，Python 3.12，主要写 FastAPI 后端。"
AIMessage:     "好的，记下了。Mac M2 配合 Python 3.12 跑 FastAPI 没问题，..."
HumanMessage:  "顺便我还在用 SQLAlchemy。"
AIMessage:     "OK，SQLAlchemy 很常见。需要 async 的话推荐用 SQLAlchemy 2.0..."
HumanMessage:  "对了，你帮我写个 fibonacci 函数吧"
AIMessage:     [tool_call: write_file]
ToolMessage:   "写入成功"
AIMessage:     "已经写好了，要不要我跑一下测试?"
HumanMessage:  "不用，谢谢"
```

如果 day5 你**直接存原文**：

- ❌ 9 条消息全进库，每条都要 embedding，占空间
- ❌ "已经写好了，要不要我跑一下测试?" 这种废话也参与召回
- ❌ Thread 2 用户问"我环境是啥"，可能召回到无关的"测试要不要跑" → 噪音

如果**让 LLM 把这段对话压缩成摘要**：

```text
用户硬件：Mac M2 + Python 3.12
用户工具栈：FastAPI + SQLAlchemy
```

- ✅ 2 条事实进库，精简
- ✅ 寒暄、操作过程、废话全丢
- ✅ Thread 2 召回时只命中"硬实事实"，干净

**摘要 = 蒸馏对话 → 留下"对未来有用的事实"，丢掉过程性废话**。

## 3. day5 里"摘要"具体长啥样？

`memories` 表里实际存的就是这些字符串：

```python
{"id": 1, "thread_id": "t1", "summary": "用户硬件 Mac M2 + Python 3.12"}
{"id": 2, "thread_id": "t1", "summary": "用户工具栈 FastAPI + SQLAlchemy"}
{"id": 3, "thread_id": "t1", "summary": "用户偏好 fibonacci 用递归实现"}

{"id": 4, "thread_id": "t2", "summary": "用户在做电商项目，后端用 PostgreSQL"}
{"id": 5, "thread_id": "t3", "summary": "用户开了一个新仓库 my-blog，使用 Next.js + TypeScript"}
```

每条**摘要**是：

- 1-2 句话
- 主语通常是"用户"或"项目"
- 表达**事实/偏好/环境/决策**
- 删掉了所有"嗯好的"、操作过程、错误尝试

## 4. 摘要从哪来？谁产生的？

**LLM 产生的** —— 这就是 `day5_memory.py` 里 `summarize()` 节点要做的事：

```python
def summarize(state):
    # 把整段对话(state["messages"])给 LLM 看
    convo = "..."  # 序列化对话

    # 让 LLM 抽取事实
    summary = LLM("把以下对话压成 1-2 条事实:..." + convo)
    # → "用户硬件 Mac M2 + Python 3.12"

    # 落库
    STORE.put(thread_id, summary)
```

**`summarize` 是 day5 三个 TODO 里最难的那个**，因为这个 prompt 决定召回质量天花板：

- prompt 写废 → LLM 抽出"用户问了 fibonacci 怎么写" → 没用，后面召回用不上
- prompt 写好 → LLM 抽出"用户偏好递归实现 + 用 Mac M2" → 有用，跨 thread 真能帮上忙

## 5. 一图串起来

```text
Thread 1（完整对话 9 条 messages）
   ↓
   ↓ summarize 节点（用 LLM 抽事实）
   ↓
   ┌──────────────┐
   │  摘要 string  │   "用户硬件 Mac M2 + Python 3.12"
   └──────────────┘
   ↓
   ↓ MemoryStore.put(thread_id, summary)
   ↓ (内部：_embed(summary) 算 1024 维向量，存 SQLite BLOB)
   ↓
┌─────────────────────────────────────────┐
│ memories 表（跨 thread 共享）            │
│   id  thread  summary               vec │
│   1   t1      用户硬件 Mac M2...    [...]│
│   2   t1      用户工具栈 FastAPI... [...]│
│   3   t2      用户在做电商项目...    [...]│
└─────────────────────────────────────────┘
   ↑
   ↑ Thread 2 用户问问题时
   ↑ retrieve_memory 节点 → MemoryStore.search("我环境是啥") → 召回 top-3
```

## 坑 / Why

- **"摘要"这个词在 RAG 语境里和写作课的"摘要"不同**。写作课的摘要追求"保留主旨、缩短篇幅"；RAG 的摘要追求"**保留对未来 query 有召回价值的事实**"。两个目标完全不同——写作摘要会保留"用户和 Agent 探讨了 fibonacci 的实现"，RAG 摘要会保留"用户偏好 fibonacci 递归版"。**前者描述发生了什么，后者沉淀有用的什么**。
- **摘要不一定要 LLM 做**，这是 day5 的简化选择。生产 RAG 系统里，"什么算有用事实"可能由领域规则决定（比如客服系统就抽 `{用户ID, 订单号, 问题类型}`，根本不让 LLM 自由发挥）。但 day5 先用 LLM 做最通用的版本，等踩坑再升级到结构化抽取。
- **摘要是 day5 召回质量的"上游"——prompt 写废了，后面什么 reranker 都救不了**。这就是为什么把 summarize 标成 ⭐⭐⭐ 难度。week4 会再次验证这点：**RAG 80% trade-off 在"存什么"，不在"怎么检索"**。新手会把时间花在调 top-k 和阈值，老手会把时间花在调 chunk 切分和摘要 prompt。

## 6. 摘要写作示例（同对话三种侧重）

### 版本 1：技术栈侧重（推荐用这个存 memory）

> 用户使用 Mac M2、Python 3.12 开发 FastAPI 后端，配合 SQLAlchemy（建议用 2.0 async 版本）。曾请求编写 fibonacci 函数，已通过 write_file 工具完成。

### 版本 2：偏档案式

> 用户的开发环境：Mac M2 + Python 3.12 + FastAPI + SQLAlchemy。本次对话中协助其生成了一个 fibonacci 函数文件。

### 版本 3：更口语自然

> 用户在 Mac M2 上用 Python 3.12 写 FastAPI 后端，使用 SQLAlchemy ORM。本次会话为其创建了 fibonacci 函数文件，用户表示无需进一步测试。

## 7. memory 写作建议（profile vs episodic）

存 agent memory 时，**版本 1 这种结构最实用**，因为它把两类信息分开了：

1. **持久性事实（profile 类）**：技术栈、环境、偏好——这些以后每次对话都用得上
2. **本次任务事实（episodic 类）**：写了 fibonacci 函数——这个用处会随时间衰减

很多 memory 系统（比如 LangGraph memory、mem0、Letta 之前的 MemGPT）会建议把这两类**分开存**：

```text
profile_memory:
  - OS: Mac M2
  - Python version: 3.12
  - Framework: FastAPI
  - ORM: SQLAlchemy

task_memory:
  - 2026-05-10: 编写了 fibonacci 函数 (write_file 完成)
```

如果 memory 库支持结构化字段，分两类存比塞一段散文更利于后续检索和更新。
如果只能存自由文本两句话，**用版本 1**。

## 一句话总结

**memory 摘要** = LLM 把一整段对话压成 1-2 句"对未来有用的事实"，作为字符串 + 它的 embedding 向量，一起存进 SQLite。后面新 thread 提问时，先把问题 embedding，跟所有摘要算余弦相似度，拉 top-3 塞进 LLM context，Agent 就"记得"这些事实了。

## 关联

- [long-term-memory-design.md](./long-term-memory-design.md) — summarize 节点在 graph 里的位置
- [embedding-vs-llm-and-rag.md](./embedding-vs-llm-and-rag.md) — 摘要为什么需要 embedding
- [checkpointer-vs-store.md](./checkpointer-vs-store.md) — checkpointer 和 memory 的不同分工

---

来源：week2/day5_workspace/0510_2/1833.md
落盘日期：2026-05-10
