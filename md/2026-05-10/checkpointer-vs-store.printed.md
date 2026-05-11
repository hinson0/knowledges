# Checkpointer 家族 + Saver vs Store 的混淆

## 1. `MemorySaver` 和 `InMemorySaver` 是同一个类

```python
from langgraph.checkpoint.memory import InMemorySaver, MemorySaver
assert InMemorySaver is MemorySaver   # ← True
```

LangGraph 1.x 改名:`MemorySaver` → `InMemorySaver`,老名字保留为 alias。新代码用 `InMemorySaver`,命名风格和 `SqliteSaver` / `PostgresSaver` 对齐。

## 2. Checkpointer 家族(按持久化能力)

| 类 | import 路径 | 进程退出后 | 适用场景 |
|---|---|---|---|
| `InMemorySaver` (= `MemorySaver`) | `langgraph.checkpoint.memory` | **数据丢失** | 单元测试 / demo / 短任务 |
| `SqliteSaver` | `langgraph.checkpoint.sqlite` | 落到 .db 文件 | 单机 / 个人项目 |
| `AsyncSqliteSaver` | 同上 | 同上 | 异步 graph(`ainvoke` / `astream`) |
| `PostgresSaver` | `langgraph-checkpoint-postgres` 包(单独装) | 落到 PG 表 | 多进程 / 生产 |
| `AsyncPostgresSaver` | 同上 | 同上 | 异步 + 生产 |

口诀:

| 干啥 | 用哪个 |
|---|---|
| HITL minimal demo / 单测 | `InMemorySaver` |
| "中断后下次还能 resume"(week2 day3) | `SqliteSaver` |
| 多进程 / Langfuse trace 持久(week5+) | `PostgresSaver` |

## 3. Saver vs Store —— 两个完全不同的"记忆"

```python
# Saver:存 graph 状态 snapshot,跨 invoke 续跑用
from langgraph.checkpoint.memory import InMemorySaver
checkpointer = InMemorySaver()

# Store:存语义信息,跨 thread 检索用
from langgraph.store.memory import InMemoryStore
store = InMemoryStore()

app = graph.compile(checkpointer=checkpointer, store=store)
```

| 维度 | Checkpointer / Saver | Store |
|---|---|---|
| 管什么 | "这个 thread 跑到哪一步,state 是啥" | "用户/项目/会话级的事实和偏好" |
| 粒度 | 每个 thread 每步一个 snapshot | 跨 thread 共享 |
| 用途 | resume / time travel / HITL | 长期记忆 / 用户偏好召回 |
| 检索方式 | by `thread_id + checkpoint_id` | by namespace + key,可挂 embedding 做语义检索 |
| Week 计划 | week2 day3-4 | week2 day5(SQLite + bge-m3) |

混淆点:都叫"memory",但管的是完全不同的事情。

- "Agent 上次跑到一半被中断,下次能不能续?" → Checkpointer
- "Agent 能不能记得上周用户说他喜欢 Python?" → Store

## 4. compile 时的实践

```python
# 测试 / demo:不留垃圾文件
app = graph.compile(checkpointer=InMemorySaver())

# 工程:落盘续跑
from langgraph.checkpoint.sqlite import SqliteSaver
with SqliteSaver.from_conn_string("checkpoints.db") as cp:
    app = graph.compile(checkpointer=cp)
    # ... 用 app

# 长期记忆 + state 续跑
app = graph.compile(checkpointer=cp, store=store)
```

## 关联

- `hitl-interrupt-mechanism.md` — 为什么 interrupt 必须有 checkpointer
- `~/ai_agent_learning/week2/day3_sqlite_resume.py` — SqliteSaver 实战
- week2 day5(待写)— Store + bge-m3 长期记忆召回
