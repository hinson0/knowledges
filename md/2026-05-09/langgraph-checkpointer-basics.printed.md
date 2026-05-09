# LangGraph Checkpointer 持久化基础

> 来源:Week 2 · Day 3
> 关键词:`MemorySaver` / `SqliteSaver` / `thread_id` / 持久化 / 续接

---

## 一句话总结

**Checkpointer 把 LangGraph 从"无状态状态机"变成"有状态、可恢复、可审计的状态机";代价是 invoke 调用约定从"塞完整 init_state"变成"只塞差分"。**

---

## 核心 API(就两行)

```python
from langgraph.checkpoint.memory import MemorySaver
# 或: from langgraph.checkpoint.sqlite import SqliteSaver

# ① compile 时挂载 checkpointer
checkpointer = MemorySaver()
app = graph.compile(checkpointer=checkpointer)

# ② invoke 时必须传 thread_id(藏在 config.configurable 里)
config = {"configurable": {"thread_id": "session-1"}, "recursion_limit": 30}
app.invoke(inputs, config=config)
```

---

## thread_id = 数据库主键

| 行为              | 含义                       | 类比               |
| ----------------- | -------------------------- | ------------------ |
| 同 thread_id 二次 invoke | 续接(从历史 state 接着跑) | UPDATE             |
| 不同 thread_id    | 全新会话                   | INSERT             |
| 漏写 thread_id    | **直接报错**(LangGraph 1.x)| —                  |

### LangGraph 1.x 的硬性要求

漏传 `configurable` 直接抛:

```
ValueError: Checkpointer requires one or more of the following 'configurable' keys:
thread_id, checkpoint_ns, checkpoint_id
```

跟 0.x 不同(0.x 静默用匿名 thread)。从 0.x 升级时这是常见踩坑点。

---

## 续接 = reducer 重新跑

第 2 次 invoke **不要**塞完整 init_state,只塞**增量**:

```python
# ❌ 错误:重塞 system + user(会污染历史)
app.invoke(
    {"messages": [
        {"role": "system", "content": SYSTEM_PROMPT},   # ← 这条会被追加到历史末尾!
        {"role": "user", "content": "新问题"},
    ]},
    config=config,
)

# ✅ 正确:只塞差分
app.invoke(
    {"messages": [HumanMessage(content="新问题")]},
    config=config,
)
```

LangGraph 会:
1. 从 checkpointer 读出该 thread_id 的最新 state
2. 把你这次的 input 当成"node 返回值",**用 reducer 合并**
3. `add_messages` 把新消息追加到历史尾部

**reducer 字段(`Annotated[..., reducer]`)的关键特性**:不传**不会清零**,会从快照读旧值再 +增量。普通字段(没加 Annotated)才会被新 input 覆盖丢失。

---

## Day 2 → Day 3 思维迁移

| 时代          | invoke 写法                 | 原因                            |
| ------------- | --------------------------- | ------------------------------- |
| Day 2(无 checkpointer) | 每次塞完整 init_state(system+user 全套) | 没有持久化,不塞就什么都没有     |
| Day 3(有 checkpointer) | 只塞差分(新增 user 一条)   | 历史在 checkpoint 里,塞了会重复 |

**两个时代的调用约定完全相反,迁移代码不能简单复制粘贴**。

---

## MemorySaver vs SqliteSaver

| 项                | MemorySaver         | SqliteSaver                                   |
| ----------------- | ------------------- | --------------------------------------------- |
| 存储              | 进程内 dict         | 本地 sqlite 文件                              |
| 进程退出          | **数据全丢**        | 数据保留                                      |
| API 形态          | `MemorySaver()`     | `SqliteSaver.from_conn_string("path")` (上下文管理器) |
| 适用              | 单进程开发 / 测试   | 单机生产 / 调试                               |
| 多进程并发        | 不行                | 行(sqlite 自带 wal)                         |
| 远程 / 分布式     | 不行                | 不行(用 PostgresSaver 才行)                 |

### SqliteSaver 的"必须用 with"陷阱

LangGraph 1.x 的 `SqliteSaver.from_conn_string` 是**上下文管理器**,不能裸用:

```python
# ❌ 会报错:连接没建立
checkpointer = SqliteSaver.from_conn_string("ckpt.sqlite")
app = graph.compile(checkpointer=checkpointer)

# ✅ 必须 with
with SqliteSaver.from_conn_string("ckpt.sqlite") as checkpointer:
    app = graph.compile(checkpointer=checkpointer)
    # ... 实验都要写在 with 块里 ...
```

跟 0.x 不一样,从 0.x 抄代码会踩。

---

## 3 个高频坑

| #   | 现象                                                  | 根因                                       | 修复                       |
| --- | ----------------------------------------------------- | ------------------------------------------ | -------------------------- |
| 1   | 第 2 次 invoke 报 `MissingThreadId`                   | 漏传 `configurable.thread_id`              | invoke 必须带 config       |
| 2   | 第 2 次 invoke 后 messages 里多了一条 system          | input 重塞了 system,reducer 无脑追加     | 只塞差分                   |
| 3   | 进程重启后 `app.get_state(config)` 是空的             | MemorySaver 是进程内 dict,退出就消失      | 切 SqliteSaver             |

---

---

## 抽象破裂场景 4 例(happy path 之外的 1%)

LangGraph + checkpointer 的设计哲学:**99% 情况下用户不用关心底层**,你写续接代码就一行 `app.invoke({"messages": [HumanMessage(...)]}, config=config)`,框架自动处理 state 加载 / reducer 合并 / checkpoint 落盘 / thread 隔离 —— **跟 git commit 一样,你不用管 SHA、索引、blob 怎么存**。

但抽象的代价是:**出问题时,你必须知道底层在做什么才能 debug**。下面 4 种场景是抽象破裂的常见入口:

### 场景 ① · graph 结构改了再 resume

| 现象     | resume 后 KeyError、行为诡异、state 字段缺失           |
| -------- | ------------------------------------------------------ |
| 根因     | checkpoint 里的 state schema 跟新 graph 不匹配         |
| 诊断     | `app.get_state(config).values` 看字段是否符合新 schema |
| 应对     | 删 sqlite 文件 / 换 thread_id / 抽 `build_graph()` 工厂函数让两份代码物理共享 graph 定义 |

### 场景 ② · MemorySaver 在多进程下并发

| 现象     | 进程 A 写的 state,进程 B 读不到                        |
| -------- | ------------------------------------------------------ |
| 根因     | MemorySaver 是进程内 dict,各进程内存独立               |
| 诊断     | `type(checkpointer)` 看是不是 MemorySaver              |
| 应对     | 切 SqliteSaver(单机)或 PostgresSaver(分布式)        |

### 场景 ③ · 第 2 次 invoke 重塞了 system

| 现象     | 续接后 messages 中途冒出一条 system message,LLM 行为怪异 |
| -------- | -------------------------------------------------------- |
| 根因     | `add_messages` reducer 不去重,无脑追加 |
| 诊断     | `app.get_state(config).values["messages"]` 翻一遍看有没有重复 system |
| 应对     | 续接只塞差分(只塞新 user 消息),不要重塞 system           |

### 场景 ④ · thread_id 拼错或漂移

| 现象     | 续接后变成"全新对话",历史完全没了                       |
| -------- | -------------------------------------------------------- |
| 根因     | `yzb` vs `yzb-1` vs `yzb_1` 拼错,默默开了新会话         |
| 诊断     | `list(app.get_state_history(config))` 长度=1 → 全新会话  |
| 应对     | 用工厂函数集中管理 config:`make_config(thread_id="yzb")` |

---

## 抽象的好处 vs 代价(同一枚硬币)

| 维度        | 好处                                       | 代价                                       |
| ----------- | ------------------------------------------ | ------------------------------------------ |
| Happy path  | 一行 invoke 搞定续接,认知成本几乎为零      | —                                          |
| 调试        | —                                          | 必须懂底层(reducer / checkpoint / metadata) |
| 学习曲线    | 上手 5 分钟                                 | 精通 5 周(Week 5 工程化时才会真正用透)    |
| 跟裸 while 比 | 跨进程续接 / 时间旅行 / 多线程隔离 全送    | 不需要这些能力时显得"过度工程"             |

**判断"是否该用 LangGraph"的标准**:你的 agent 是否需要跨 invoke 持久化、是否需要中断恢复、是否需要审计追溯?**任何一个 yes,框架成本就回本了**。三个全 no 的场景(一次性脚本 / 简单 chatbot)裸循环够用。

---

## 相关知识

- [thread 隔离的"假象续接"陷阱](checkpointer-thread-isolation.md) — 同进程不同 thread_id 怎么验证真的隔离
- [add_messages reducer 的 4 种输入隐式转换](add-messages-reducer-quirks.md) — 裸字符串会被降级成 HumanMessage
- [LangGraph state 观察的 3 种 API](langgraph-state-inspection.md) — get_state / get_state_history / stream
- [LangGraph SqliteSaver 内部机制](langgraph-sqlite-internals.md) — checkpoints / writes 两表 schema、UUIDv6、branch:to:* 路由信号、Git 类比、debug 实战
