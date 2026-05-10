# StateSnapshot — `app.get_state(config)` 返回值

> 来源:week2/0510/StateSnapshot.md。LangGraph 用 StateSnapshot 表达"checkpoint 在某个时刻的全息快照"。任何时刻调 `app.get_state(config)` 拿到的就是这个对象。

## Schema(伪 TypedDict)

```python
class StateSnapshot:
    values:         dict           # 当前 state 全量(就是你的 AgentState)
    next:           tuple[str]     # 下一个要执行的节点名
    config:         RunnableConfig # 这个 checkpoint 的标识(含 checkpoint_id)
    metadata:       dict           # {source, step, parents}
    created_at:     str            # ISO 8601 时间戳
    parent_config:  RunnableConfig # 上一个 checkpoint 的 config(链式回溯)
    tasks:          tuple          # 当前 pending 的 PregelTask(中断时用)
    interrupts:     tuple          # 当前激活的 Interrupt(HITL 时用)
```

## 字段详解

| 字段 | 类型 | 含义 / 取值场景 |
|---|---|---|
| `values` | `dict` | **state 全量**。你 AgentState 里有什么这里就有什么(`messages` / `iter_count` / 你后面加的字段)。读 `snap.values["messages"]` 看历史 |
| `next` | `tuple[str]` | **下一步要跑哪个节点**。`()` 空元组 = 已终止或全部 pending 已完成;`("tools",)` = 下一步去 tools 节点;`("__interrupt__",)` 在 1.x 已废弃,中断信号去 tasks/interrupts 字段看 |
| `config` | `RunnableConfig` | 这个快照对应的 **checkpoint 标识**。三个关键 key:`thread_id`(线程隔离)/ `checkpoint_id`(本 checkpoint UUIDv6)/ `checkpoint_ns`(子图命名空间,主图永远是 `""`) |
| `metadata.source` | `"input" \| "loop" \| "update" \| "fork"` | 这个 checkpoint 是怎么产生的:<br>• `input` = 用户首次 invoke 注入<br>• `loop` = node 正常执行后产生(最常见)<br>• `update` = 用 `app.update_state()` 手动改的<br>• `fork` = 时间旅行从某个老 checkpoint 分叉 |
| `metadata.step` | `int` | 第几步(从 -1 开始,input checkpoint 是 -1 / 0,后续递增) |
| `metadata.parents` | `dict` | 父 checkpoint 引用,**主图通常空 dict `{}`**;subgraph 里指向上层图的 checkpoint |
| `created_at` | `str` | ISO 8601 with timezone(`2026-05-09T11:57:59.345503+00:00`) |
| `parent_config` | `RunnableConfig` | 链表前驱 — 上一个 checkpoint 的 config。沿这个 next 指针反向走能拿到完整 history |
| `tasks` | `tuple[PregelTask]` | 当前**未完成**的任务。正常运行时 `()`;中断时这里有元素,每个 task 有 `.interrupts` 字段拿 payload |
| `interrupts` | `tuple[Interrupt]` | 当前**激活的**中断信号(HITL `interrupt()` 调用产生)。和 tasks 略有冗余,1.x 推荐从 `tasks[*].interrupts` 取 |

## 真实数据样本(thread=yzb,day3 跑完后)

```python
StateSnapshot(
    values={
        'messages': [
            SystemMessage(content='你是一个简洁的代码理解助手...', id='b13c3000-...'),
            HumanMessage(content='读一下 .../math_utils.py,告诉我里面有哪些函数。', id='eb465754-...'),
            AIMessage(
                content='',
                additional_kwargs={
                    'reasoning_content': '用户要求读取文件...让我先读取这个文件。'
                },
                tool_calls=[
                    {
                        'name': 'read_file',
                        'args': {'file_path': '/Users/a114514/.../math_utils.py'},
                        'id': 'call_00_IdzTI2DyPqB8PYurECdT2931',
                        'type': 'tool_call'
                    }
                ],
                invalid_tool_calls=[],
                id='edd322fe-...'
            ),
            ToolMessage(
                content='import math\n\ndef add(a, b):\n    """返回 a + b 的和"""\n    return a + b\n...',
                tool_call_id='call_00_IdzTI2DyPqB8PYurECdT2931',  # ← 跟上面 AIMessage tool_calls[0].id 配对
                id='bd3c95e3-...'
            ),
            AIMessage(
                content='文件中共定义了 **14 个函数**,如下:...',
                additional_kwargs={'reasoning_content': '文件内容已经读取完毕...'},
                tool_calls=[],          # ← 空 = 这是终结消息,没有再调工具
                invalid_tool_calls=[],
                id='07328a60-...'
            )
        ],
        'iter_count': 2                  # ← 累计 LLM 调用次数(call_llm 节点跑了 2 次)
    },
    next=(),                              # ← 空元组 = graph 已终止,没有 pending 节点
    config={
        'configurable': {
            'thread_id': 'yzb',
            'checkpoint_ns': '',
            'checkpoint_id': '1f14b9e5-2ee3-6796-8003-9634ec89b4e7'  # ← UUIDv6,字符串排序 = 时间排序
        }
    },
    metadata={
        'source': 'loop',                 # ← 这是 node 正常执行产生的 checkpoint
        'step': 3,                        # ← 第 3 步(input=-1 / 0,然后 +1+1+1)
        'parents': {}                     # ← 主图,无 parent
    },
    created_at='2026-05-09T11:57:59.345503+00:00',
    parent_config={                       # ← 上一个 checkpoint(可顺这条线回溯)
        'configurable': {
            'thread_id': 'yzb',
            'checkpoint_ns': '',
            'checkpoint_id': '1f14b9e4-cd43-6856-8002-bf595411d2fc'
        }
    },
    tasks=(),                             # ← 无未完成任务
    interrupts=()                         # ← 无激活中断
)
```

## 高频用法速查

```python
snap = app.get_state(config)

snap.values["messages"][-1]              # 最后一条消息
snap.values.get("iter_count", 0)         # 当前迭代次数(可能字段不存在)
snap.next                                # () = 完了 ; ("tools",) = 下一步去 tools
snap.metadata["source"]                  # 这个 checkpoint 怎么产生的
snap.config["configurable"]["checkpoint_id"]   # 当前 checkpoint UUID(时间旅行用)

# HITL 中断检测
if snap.next:
    for task in snap.tasks:
        if task.interrupts:              # tuple of Interrupt
            payload = task.interrupts[0].value   # 你 interrupt() 时传进去的 dict

# 历史回溯(从新到旧)
for snap in app.get_state_history(config):
    print(snap.config["configurable"]["checkpoint_id"], snap.metadata["step"])
```

## 关联

- `AIMessage-schema.md` — values.messages 里 AIMessage 类型的字段拆解
- `hitl-interrupt-mechanism.md` — `snap.tasks[0].interrupts` 字段路径来源
- `langgraph-stream-chunks.md` — `__interrupt__` chunk 的元数据来源跟 snapshot 互补
- `checkpointer-vs-store.md` — checkpoint_id 怎么落到 SQLite 表里(SqliteSaver 内部)
