# LangGraph `app.stream()` chunk schema(updates 模式)

> 来源:week2/0510/2229.md + stream_chunks.md。day4 HITL 调试时,**读 stream chunks 比加 print 更准** —— 它和 node return 是同一份数据,reducer 没消化前的样子。

## Chunk schema(updates 模式)

`stream_mode="updates"` 的 chunk 有 **3 种形态**,实际跑 day4 时按时间顺序遇到大概是这样:

```python
chunk: dict
  ├── 形态 A · 节点正常完成:    {"<node_name>": <state_delta_dict>}
  ├── 形态 B · 触发 interrupt:  {"__interrupt__": (Interrupt(...),)}
  └── 形态 C · 多节点并行(Send API):  {"<node_a>": ..., "<node_b>": ...}  # day4 不会撞到
```

## day4 happy path 的真实 chunk 序列

```python
# round 1 ─────────────────────────────────────────

# chunk 1:llm 节点跑完
{
    "llm": {
        "messages": [
            AIMessage(
                content="",
                tool_calls=[
                    {"name": "read_file",
                     "args": {"file_path": "/Users/.../math_utils.py"},
                     "id": "call_00_xxx",
                     "type": "tool_call"}
                ],
                additional_kwargs={"reasoning_content": "用户要求读取..."},
                id="edd322fe-..."
            )
        ],
        "iter_count": 1                    # ← 注意是 delta:+1,不是绝对值
    }
}

# chunk 2:human_review 节点触发 interrupt(没 yield 节点结果)
{
    "__interrupt__": (
        Interrupt(
            value={                         # ← 这就是你 interrupt(payload) 传进去的那个 dict
                "stage": "pre_tool",
                "tool_calls": [{"name": "read_file", "args": {...}}],
                "reasoning": "用户要求读取..."
            },
            resumable=True,                # ← 1.x 字段:可恢复(LangGraph 0.x 没这个)
            ns=["human_review:abc123"],    # ← namespace,subgraph 时区分多个 interrupt
            when="during",                 # ← 中断在节点执行中(还有 "before" / "after")
        ),
    )                                       # ← 注意是 tuple(可能多个 Interrupt 同时发生)
}

# 你的代码到这里就 return True, payload —— for 循环退出

# ─────── 用户输入 y,resume ─────────
# input_ = Command(resume={"action": "approve"})

# round 2 ─────────────────────────────────────────

# chunk 3:human_review 节点完成(approve 路径,空 delta)
{
    "human_review": {}                     # ← return {} 的产物,空 dict
}

# chunk 4:tools 节点跑完
{
    "tools": {
        "messages": [
            ToolMessage(
                content="import math\n\ndef add(a, b):\n    ...",
                tool_call_id="call_00_xxx",   # ← 跟前面 AIMessage.tool_calls[0].id 配对
                id="bd3c95e3-..."
            )
        ]
    }
}

# chunk 5:llm 节点跑完(终结回复)
{
    "llm": {
        "messages": [
            AIMessage(
                content="文件中共定义了 **14 个函数**,如下:...",
                tool_calls=[],                # ← 空 = 终结
                additional_kwargs={"reasoning_content": "..."},
                id="07328a60-..."
            )
        ],
        "iter_count": 1                       # ← 又一个 +1 delta(累计 = 2)
    }
}

# stream 自然结束,for 循环退出
# 你的 stream_until_interrupt return False, None
```

## reject path 的差异

reject 路径下 chunk 序列变化:

```python
# 跟 happy path 一样到 chunk 2(interrupt)

# 用户输入 r + 理由
# input_ = Command(resume={"action": "reject", "reason": "..."})

# chunk 3':human_review 这次有非空 delta(因为 reject 追加了 ToolMessage)
{
    "human_review": {
        "messages": [
            ToolMessage(
                content="[人工拒绝执行] 用户理由: ...",
                tool_call_id="call_00_xxx"
            )
        ]
    }
}

# chunk 4':llm 节点重新跑(post_review 路由回 llm)
{
    "llm": {
        "messages": [AIMessage(...)],          # ← 看完拒绝消息后的新决策
        "iter_count": 1
    }
}

# 然后 should_continue 看 last.tool_calls:
#   - 空 → 直接 END,stream 自然结束
#   - 非空 → 进入新一轮 human_review interrupt(chunk 5'... 类似 chunk 2)
```

## `Interrupt` 对象的字段

```python
class Interrupt:
    value:     Any              # 你 interrupt(payload) 传进去的东西,任意类型
    resumable: bool             # 1.x 字段:这个 interrupt 能不能 Command(resume=) 续?
    ns:        list[str]        # namespace,格式 ["<node_name>:<task_uuid>"];多 interrupt 时识别归属
    when:      "before" | "during" | "after"   # 中断发生在节点的哪个阶段(动态 interrupt 是 during)
```

## 4 种 stream_mode 的 chunk 形态对比(快速备查)

| stream_mode | 每个 chunk 的形态 | 用途 |
|---|---|---|
| `"updates"` | `{node: delta}`(只 yield 增量) | day4 在用,信息精简 |
| `"values"` | `state_全量_dict`(每步都 yield 完整 state) | 调试时看完整快照,信息冗余但直观 |
| `"messages"` | `(message_chunk, metadata)` tuple,**LLM token 流** | 实时显示 LLM 打字效果,UI 友好 |
| `"debug"` | `{type, timestamp, step, payload}` 调试事件流 | trace 调试,生产环境关闭 |

## ★ Insight

- **`{"<node>": <delta>}` 这种形态本质是 reducer 的 "输入预览"**。你在 stream chunk 里看到的 dict,跟 node 函数的 `return` 值是**同一个东西** —— LangGraph 把 node 的 return 既塞进 reducer 算 state,又转发给 stream 当 chunk。所以读懂 stream chunks = 读懂 node 在做什么的最高效路径,**比加 print 调试更准确**(print 只看你想看的字段,stream 看全)。
- **`__interrupt__` 这个特殊 key 的命名约定**:LangGraph 用双下划线前缀标记"框架自身产生的 chunk",区别于"用户节点产生的 chunk"。除了 `__interrupt__` 还有 `__start__` / `__end__`(虽然默认配置看不到)。这跟 Python `__init__` 的双下划线是同一种 "protected namespace" 约定 —— 看到 `__xxx__` 就知道是框架元数据,不是业务节点名。
- **Interrupt 的 `ns` 字段在 multi-agent / subgraph 时变得重要**。day4 是单图,`ns` 永远只有一个元素 `["human_review:xxx"]`,看不出价值。但 week5/6 你做 subgraph 嵌套(Planner subgraph 里又有 HITL),同时可能有多个 interrupt 并发触发,**靠 `ns` 区分"是 Planner 里的审批还是 Executor 里的审批"**。提前知道这个字段存在,避免 week6 撞到时一脸懵。

## 关联

- `hitl-interrupt-mechanism.md` — `__interrupt__` chunk 的产生条件和 payload 来源
- `langgraph-state-vs-control-flow.md` — 形态 A 的 delta 跟 node return 是同一份数据
- `AIMessage-schema.md` / `StateSnapshot-schema.md` — chunk 里出现的 message 对象字段拆解
