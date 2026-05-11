# Day 5 长期记忆系统：设计、推演、跑通

> 来源：week2/day5_workspace/0510_2/1514.md + 1645.md + 1656.md。day5 长期记忆模块从设计到落地的完整推演与跑通报告。

## 1. Why（承接 Day 4）

Day 3-4 解决的是"**单 thread 内的状态续跑**"：同一个 thread，中断后还能 resume，checkpointer 帮你保住 state。但有两个场景 checkpointer 解决不了：

| 场景 | checkpointer 能不能? | 为什么 |
|------|--------------------|-------|
| "Agent 上次跑到一半中断，下次能不能续?" | ✅ 能 | 同 thread，checkpoint_id 续上 |
| "上周 thread A 用户说他喜欢 Python，这周 thread B 里 Agent 能不能记得?" | ❌ 不能 | 跨 thread，checkpoint 是 thread-scoped 的 |
| "Agent 跑了 50 轮 messages，context 撑不下了" | ❌ 不能 | 状态续跑 ≠ 状态压缩 |

**长期记忆 = 跨 thread 的语义事实库 + 当前 thread 的检索注入**。它不是 graph 状态的延伸，是 **Agent 的"知识"**（对比 Saver 是 Agent 的"工作记忆"）。

复习 day5 落盘的 `checkpointer-vs-store.md`：Saver 管"跑到哪了"，Store 管"知道什么"。**day5 干的就是 Store 这一边**。

## 2. 技术路线对比（三条路，层级从高到低）

| 路线 | 写法 | 你能学到什么 | 适合 |
|------|------|------------|------|
| **A · LangGraph 1.x `InMemoryStore` + 内置 embed** | `store = InMemoryStore(index={"embed": embed_fn, "dims": 1024})`，在节点里 `store.put` / `store.search` | 高层封装：LangGraph 的 Store 抽象 + namespace 隔离 + 自动相似度 | 已经会底层，想快速上线 |
| **B · 自建 SQLite + bge-m3（CLAUDE.md 写定的路线）** | 自己开表存 `(id, thread_id, summary, embedding BLOB, created_at)`，自己做 batch embed + 余弦排序 | 底层机制：embedding 维度 / 序列化 / 召回排序 / threshold | **第一次做长期记忆，推荐这条** |
| **C · 直接上 Chroma / Qdrant** | `client.create_collection(...)`，框架替你管所有细节 | 生产级向量库的接口 | week4 RAG 周才会用 |

**推荐 B，故意先踩 CLAUDE.md 写好的两个坑（维度不匹配 / 召回不相关），再切 A 体感"高层封装到底替你做了什么"**。这跟 day4 "先 B 路线 baseline 再切 A interrupt()" 是同一种学法。

## 3. 设计四问（开始干之前先想清楚）

跟 day4 一样，**先把协议定下来再写代码**。这次有 4 问，但 Q1 是核心，后面跟着收窄。

### Q1 · 存什么?（memory 的内容粒度）

| 档位 | 存的内容 | trade-off |
|------|---------|----------|
| ① 原文 | 每条 messages 原样存 | ✅ 不丢信息<br>❌ token 巨贵，召回噪音大，相邻消息互抢 |
| ② 摘要 | 每个 thread 跑完后让 LLM 摘要成 1-2 句 | ✅ 精简，召回准<br>❌ 摘要质量决定一切，LLM 摘错了你不知道 |
| ③ 事件抽取 | 抽 `{"fact": "用户喜欢 Python", "type": "preference"}` 这种结构化事实 | ✅ 最精准，可按 type 过滤<br>❌ 抽取规则难写，容易遗漏 |

**判断锚点**：你这个长期记忆是给"Agent 自己用"还是"未来给用户看"？给 Agent 用 → ②/③（精简就行）；给用户回顾 → ① 留底。

### Q2 · 何时存?（写入时机）

| 候选 | 写法 | 影响 |
|------|------|------|
| A · graph END 时统一存 | 加一个 `summarize` 节点接在 END 前 | 简单，但中途崩了就丢 |
| B · 每个 LLM 轮次后都存 | call_llm 节点尾部 hook | 实时但啰嗦，容易存重复 |
| C · LLM 自己调 `save_memory` 工具决定 | 给 Agent 一个"记一下"的工具 | 智能但难评估 LLM 决策质量 |

### Q3 · 何时取 + 用什么 query 召回?

| 候选 | 召回时机 | query 内容 |
|------|---------|-----------|
| X · call_llm 入口 | 每轮 LLM 调用前 | 最新 user message 原文 |
| Y · query rewriting | call_llm 入口，但先让小 LLM 重写 | 重写后的 query（更完整）|
| Z · reasoning-driven | 用上一轮的 reasoning_content 当 query | 更结构化 |

### Q4 · 召回结果怎么注入 LLM context?

| 候选 | 写法 | LLM 怎么"看见" |
|------|------|---------------|
| P · 拼到 SystemMessage | `system_prompt += "\n\n## 你过去知道的:..."` | 透明，但 prompt 越拼越长难调试 |
| Q · 单独一条 SystemMessage | 召回结果做成独立 SystemMessage 放在用户消息前 | 清晰边界，可单独移除 |
| R · 加 retrieved_context state 字段 | 改 AgentState schema，call_llm 内部模板拼接 | 显式但啰嗦（回到 day4 Q3 的 in-band vs out-of-band 之争）|

## 4. 设计四问 · 详细选项与推荐答（带具体示例）

### Q1 · 存什么 — 三档位详细对照

#### 选项 ① · 存原文

**长这样**：每条对话原样进表

```python
# memory 表里实际存的内容
{"id": 1, "thread": "t1", "role": "user",      "content": "帮我写一个 fibonacci 函数"}
{"id": 2, "thread": "t1", "role": "assistant", "content": "好的，这是用迭代实现的版本..."}
{"id": 3, "thread": "t1", "role": "user",      "content": "改成递归"}
{"id": 4, "thread": "t1", "role": "assistant", "content": "好的，这是递归版..."}
{"id": 5, "thread": "t2", "role": "user",      "content": "我电脑是 mac M2，Python 3.12"}
```

下次新 thread 用户问"我的环境是啥"，召回会拉 id=5 进来——但也可能误拉 id=1（因为 "Python" 也匹配）。

**适合**：几乎从不，除非你做"对话历史回顾"产品。token 成本和召回噪音都吃不消。

#### 选项 ② · 存 LLM 摘要

**长这样**：thread 跑完后让 LLM 写 1-2 句

```python
# 一个 thread 跑完后产出
{
  "id": 1,
  "thread": "t1",
  "summary": "用户请求实现 fibonacci 函数，先给了迭代版，后改成递归版",
  "created_at": "2026-05-10T10:00:00"
}
{
  "id": 2,
  "thread": "t2",
  "summary": "用户硬件:Mac M2，使用 Python 3.12",
  "created_at": "2026-05-10T11:00:00"
}
```

下次问"我的环境是啥"，召回 id=2，Agent 直接说"你用 Mac M2 + Python 3.12"，**不需要看原 5 条对话**。

**摘要 prompt 长这样**（让 LLM 自己产）：

```text
把下面的对话压缩成一句话事实，只保留以后可能有用的:
- 用户的偏好/选择
- 用户的硬件/环境/工具栈
- 项目的关键决策

[对话内容]
```

**适合**：**99% 的新手第一版**——ROI 最高，实现简单，效果直觉好。坑也只有"摘要质量"一个。

#### 选项 ③ · 结构化事件抽取

**长这样**：LLM 抽取成 typed 字段

```python
{"type": "preference",  "key": "language",  "value": "Python",      "confidence": 0.9}
{"type": "environment", "key": "os",        "value": "Mac M2"}
{"type": "environment", "key": "py_ver",    "value": "3.12"}
{"type": "decision",    "key": "fib_impl",  "value": "用递归版而非迭代版"}
```

召回时可以**按 type 过滤**："我环境是啥" → 只查 type=environment，精度爆表。

**适合**：进阶版。要写抽取 schema + 抽取 prompt + 后处理（去重/冲突合并），工作量是 ② 的 3 倍。**新手别上来就做这个，会陷进去**。

#### 🎯 推荐：**②**。简单明了，踩坑也学得到东西。

### Q4 · 怎么注入 LLM context — 三方案详细对照

#### 选项 P · 拼到原 SystemMessage 里

**长这样**：

```python
SYSTEM_PROMPT = "你是一个简洁的代码助手。"

# 召回 3 条记忆后,改写
def build_messages(state, memories):
    sys = SYSTEM_PROMPT
    if memories:
        sys += "\n\n## 你过去知道的事实:\n"
        for m in memories:
            sys += f"- {m['summary']}\n"
    return [SystemMessage(sys)] + state["messages"]
```

LLM 看到的：

```text
SystemMessage: "你是一个简洁的代码助手。

## 你过去知道的事实:
- 用户硬件:Mac M2，使用 Python 3.12
- 用户偏向递归实现 fibonacci"

HumanMessage: "我环境是啥"
```

- **优**：LLM 把"过去事实"和"角色定位"看成一个整体，**注入感最弱**（LLM 不会反复说"根据你过去告诉我的..."）
- **劣**：debug 难——SystemMessage 每轮都不一样，Langfuse 看 trace 时分不清"哪部分是基础 prompt，哪部分是召回"

#### 选项 Q · 独立一条 SystemMessage

**长这样**：

```python
def build_messages(state, memories):
    msgs = [SystemMessage(SYSTEM_PROMPT)]   # 基础 prompt 不动
    if memories:
        memory_text = "\n".join(f"- {m['summary']}" for m in memories)
        msgs.append(SystemMessage(f"## 已知事实\n{memory_text}"))   # ← 单独一条
    msgs += state["messages"]
    return msgs
```

LLM 看到的：

```text
SystemMessage: "你是一个简洁的代码助手。"
SystemMessage: "## 已知事实
- 用户硬件:Mac M2，使用 Python 3.12
- 用户偏向递归实现 fibonacci"
HumanMessage: "我环境是啥"
```

- **优**：清晰边界，**调试时一眼看出是召回出问题还是基础 prompt 出问题**。想关闭召回？直接不 append 这条，基础 prompt 不变
- **劣**：多数 LLM 对多个 SystemMessage 的处理不如单条稳定（但 DeepSeek/OpenAI 都支持得不错）

这一问的设计哲学跟 day4 你最后选的 "Q3=A 消息总线"一致：**让中间产物也走统一通道，不藏在变量里**。

#### 选项 R · 改 state schema 加 retrieved_context 字段

**长这样**：

```python
class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    iter_count: int
    retrieved_context: list[str]   # ← 新加

# call_llm 节点内部模板
def call_llm(state):
    ctx = state.get("retrieved_context", [])
    sys = SYSTEM_PROMPT
    if ctx:
        sys += "\n\n## 已知事实\n" + "\n".join(f"- {x}" for x in ctx)
    msgs = [SystemMessage(sys)] + state["messages"]
    return {"messages": [llm.invoke(msgs)]}
```

- **优**：召回结果跟 messages 解耦，checkpoint 里清晰可见"这一轮注入了什么"。后续做 A/B 测试时，比较"有 ctx vs 无 ctx"很方便
- **劣**：回到 day4 Q3 的 in-band vs out-of-band 之争——state 字段越多越复杂，需要给 retrieved_context 也写 reducer（还是每轮覆盖?）

#### 🎯 推荐：**Q**。

理由：

1. 跟 day4 设计风格一致（消息总线）
2. 调试最友好——出问题第一时间能定位是召回的 SystemMessage 还是基础 prompt
3. 实现最简单——不用动 state schema

### 技术栈层级 — B 自建 vs A `InMemoryStore`

#### 选项 B · SQLite + bge-m3 自建

**实际代码长这样**（即将要写的脚手架）：

```python
import sqlite3, numpy as np, requests

# 1. 建表
conn.execute("""
    CREATE TABLE memories (
        id INTEGER PRIMARY KEY,
        thread_id TEXT,
        summary TEXT,
        embedding BLOB,           -- ← 序列化的 numpy array
        created_at TEXT
    )
""")

# 2. 调 bge-m3 拿 embedding
def embed(text: str) -> np.ndarray:
    r = requests.post(
        "https://api.siliconflow.cn/v1/embeddings",
        headers={"Authorization": f"Bearer {SILICONFLOW_KEY}"},
        json={"model": "BAAI/bge-m3", "input": text}
    )
    return np.array(r.json()["data"][0]["embedding"], dtype=np.float32)  # ← 1024 维

# 3. 存
def save(thread, summary):
    vec = embed(summary)
    conn.execute(
        "INSERT INTO memories (thread_id, summary, embedding, created_at) VALUES (?, ?, ?, ?)",
        (thread, summary, vec.tobytes(), datetime.now().isoformat())
    )

# 4. 召回(自己算余弦)
def search(query: str, k: int = 3) -> list:
    q_vec = embed(query)
    rows = conn.execute("SELECT id, summary, embedding FROM memories").fetchall()
    scored = []
    for id_, summary, blob in rows:
        v = np.frombuffer(blob, dtype=np.float32)         # ← 这里维度错了你能撞上!
        score = np.dot(q_vec, v) / (np.linalg.norm(q_vec) * np.linalg.norm(v))
        scored.append((score, summary))
    scored.sort(reverse=True)
    return scored[:k]
```

**会撞的坑（CLAUDE.md 已预告）**：

- `dtype` 写错（存 float64 取 float32）→ 维度从 1024 变 2048 → 崩
- bge-m3 的 input 太长（>8192 token）→ API 报 413 → 你得切 chunk
- SQLite 表里 5000 条以后 SELECT 全表 + numpy 算余弦慢到要命 → 学到 ANN 索引存在的必要性

**收获**：**真正理解 Chroma/Qdrant 帮你做了什么**。week4 上 Chroma 时，你不会觉得是黑盒。

#### 选项 A · LangGraph `InMemoryStore`

**实际代码长这样**：

```python
from langgraph.store.memory import InMemoryStore

# 一行注册 embedding
store = InMemoryStore(
    index={"embed": embed_fn, "dims": 1024, "fields": ["summary"]}
)

# 存(framework 自动算 embedding)
store.put(("user_1", "memories"), key="mem_1", value={"summary": "用户用 Mac M2"})

# 召回(framework 自动算 cosine)
results = store.search(("user_1", "memories"), query="我的环境是啥", limit=3)
```

- **优**：10 行写完
- **劣**：你不知道里面发生了什么。维度怎么对的？cosine 怎么算的？数据怎么序列化的？**全是黑盒**

#### 🎯 推荐：**B 自建，跑通后再用 A 跑一遍对比**。

CLAUDE.md "实践优先 5 铁律"第 5 条："不许跳过为什么不工作"。**B 路线注定要踩两个坑，这是教学路径**。
A 路线 30 分钟跑通，但 week4 Chroma 你心里没底。

### 长期记忆的范围 — 第一版做什么

#### 范围 ① · 用户偏好/项目事实

**长这样**（每个 thread 跑完后产出 0-3 条事实）：

```text
- 用户偏好递归实现 > 迭代实现
- 项目用 FastAPI + SQLAlchemy
- 用户硬件 Mac M2 + Python 3.12
```

跨 thread 召回：简单、价值清晰。

#### 范围 ② · messages 压缩（对抗 context 超长）

**长这样**（同一个 thread 跑到第 50 轮，前 40 轮被压缩成）：

```text
[历史摘要] 第 1-40 轮:用户让你实现了 fibonacci/binary_search/quicksort,
代码都过测试。当前文件状态:src/algos.py 包含 3 个函数。
```

塞回 messages[0]，把原 40 条原文 drop。

#### 🎯 推荐：**①**。

理由：

1. 跟 day4 的 thread 隔离自然衔接（每个 thread 的"成果"沉淀成跨 thread 知识）
2. 范围 ② 涉及 LangGraph 的 `RemoveMessage` API，是另一个机制，挤进来一天搞不完
3. 简历卖点——"跨 thread 长期记忆"比"context 压缩"更直观体现"Agent 在变聪明"

### 推荐组合一览（新手第一版）

| 决策 | 选项 | 一句话理由 |
|------|------|----------|
| Q1 存什么 | **② LLM 摘要** | 摘要 prompt 一个 trade-off，容易调，效果立竿见影 |
| Q4 怎么注入 | **Q 独立 SystemMessage** | 跟 day4 消息总线设计一致，调试最友好 |
| 技术栈 | **B SQLite + bge-m3 自建** | CLAUDE.md 写定的踩坑路线 |
| 范围 | **① 用户偏好/事实** | 跨 thread 价值清晰，简历好讲 |

## 5. CLAUDE.md 故意踩的两个坑（预告）

跑通后会撞到：

1. **embedding 维度不匹配** —— bge-m3 是 1024 维，你存 BLOB 时如果用 `np.array(..., dtype=np.float64)` 是 8192 字节；读回来如果用 `dtype=np.float32` 解出来是 2048 维，余弦计算直接 dimension mismatch。**这是序列化协议错位的微缩样本**，跟 day4 OpenAI 协议刚性、render_payload key 漂移是同一类教学陷阱。
2. **召回结果跟当前问题无关** —— 用户问"帮我写个 fibonacci"，召回回来"用户喜欢 Python"。语义"沾边"但对当前任务无用。这是 RAG 工程的核心难题：**相似 ≠ 相关**。修法是 score threshold + reranker（week4 才完整学，day5 先做 threshold）。

## 6. 实现跑通：基础链路 + 召回相关性问题

**基础链路跑通了**，而且立刻撞上 CLAUDE.md 预告的"召回相关性"坑：

```text
=== query: 我电脑啥配置 ===
  0.5724  用户硬件 Mac M2，Python 3.12     ← ✅ top1 正确
  0.5189  今天天气不错                       ← ⚠ 第二居然是天气!score > 0.5 阈值
  0.4624  用户偏好 FastAPI + SQLAlchemy

=== query: 后端用什么框架 ===
  0.5001  用户偏好 FastAPI + SQLAlchemy    ← ✅ top1 正确
  0.4632  用户硬件 Mac M2，Python 3.12
  0.3654  今天天气不错
```

### 跑通报告中的关键发现

- **bge-m3 中文 cosine 基线偏高**：同语言任意两段中文 baseline ≈ 0.35-0.55，这意味着 **`SCORE_THRESHOLD=0.5` 太松**，"今天天气不错"也能混进 query="我电脑啥配置" 的 top-3。**这就是 CLAUDE.md 预告的"召回结果与当前问题无关"在你眼前发生**——解决路径不是无脑提阈值（会把对的也滤掉），而是 Q2 那个设计：**top-k + 阈值 + 跑一批数据看 score 分布再调**（这个流程 week4 RAG 是核心技能）。
- **dtype 没撞坑** —— 因为我在 `_embed` 和 `search` 里都锁了 `float32`。等你后面想试"如果 dtype 写错会怎样"，把 `search` 那行改成 `dtype=np.float64` 重跑，会立刻看到 dimension mismatch。这是个**可控的踩坑入口**。
- **bge-m3 API 对中文短文本 latency ≈ 150ms/次**（从输出时间戳看），summarize 节点要小心：每条事实独立 embed 一次，如果 LLM 抽 3 条就是 450ms 加 LLM 的 1-2s。week4 调优时这是优化方向（"批量 embed" 一次 API 拿 N 条向量）。

## 7. 三个 TODO 节点（day5 真正考你的部分）

文件已落到 `week2/day5_memory.py`，332 行。代笔的部分（`MemoryStore` + graph build + main 测试）已验证通过。剩下 3 个 TODO 节点是 day5 真正考你的部分：

| 顺序 | 节点 | 难度 | 你要决定的 |
|------|------|------|-----------|
| 先写 → | `retrieve_memory` | ⭐ 容易 | Q1 query 选什么 / Q3 空召回返回啥 |
| 然后 → | `inject_context` | ⭐ 容易 | 拼 SystemMessage 的 markdown 格式 |
| 最后 → | `summarize` | ⭐⭐⭐ 难 | **prompt 怎么写决定召回质量天花板**，这是 day5 的命门 |

### 建议工作流

1. 先写 `retrieve_memory` + `inject_context`（15 分钟，无 LLM 调用，印象就有了）
2. 用 hardcoded `STORE.put(...)` 手工塞两条假摘要，跑 main 看 LLM 收到注入后的回复（验证注入链路）
3. 然后写 `summarize`——prompt 反复调，一版好一版烂的 trade-off 会非常明显
4. 最后整链路跑 thread1 → thread2，看 Agent 真的"跨 thread 记得"

写完任意一个 TODO 卡住，把代码贴回来 review。**重点是写 prompt 时遇到的纠结，那是 day5 真正的学习点**。

文件位置：`/Users/a114514/ai_agent_learning/week2/day5_memory.py:218`（retrieve_memory 起点）。

## 坑 / Why · 综合 Insight

- **长期记忆是 RAG 的最小完整形态**。week4 的 codebase RAG 比 day5 复杂的不是机制（embed + 召回 + 注入这套是同一套），而是 chunking 策略（代码切到一半语义就断）和召回精度（BM25 + 向量混合 + reranker）。**day5 跑通后，week4 就只是"把 source 从消息摘要换成代码 chunks"**。这就是为什么 week2 现在做长期记忆——给 week4 提前打地基。
- **"存什么"是 RAG 的 80% trade-off**，"怎么存"和"怎么召回"加起来 20%。新手会花一周调召回 top-k 和 reranker，老手会花一周调摘要 prompt。day5 你会亲身验证这点——Q1 选 ① 原文做出来效果差，改成 ② 摘要立刻好转。
- **跨 thread 的 namespace 设计很值得多想一秒**。LangGraph Store 用 tuple namespace（`("user_id", "memories")`），这跟文件系统目录是同一种思想。**day5 你哪怕用最简单的"全局共享" namespace 也行，但要意识到这个维度存在**——否则 week6 多用户 Agent 上线时，Alice 的偏好被注入到 Bob 的对话，直接事故。
- **"长期记忆"的本质是"换一种数据结构存对话历史"**。已经会的 messages list 是按时间顺序的"日记本"，换成 embedding-indexed 的 SQLite 就是"按主题翻阅的笔记本"。**同一份信息，索引方式不同，可用性天差地别**。
- **新手最容易在 Q3（用什么 query 召回）出错**，但你今天不需要决定——第一版用"最新 user message 原文当 query"就行。**等召回出现"沾边但不相关"时，再去学 query rewriting**。提前选 Y/Z 是过度设计。
- **bge-m3 选 1024 维不是随便选的**：它原生支持 dense + sparse + multi-vector 三种模式，1024 是 dense 模式。week4 RAG 你会撞上 sparse（BM25-like）和 multi-vector（ColBERT-like）的差异。**day5 第一版只用 dense 即可，但要知道这个模型还有另外两条腿没用**。

## 8. 设计阶段的开放问题（用户拍板用）

按 CLAUDE.md 的"先入为主了解知识点"原则，先回答 **Q1 + Q4**，Q2/Q3 跟着收窄：

1. **Q1 存什么** — 选 ① 原文 / ② 摘要 / ③ 事件抽取?（推荐 ② 起步，跑一次后再看要不要升级 ③）
2. **Q4 怎么注入** — 选 P 拼 system / Q 独立 SystemMessage / R 改 state schema?（day4 你选了 Q3=A 消息总线，如果想保持设计一致性，这次该选 Q；想体验一次 out-of-band 设计就选 R）

另外两个**前置选择题**：

3. **技术栈层级** — 走 B 自建（踩坑学底层），还是 A `InMemoryStore`（直接用框架）?
4. **长期记忆的范围** — 第一版只做"用户偏好/项目事实"召回，还是直接做"messages 压缩"（为后面 context 超长做准备）?

四个答完，就能开 day5_memory.py 的脚手架。

## 关联

- [checkpointer-vs-store.md](./checkpointer-vs-store.md) — Saver vs Store 的前置概念分清
- [memory-config-constants.md](./memory-config-constants.md) — day5_memory.py 的常量定义
- [memory-summary-prompt-design.md](./memory-summary-prompt-design.md) — summarize 节点的摘要写作
- [embedding-vs-llm-and-rag.md](./embedding-vs-llm-and-rag.md) — embedding/RAG 概念基础
- [bge-m3-model-card.md](./bge-m3-model-card.md) — embedding 模型详解

---

来源：week2/day5_workspace/0510_2/1514.md, 1645.md, 1656.md
落盘日期：2026-05-10
