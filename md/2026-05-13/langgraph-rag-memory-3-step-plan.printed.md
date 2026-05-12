# LangGraph 长期记忆 RAG · 三步收口路线图(取/注/存)

> 来源:`week2/day5_workspace/0512/1549.md`(2026-05-12 流水笔记,落盘日 2026-05-13)
> 对应工作目录:`week2/day5_workspace/`,主代码 `day5_memory.py`,持久化 `memories.sqlite`

## 概念

day5 长期记忆作业的**完成度诊断 + 收口方案**:基础设施已就绪(数据层 / 调试层 / Graph 骨架 / State schema 都 ✅),业务逻辑层(拓扑图上的两条箭头 ↑↓)还没接,完成度大概 50%。把剩下的工作拆成 3 个节点对应 **RAG 的核心三件事:取 → 注 → 存**。

## 已完成层级表

| 层           | 状态 | 内容                                                           |
| ------------ | ---- | -------------------------------------------------------------- |
| 数据层       | ✅   | `MemoryStore` 类(put/search/all)+ SQLite 表 + bge-m3 embedding |
| 调试层       | ✅   | 10 条 mock + 6 个 query + score 分布(0.6197 命中 / < 0.5 噪音) |
| Graph 骨架   | ✅   | `build()` 里 4 个节点 + 边都连好了                             |
| State schema | ✅   | 加了 `retrieved_memories` 字段                                 |

## 没完成的拓扑(两条箭头)

```
                    ↑ inject 注入箭头        ↓ summarize 落库箭头
                    │                       │
START → retrieve → llm ─(should_continue)─┬→ tools → llm
                                          └→ summarize → END
        ╰── ❌ Step 1 ──╯        ╰── ❌ Step 3 ──╯
                ↑
         ❌ Step 2 在这里发生(call_llm_with_memory 内)
```

3 个 TODO 节点对应 **RAG 的核心三件事**:**取 → 注 → 存**。

## 接下来 3 步走(按难度递增)

### Step 1 · `retrieve_memory` 节点 — 把 search 接进 graph 【15 min,最容易】

**所有答案已经在 score 分布里给了**:

- query 怎么选?→ `state["messages"][-1].content` (最新 HumanMessage)
- threshold 多少?→ 看跑出的 6 个 query,**0.55 是 ✅ 命中和 ⚠ 噪音的天然分界**
- 返回啥?→ `{"retrieved_memories": [s for score, s in hits if score >= 0.55]}`

**验证标准**:单独跑 `retrieve_memory({"messages": [HumanMessage("我电脑啥配置")]})`,返回应该是 `{"retrieved_memories": ["用户硬件:Mac M2 Pro..."]}`。

### Step 2 · `inject_context` 函数 — 把召回拼进 SystemMessage 【10 min】

- 空召回 → 原 messages 直接返回
- 非空 → 拼一条 `SystemMessage("## 已知事实\n- xxx\n- yyy")` **prepend 到最前面**

**验证标准**:print 一下 `call_llm_with_memory` 内部构造的 `enriched_messages`,应该比原 messages 多一条 SystemMessage,且 LLM 回复里出现了 mock 数据的事实。

### Step 3 · `summarize` 节点 — 抽事实落库 【30-60 min,本周最难】

**这是 day5 真正考察的点**。结构上分三步:

1. 把 `state["messages"]` 序列化成可读文本(`user: xxx / assistant: yyy` 多行)
2. 调 LLM 用摘要 prompt(`call_llm` 不能直接复用,因为它带工具集,要写一个无工具版的简单调用)
3. parse LLM 输出 → 多行 split → 逐条 `STORE.put(thread_id, line)`

**第一版 prompt** stub 里已经有了(line 324 那个 f-string),可以直接用,跑完看效果再调。

**会撞的坑(预告)**:

- LLM 返回 "SKIP" / 空 / 一段没换行的废话 → 落库前要 strip + filter
- LLM 输出带 markdown bullet `- xxx` → `lstrip("-•* ")` 已经在 stub 里
- 摘要重复了已有事实 → day5 第一版不去重,week4 RAG 再做

## 端到端验证(day5 完成标准)

**跑这个剧本**,Agent 必须通过:

```python
# 清库
import os; os.remove("./memories.sqlite")
# 重启 STORE(因为 connection 失效)

# Thread 1:植入事实
app.invoke({
    "messages": [HumanMessage("我电脑是 Mac M2 + Python 3.12,主要写 FastAPI 后端")],
    "thread_id": "t1",
}, {"configurable": {"thread_id": "t1"}})

# 检查 memory 库是否有新条目
print(STORE.all())  # 应该看到 LLM 摘要后落的事实

# Thread 2:跨 thread 召回(全新对话)
result = app.invoke({
    "messages": [HumanMessage("我电脑配置是啥来着?")],
    "thread_id": "t2",
}, {"configurable": {"thread_id": "t2"}})

print(result["messages"][-1].content)
# ← 必须出现 "Mac M2" 或 "Python 3.12" 或 "FastAPI"
```

**通过 = day5 RAG 最小闭环完成**。这一刻就**真正会 RAG 了**,week4 只是换个 source(代码 chunks 代替对话摘要)。

## 坑/Why:Insight

`★ Insight ─────────────────────────────────────`

- **score 分布(0.6197 命中 / < 0.5 噪音)就是 day5 简历的第一行数字**。CLAUDE.md 铁律 4:"所有数字必须真实"。跑出来的这 30 个 score 是**真实测量**,不是猜的 —— 简历可以写"通过 6 个测试 query 的 score 分布观察,把 threshold 从默认 0.5 调到 0.55,噪音召回率从 X% 降到 Y%"。**这一刻起,已经在攒可量化经验**,而不只是写代码。
- **Step 3 summarize 的"prompt 设计"是 day5 真正分水岭**。Step 1-2 任何会 Python 的人都能写,但 Step 3 会反复改 prompt:第一版可能让 LLM 把"用户问了 fibonacci 怎么写"也算成事实,后来 prompt 加上"丢弃过程性叙述,只保留 typed 事实",效果立刻好。**这种"prompt 调到 LLM 行为符合预期"的迭代手感,是 AI Agent 工程师的核心技能** —— week6 mini-Aider 的 Planner / Coder / Reviewer 三个 agent 全靠这种调 prompt 的本事。
- **完成 day5 后,应该可以 5 分钟内向陌生人讲清 RAG 是啥**:"我有个 SQLite 库存历史对话的摘要,新对话来时把问题变向量算余弦找最像的 3 条塞回 prompt,LLM 就能用上历史"。能用一句话讲清 = 真懂了。**写一个 30 秒录屏 demo + 这句解释,就是 week2 周末交付物**(CLAUDE.md week2 主线那张表里的"产出")。

`─────────────────────────────────────────────────`

## 推荐工作流

```
今晚(30 min)         : 写 Step 1 + Step 2(基础链路通),用 mock 数据验证 inject 后 LLM 能引用事实
明早(60 min)         : 写 Step 3 summarize,反复调 prompt,看 STORE.all() 看抽出来的事实质量
明晚(30 min)         : 端到端验证 剧本跑通,清库重跑 5 次确认稳定
后天(30 min)         : 知识落盘到 ~/knowledges/md/2026-05-12/(用 summary skill)
```

写到任一 Step 卡住,把代码贴回来或截图问。**重点是写 summarize prompt 时遇到的纠结** —— 那是 day5 真正的金矿。

## 关联

- `week2/day5_workspace/day5_memory.py` — 主代码(含 `MemoryStore` / `build` / 4 节点 stub)
- `week2/day5_workspace/memories.sqlite` — 持久化层
- CLAUDE.md week2 路线表 — Day 5 "长期记忆:SQLite + bge-m3 embedding 存历史摘要,语义召回 top-3"
