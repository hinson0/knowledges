# LangGraph State 观察:get_state / get_state_history / stream

> 来源:Week 2 · Day 3 实验 C/D + metadata 字段踩坑
> 关键词:`get_state` / `get_state_history` / `stream` / `StateSnapshot` / `next` / `metadata`

---

## 一句话总结

**LangGraph 1.x 把"状态观察"切成两个平面:控制平面靠 `get_state` / `get_state_history`(可重放、时间旅行),数据平面靠 `app.stream(stream_mode=...)`(实时观察哪个 node 写了啥)。**

---

## 三种 API 对比

| API                              | 返回类型                  | 时机                | 适用场景                          |
| -------------------------------- | ------------------------- | ------------------- | --------------------------------- |
| `app.get_state(config)`          | `StateSnapshot`           | 跑完后随时          | 续聊取上下文、查最新 state        |
| `app.get_state_history(config)`  | `Iterator[StateSnapshot]` | 跑完后随时          | 时间旅行、调试、审计、fork         |
| `app.stream(input, config, ...)` | 生成器(实时 yield)       | invoke 期间         | 实时观察每步、UI 流式更新、埋点    |

---

## StateSnapshot 关键字段

```python
snap = app.get_state(config)

snap.values        # dict — state 内容,如 {"messages": [...], "iter_count": 4}
snap.next          # tuple — 下一个要跑的 node,() 表示已 END
snap.config        # dict — 这个快照的 config(含 checkpoint_id)
snap.metadata      # dict — 元数据(见下文)
```

### `.metadata` 在 LangGraph 1.x 简化了

LangGraph 1.x 实测打印出来:

```python
{"source": "loop", "step": 7, "parents": {}}
```

**只有 3 个字段**:`source` / `step` / `parents`。**没有** `writes` 字段(这是 0.x 的)。

旧文档/教程里的 `metadata.writes` 已经不存在,如果要"哪个 node 写了什么",**改用 `app.stream(stream_mode="updates")`**(下面会讲)。

`source` 取值:

| 值       | 含义                            |
| -------- | ------------------------------- |
| `"input"` | 初始空快照(step=-1)            |
| `"loop"` | 框架自己生成的合并点             |
| `"update"`| 通过 `app.update_state()` 手动改的 |
| `"fork"` | 时间旅行的 fork 起点             |

---

## `next` 字段:被严重低估的核心

### 它不止是"下一步要跑啥"

`next` 是 **LangGraph 持久化引擎决定 resume 行为的依据**。当你 fork 或 resume 一个 checkpoint,框架就是看 `next` 决定从哪里继续。

| `next` 值              | 含义                              |
| ---------------------- | --------------------------------- |
| `('__start__',)`       | 还没跑                            |
| `('llm',)`             | 下一步要跑 llm 节点                |
| `('tools',)`           | 下一步要跑 tools 节点              |
| `('human_review',)`    | 中断在 HITL 节点(Day 5 周末用到) |
| `()` 空 tuple          | 已 END                            |

### 通过 `next` 反推"上一步是谁跑的"

LangGraph 1.x 的 metadata 不直接告诉你这一步是谁写的,但 `next` 字段配合 history 可以倒推:

| `history[i].next`    | 含义                    | 所以 `history[i-1]` 是… |
| -------------------- | ----------------------- | ----------------------- |
| `('__start__',)`     | 还没跑                  | (没有上一步)            |
| `('llm',)`           | 下一步要跑 llm          | tools 刚跑完(或 START)|
| `('tools',)`         | 下一步要跑 tools        | llm 刚跑完              |
| `()` 空 tuple        | 已 END                  | llm 给出 final answer   |

---

## get_state_history 的特点

```python
history = list(app.get_state_history(config))
print(f"快照总数: {len(history)}")
# 通常 ≈ super_steps + 2(start 算一份,end 算一份)
```

**关键性质**:

1. **倒序**:`history[0]` 是最新,`history[-1]` 是最早(跟 git log 一样)
2. `history[-1]` 通常是空快照(`messages=[]`, `step=-1`)— 等价于 git 的 root commit
3. `app.get_state(config) == history[0]`(完全相同的 StateSnapshot)
4. `messages` 数和 `iter_count` 在历史中**单调递增**(reducer 是只追加,checkpoint 不可变)

### 时间旅行示例

```python
# 选中 step=4 那个快照,从那里 fork 重新跑
target = next(s for s in history if s.metadata.get("step") == 4)
fork_config = target.config   # 含 checkpoint_id

# 真要 fork,传 None 表示"不加新输入,从这个点重新跑"
app.invoke(None, config=fork_config)
```

---

## stream:观察"哪个 node 写了什么"的正解

LangGraph 1.x 把这个能力从 `metadata.writes` 挪到了 stream API:

```python
for chunk in app.stream(init_state, config=config, stream_mode="updates"):
    # chunk 形如 {"node_name": {字段: 增量值}}
    for node_name, patch in chunk.items():
        msgs_delta = len(patch.get("messages", []))
        iter_delta = patch.get("iter_count", 0)
        print(f"  [{node_name}] +{msgs_delta} msgs, +{iter_delta} iter")
```

期望输出:

```
[__start__] +2 msgs, +0 iter
[llm]       +1 msgs, +1 iter
[tools]     +1 msgs, +0 iter
[llm]       +1 msgs, +1 iter
[tools]     +1 msgs, +0 iter
[llm]       +1 msgs, +1 iter   # 最后一次,带 final answer
```

### stream_mode 的 4 种模式

| mode       | 每次 yield 啥                              | 适用                              |
| ---------- | ------------------------------------------ | --------------------------------- |
| `"updates"` | `{node_name: 该 node 的 return}`(增量)   | 调试、看是谁写了什么              |
| `"values"` | 每步后的完整 state                          | 实时同步整个 state 给 UI          |
| `"messages"` | LLM 流式 token + tool 调用                | 实时聊天 UI                       |
| `"debug"` | 最详细的内部事件                             | 工程化埋点(Langfuse 用这个)     |

---

## 控制平面 vs 数据平面

LangGraph 1.x 的 API 设计哲学:

| 平面         | API                              | 拿到啥             | 比喻               |
| ------------ | -------------------------------- | ------------------ | ------------------ |
| **控制平面** | `get_state` / `get_state_history` | 框架级最小信息(source/step/parents) + values | git log / git show |
| **数据平面** | `app.stream(stream_mode=...)`    | 业务级实时增量     | tail -f log        |

**为什么这么拆**:控制平面要快、要稳、要持久化(每个 super-step 都落盘),所以 metadata 越精简越好;数据平面要详细、要实时,但不需要持久化,挪到 stream 里就没存储压力。

---

## 工程化建议

| 场景                  | 用什么                                    |
| --------------------- | ----------------------------------------- |
| 续聊取上下文          | `get_state(config).values["messages"]`   |
| 调试某次 invoke       | `get_state_history(config)` + 翻历史      |
| Langfuse 埋点         | `stream(stream_mode="debug")`             |
| 实时 UI 流式输出      | `stream(stream_mode="messages")`          |
| HITL 中断 + 等用户确认 | 看 `next` 是否停在你的 review 节点        |
| 时间旅行 / fork       | `history` 里挑快照 + `app.invoke(None, config=snap.config)` |

---

## 相关知识

- [LangGraph Checkpointer 持久化基础](langgraph-checkpointer-basics.md) — checkpointer 是这套观察 API 的底座
- [thread 隔离的"假象续接"陷阱](checkpointer-thread-isolation.md) — 用 get_state_history 验证隔离的具体做法
- [LangGraph SqliteSaver 内部机制](langgraph-sqlite-internals.md) — 这套 API 在 sqlite 层是怎么实现的,以及如何用 SQL 直查诊断
