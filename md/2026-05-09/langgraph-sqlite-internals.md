# LangGraph SqliteSaver 内部机制 · 完整解析

> 来源:Week 2 · Day 3 · SqliteSaver 实战之后的深度调研
> 关键词:`checkpoints` 表 / `writes` 表 / UUIDv6 / `branch:to:*` / time-travel / 心智模型 = Git

---

## 一句话总结

**LangGraph SqliteSaver 的持久化模型 = Git 的对象数据库:`checkpoints` 像 commit、`writes` 像 staged diff、`parent_checkpoint_id` 像父 commit、UUIDv6 让"字符串排序 = 时间排序",fork / time-travel 都是从 commit 链上挑一个点重新分叉。**

---

## 一、整体架构:两张表干两件事

LangGraph 的 SQLite checkpointer 用**两张表**存储所有持久化数据:

| 表名          | 角色                                       | 类比 Git                |
| ------------- | ------------------------------------------ | ----------------------- |
| `checkpoints` | 存"全量状态快照"——某一时刻整个图的完整状态 | `commit`(一次提交)    |
| `writes`      | 存"增量写入记录"——每个节点产出的具体修改   | `diff` / staged changes |

它们的关系:**一个 checkpoint(快照)对应多行 writes(写入)**,逻辑上是 `1 : N`。

---

## 二、`checkpoints` 表

### 字段结构

```sql
CREATE TABLE checkpoints (
    thread_id            TEXT NOT NULL,
    checkpoint_ns        TEXT NOT NULL DEFAULT '',
    checkpoint_id        TEXT NOT NULL,
    parent_checkpoint_id TEXT,
    type                 TEXT,
    checkpoint           BLOB,
    metadata             BLOB,
    PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id)
);
```

### 字段逐个说明

| 字段                   | 含义                                                            |
| ---------------------- | --------------------------------------------------------------- |
| `thread_id`            | 会话 ID,一次完整的对话 / 任务流程                                |
| `checkpoint_ns`        | 命名空间,主图为 `''`,子图(subgraph)用它隔离状态                |
| `checkpoint_id`        | 快照唯一 ID,**UUIDv6 风格**,前缀编码时间戳,**天然按时间有序** |
| `parent_checkpoint_id` | 父快照 ID,形成单向链表;**为空表示这是第一个快照**              |
| `type`                 | `checkpoint` 字段的序列化格式(通常是 `msgpack`)                |
| `checkpoint`           | 核心数据:整个图状态的二进制序列化结果                          |
| `metadata`             | 元数据:`source`、`step`、`parents` 等                          |

### checkpoint 字段(BLOB)解码后的结构

```python
{
    "v": 4,                          # schema 版本号
    "ts": "2026-05-09T07:09:47...",  # 时间戳
    "id": "1f14b760-...581c",
    "channel_values": {              # 各 channel 当前值
        "messages": [SystemMessage(...), HumanMessage(...)],
        "iter_count": 0,
        ...
    },
    "channel_versions": {...},       # 每个 channel 的版本号
    "versions_seen": {...}           # 各节点已见过的 channel 版本(用于触发判断)
}
```

### metadata 字段说明

```json
{ "source": "input", "step": -1, "parents": {} }
```

| 字段      | 取值                                 | 含义                                  |
| --------- | ------------------------------------ | ------------------------------------- |
| `source`  | `input` / `loop` / `update` / `fork` | 这个快照怎么产生的                    |
| `step`    | `-1, 0, 1, 2, ...`                   | 执行步数,**`-1` 是约定的"初始化"步** |
| `parents` | dict                                 | 父命名空间映射,主图为 `{}`            |

`source` 取值含义:

- `input` — 用户输入触发(初始快照)
- `loop` — 图执行循环中产生(节点执行后的快照)
- `update` — 手动 `update_state()` 产生
- `fork` — 分支产生

---

## 三、`writes` 表

### 字段结构

```sql
CREATE TABLE writes (
    thread_id     TEXT NOT NULL,
    checkpoint_ns TEXT NOT NULL DEFAULT '',
    checkpoint_id TEXT NOT NULL,
    task_id       TEXT NOT NULL,
    idx           INTEGER NOT NULL,
    channel       TEXT NOT NULL,
    type          TEXT,
    value         BLOB,
    PRIMARY KEY (thread_id, checkpoint_ns, checkpoint_id, task_id, idx)
);
```

### 字段逐个说明

| 字段            | 含义                                                      |
| --------------- | --------------------------------------------------------- |
| `thread_id`     | 会话 ID(同 checkpoints)                                  |
| `checkpoint_ns` | 命名空间(同 checkpoints)                                 |
| `checkpoint_id` | **属于哪个快照** —— 与 checkpoints 表的逻辑外键           |
| `task_id`       | 任务 ID,标识"是哪个节点这次执行写的"                      |
| `idx`           | 写入序号,同一 task 的多次写入按 idx 排序                  |
| `channel`       | 状态通道名(`messages`、`iter_count`、`branch:to:xxx` 等) |
| `type`          | value 的序列化格式                                        |
| `value`         | 实际写入的内容(二进制)                                  |

### 主键设计的层级

```
thread_id              (哪次会话)
  └─ checkpoint_ns     (主图 or 子图)
       └─ checkpoint_id (哪个快照)
            └─ task_id  (哪个节点任务)
                 └─ idx (这个任务的第几次写入)
```

### 特殊 channel:`branch:to:*`

LangGraph 内部约定的**路由信号**:

- `branch:to:llm` — 下一步去 `llm` 节点
- `branch:to:tools` — 下一步去 `tools` 节点
- **没有 `branch:to:*` 写入 → 走向 END**

`type` 通常是 `null`,`value` 也为空 —— 写入这个 channel 这个动作本身就是信号。

---

## 四、两张表的关系

### 逻辑外键(SQLite 没强制声明)

```
writes.(thread_id, checkpoint_ns, checkpoint_id)
  →  checkpoints.(thread_id, checkpoint_ns, checkpoint_id)
```

**关系:1 : N** — 一个 checkpoint 对应多行 writes(每个节点写多个 channel)。

### 两条"链"

LangGraph 用两条链组织数据:

1. **快照链(checkpoints 内部)** — `parent_checkpoint_id` 形成单向链表,从最新快照可追溯到创世快照,**这是 time-travel 的基础**
2. **写入链(writes 内部)** — 同一 task 的写入按 `idx` 排序,保证状态精确顺序回放

---

## 五、UUIDv6 的妙处

`checkpoint_id` 用的是 **UUIDv6**(不是 UUIDv4):

- **前缀编码时间戳** → 字符串排序 = 时间排序
- `ORDER BY checkpoint_id` 直接得到执行顺序
- 不需要额外的 `created_at` 字段或解析 metadata
- `1f14b760-...` → `1f14b761-...` 表示更新的快照

这是为什么 LangGraph 选 UUIDv6 的核心原因。

---

## 六、典型执行流程示例

以 ReAct Agent 读文件并回答为例,完整执行流程:

### 时间线

| step | source | 写入的 channels                             | 含义                                          |
| ---- | ------ | ------------------------------------------- | --------------------------------------------- |
| -1   | input  | `messages`, `iter_count`, `branch:to:llm`   | 创世快照,登记用户输入,准备进 LLM            |
| 0    | loop   | `messages`, `iter_count`, `branch:to:tools` | LLM 第一次调用,决定调工具                    |
| 1    | loop   | `messages`, `branch:to:llm`                 | 工具执行,读文件,回到 LLM                    |
| 2    | loop   | `messages`, `iter_count`                    | LLM 第二次调用,直接回答(**无路由 = 走 END**)|
| 3    | loop   | (空)                                        | 终结快照,标记运行完成                         |

### 路径

```
START → llm → tools → llm → END
```

### 关键观察

- `iter_count` 只在 LLM 节点更新(限制 LLM 调用次数的设计)
- 工具节点不更新计数器
- step 2 没写 `branch:to:*` → 框架走 END
- step 3 是空 checkpoint,相当于 git 的 HEAD 标记

---

## 七、实用 SQL 查询模板

### 7.1 看一次会话的全部 checkpoint

```sql
SELECT
    json_extract(metadata, '$.step') AS step,
    json_extract(metadata, '$.source') AS source,
    substr(checkpoint_id, 1, 8) AS cp,
    substr(parent_checkpoint_id, 1, 8) AS parent
FROM checkpoints
WHERE thread_id = 'yzb'
ORDER BY checkpoint_id;
```

### 7.2 JOIN 出每一步的全部 writes

```sql
SELECT
    json_extract(c.metadata, '$.step') AS step,
    json_extract(c.metadata, '$.source') AS source,
    w.idx,
    w.channel,
    w.type
FROM checkpoints c
LEFT JOIN writes w
    ON c.thread_id = w.thread_id
   AND c.checkpoint_ns = w.checkpoint_ns
   AND c.checkpoint_id = w.checkpoint_id
WHERE c.thread_id = 'yzb'
ORDER BY c.checkpoint_id, w.idx;
```

### 7.3 路由审计(只看 Agent 怎么走)

```sql
SELECT
    json_extract(c.metadata, '$.step') AS step,
    COALESCE(
        (SELECT w.channel
         FROM writes w
         WHERE w.thread_id = c.thread_id
           AND w.checkpoint_id = c.checkpoint_id
           AND w.channel LIKE 'branch:to:%'
         LIMIT 1),
        '→ END'
    ) AS route
FROM checkpoints c
WHERE c.thread_id = 'yzb'
ORDER BY c.checkpoint_id;
```

### 7.4 反序列化 BLOB 看实际内容

```python
import sqlite3
from langgraph.checkpoint.sqlite import SqliteSaver

# 推荐方式:用 LangGraph 自带的 API
saver = SqliteSaver.from_conn_string("checkpoint.db")
config = {"configurable": {"thread_id": "yzb"}}

# 看最新状态
state = saver.get(config)
print(state)

# 看历史所有快照(完整执行轨迹)
for snapshot in saver.list(config):
    print(snapshot.metadata, snapshot.values)
```

---

## 八、生产环境 debug 实战

### 场景 1:Agent 死循环

**症状**:路由序列反复来回:

```
0  branch:to:llm
1  branch:to:tools
2  branch:to:llm
3  branch:to:tools
... 一直循环
```

**排查**:LLM 反复调工具停不下来,检查:

- 系统提示词是否明确"得到结果后直接回答"
- 是否设置了 `recursion_limit` 或自定义迭代上限
- 工具返回值是否真的能让 LLM 满意

### 场景 2:Agent 提前退出

**症状**:第一步就走 END:

```
-1  branch:to:llm
 0  (空)   ← 没调工具,直接结束
```

**排查**:

- 工具 schema(description / parameters)是否清晰
- 系统提示词是否过度抑制工具调用
- LLM 是否"自信地编造"了答案

### 场景 3:路由分支跳错地方

**症状**:

```
0  branch:to:retriever   ← 期望是 tools
```

**排查**:

- `add_conditional_edges()` 的 `route_func` 函数逻辑
- 路由函数的返回值与 mapping dict 是否匹配

### 场景 4:对比好坏会话

把成功的 thread 和失败的 thread **路由序列并排对比**,差异点立刻浮现 —— 这是定位 Agent 行为问题的最快办法。

---

## 九、心智模型总结:LangGraph ≈ Git

把整套机制类比成 **Git**,理解会非常清晰:

| Git 概念              | LangGraph 对应                                                                    |
| --------------------- | --------------------------------------------------------------------------------- |
| `branch`              | `thread_id`(每个会话独立分支)                                                   |
| `submodule`           | `checkpoint_ns`(子图嵌套)                                                       |
| `commit`              | `checkpoints` 行(完整状态快照)                                                  |
| `commit hash`         | `checkpoint_id`(UUIDv6,有序)                                                     |
| `parent commit`       | `parent_checkpoint_id`(链表往前指)                                              |
| `staged diff`         | `writes` 行(节点写出的增量)                                                     |
| `git log`             | `SELECT * FROM checkpoints ORDER BY checkpoint_id`                                |
| `git checkout <hash>` | `graph.invoke(config={"configurable": {"thread_id": ..., "checkpoint_id": ...}})` |
| `git reset`           | `saver.put(...)` 覆盖最新状态                                                    |

---

## 十、进阶方向

### 10.1 断点续跑

```python
config = {"configurable": {"thread_id": "yzb"}}
# 中断后再次调用,从最新 checkpoint 接着跑
result = graph.invoke(None, config=config)
```

### 10.2 Time Travel(时间旅行)

```python
# 从某个历史 checkpoint 重新执行
config = {"configurable": {
    "thread_id": "yzb",
    "checkpoint_id": "1f14b760-...581c"  # 指定某个历史点
}}
result = graph.invoke(input_override, config=config)
# 这会创建一条"分支" — 不影响原来的快照链
```

### 10.3 修改状态后再执行

```python
# 在某个 checkpoint 处修改状态,再继续执行(常用于人在回路 HITL)
graph.update_state(config, {"messages": [HumanMessage("修正一下...")]})
graph.invoke(None, config=config)
```

### 10.4 子图与 checkpoint_ns

子图执行时,`checkpoint_ns` 不再是空字符串,而是层级路径:

```
父图:    ''
子图 A:   'subgraph_a'
子子图:   'subgraph_a:nested_b'
```

每个层级的 checkpoint 独立存储但通过 ns 关联。

### 10.5 生产级替换

`SqliteSaver` 适合本地开发,生产环境换:

| 后端            | 适用场景                        |
| --------------- | ------------------------------- |
| `PostgresSaver` | 标准生产数据库,支持并发        |
| `RedisSaver`    | 高吞吐、低延迟,适合短期会话    |
| `MongoDBSaver`  | 文档型数据,适合复杂状态        |
| 自定义           | 实现 `BaseCheckpointSaver` 接口 |

所有 saver 共享同一套 schema 抽象 —— 你掌握的 SQLite 知识可以直接平移。

---

## 速查清单

> 一图流总结:

- 📦 **`checkpoints` = 快照表**,主键 3 列,一行一个完整状态
- 📝 **`writes` = 写入表**,主键 5 列,记录每个节点每次写入
- 🔗 **快照链** 通过 `parent_checkpoint_id` 串起来
- 🆔 **UUIDv6** 让 `checkpoint_id` 字符串排序 = 时间排序
- 🎯 **`branch:to:*` channel** 是路由信号,**没写 = 走 END**
- 🔢 **`step = -1`** 是初始化,**`source = input`** 是用户输入触发
- ♻️ **空 checkpoint(无 writes)** = 终结快照
- 🪞 **整体心智模型 = Git**:thread = branch,checkpoint = commit,writes = diff

---

## 相关知识

- [LangGraph Checkpointer 持久化基础](langgraph-checkpointer-basics.md) — checkpointer 的用户层 API,本篇是它的"底层揭秘版"
- [LangGraph state 观察 API](langgraph-state-inspection.md) — `get_state` / `get_state_history` / `stream` 三种观察方式,跟本篇 SQL 查询一一对应
- [thread 隔离的"假象续接"陷阱](checkpointer-thread-isolation.md) — `thread_id` 的隔离机制
