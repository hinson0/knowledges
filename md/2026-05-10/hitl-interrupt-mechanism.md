# HITL 机制本身 —— `interrupt()` + `Command(resume=...)` 最小骨架

> 把 day4 复杂度剥到只剩机制,不掺工具协议、路由分支、reject 这些。

## 一句话本质

`interrupt(payload)` 是节点函数内部的 **yield 点**:把 payload 抛给宿主,把当前 checkpoint 冻在那一行,**节点函数没 return**。宿主用 `Command(resume=value)` 续跑 graph 时,`interrupt()` 调用的返回值就是那个 `value`,节点从 yield 点之后接着跑。

## 心智模型

```
节点函数 human_review(state):
    a = state["x"]              ← (1) "已发生"
    user_in = interrupt(payload) ← (2) yield 点 — 第 1 次 invoke 跑到这冻住,函数没 return
                                 ← Command(resume=v) 来后,user_in == v,继续往下
    return {"y": user_in}        ← (3) 第 2 次 invoke 才执行
```

关键直觉:

- `interrupt()` **不是**节点的"出口动作",是节点**内部**的暂停点
- 第一次 invoke 跑到 (2) 时,函数对外没 return —— LangGraph runtime 在 stream 里抛出 `__interrupt__` chunk
- 第二次 `Command(resume=v)` 来时,**前面 (1) 不会重跑**(LangGraph 1.x 行为),从 (2) 之后接着跑

## 必备前置

- `app.compile(checkpointer=<Saver>)` —— 没有 checkpointer,interrupt 没地方冻 state,直接报错
- `config = {"configurable": {"thread_id": ...}}` —— 同一 thread 才能续

## 最小可跑 demo(35 行)

```python
from typing import TypedDict
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import START, END, StateGraph
from langgraph.types import Command, interrupt


class State(TypedDict):
    number: int
    name: str


def human_name(state: State) -> dict:
    n = state["number"]
    user_in = interrupt({"prompt": f"给 {n} 取名", "number": n})
    return {"name": user_in}


g = StateGraph(State)
g.add_node("review", human_name)
g.add_edge(START, "review")
g.add_edge("review", END)
app = g.compile(checkpointer=InMemorySaver())

config = {"configurable": {"thread_id": "t1"}}

# 阶段 1:跑到 interrupt 冻住
for chunk in app.stream({"number": 42, "name": ""}, config, stream_mode="updates"):
    print(chunk)
# → {'__interrupt__': (Interrupt(value={'prompt': '给 42 取名', 'number': 42}, ...),)}

# 拿 payload
snap = app.get_state(config)
payload = snap.tasks[0].interrupts[0].value

# 阶段 2:resume 续跑
for chunk in app.stream(Command(resume="终极答案"), config, stream_mode="updates"):
    print(chunk)
# → {'review': {'name': '终极答案'}}
```

## payload / resume schema 由你定

LangGraph **不解释** `interrupt()` 抛出的 payload,也不解释 `Command(resume=...)` 收到的 value。两端的 schema 是你和宿主之间的契约:

| 场景 | payload(发) | resume(收) |
|---|---|---|
| 简单命名 | `str` | `str` |
| 工具审批 | `{"tool_calls": [...], "preview": ...}` | `{"action": "approve"\|"reject", "reason": str}` |
| 多选 | `{"options": [...]}` | `{"choice_idx": int}` |

实践:**payload 一定塞预览**(diff / 文件前几行 / 命令全文),让用户知道"接受会发生什么"。

## stream chunk 里识别中断的 key

```python
for chunk in app.stream(...):
    if "__interrupt__" in chunk:
        interrupts = chunk["__interrupt__"]   # tuple[Interrupt, ...]
        payload = interrupts[0].value
        break
```

这个 key 是 LangGraph runtime 注入的元事件,不是 state 字段。

## 易混淆

- **节点已经 return 后**还能 interrupt 吗?不能。interrupt 是节点函数体里的同步调用,return 之后函数已退出。
- **graph END 后再 resume**?报错 / 被忽略 —— 没有"冻住的 checkpoint"可以续。
- **同一 thread 中断点 resume 两次**?第一次成功;第二次没有 pending interrupt,行为 = 普通 invoke。

---

## 完整版 minimal demo:猜数字命名

> 来源:week2/0510/1139.md。比上面 35 行版多一个产数节点 + 一个 finalize 节点,展示"interrupt 在 graph 中段"的完整流程。

场景:节点 A 给一个随机数,interrupt 出去问"叫它啥名",节点 B 把名字落进 state。**没有 LLM、没有工具、没有路由分支** —— 就这点东西。

```python
# %% imports
import random
from typing import Annotated, TypedDict

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import START, END, StateGraph
from langgraph.types import Command, interrupt


# %% State schema
class State(TypedDict):
    """
    最小 demo 的状态。

    Schema:
        number: 节点 A 生成的随机数
        name:   人工命名后的字符串
    """
    number: int
    name: str


# %% 节点 A:产数
def gen_number(state: State) -> dict:
    """生成一个随机数,写进 state.number。"""
    n = random.randint(1, 100)
    print(f"[gen_number] 生成数字 {n}")
    return {"number": n}


# %% 节点 review:中断,等用户给名字
def human_name(state: State) -> dict:
    """
    HITL 节点:把当前数字抛给宿主,等宿主用 Command(resume=...) 给名字。

    Schema:
        payload(发出去): {"prompt": str, "number": int}
        resume_value(收回来): str  ← 用户输入的名字
    """
    # 1. 这一行之前的代码"已发生"
    number = state["number"]

    # 2. 这一行是 yield 点 —— 把 payload 交给宿主,冻结 checkpoint
    user_input = interrupt({
        "prompt": f"请给数字 {number} 取个名字",
        "number": number,
    })

    # 3. 宿主 Command(resume=...) 回来后,user_input == 那个 resume value
    print(f"[human_name] 用户回了: {user_input!r}")
    return {"name": user_input}


# %% 节点 B:落盘
def finalize(state: State) -> dict:
    """打印最终结果。"""
    print(f"[finalize] {state['number']} 的名字是 {state['name']!r}")
    return {}


# %% 拼图
def build():
    g = StateGraph(State)
    g.add_node("gen", gen_number)
    g.add_node("review", human_name)
    g.add_node("finalize", finalize)
    g.add_edge(START, "gen")
    g.add_edge("gen", "review")
    g.add_edge("review", "finalize")
    g.add_edge("finalize", END)
    # checkpointer 必须有 —— interrupt 靠它冻 state
    return g.compile(checkpointer=InMemorySaver())


# %% 跑
if __name__ == "__main__":
    app = build()
    config = {"configurable": {"thread_id": "demo-1"}}

    # 第一次 invoke:从 START 跑到 interrupt 处冻住
    print("=== 第 1 次调用(跑到中断)===")
    for chunk in app.stream({}, config, stream_mode="updates"):
        print(f"  chunk: {chunk}")

    # 此时 graph 暂停在 review 节点的 interrupt() 处
    # 看一下 snap
    snap = app.get_state(config)
    print(f"\n[snap] next={snap.next}")  # → ('review',)
    print(f"[snap] interrupts={snap.tasks[0].interrupts}\n")

    # 拿到 payload(就是 interrupt() 里传的 dict)
    payload = snap.tasks[0].interrupts[0].value
    print(f"[宿主] graph 让我回答: {payload['prompt']}")

    # 模拟用户输入
    user_answer = "幸运数字"

    # 第二次 invoke:用 Command(resume=...) 续跑
    print("\n=== 第 2 次调用(续跑)===")
    for chunk in app.stream(Command(resume=user_answer), config, stream_mode="updates"):
        print(f"  chunk: {chunk}")

    final = app.get_state(config).values
    print(f"\n[最终 state] {final}")
```

### 跑出来的样子

```
=== 第 1 次调用(跑到中断)===
[gen_number] 生成数字 73
  chunk: {'gen': {'number': 73}}
  chunk: {'__interrupt__': (Interrupt(value={'prompt': '请给数字 73 取个名字', 'number': 73}, ...),)}

[snap] next=('review',)
[snap] interrupts=(Interrupt(value={'prompt': '请给数字 73 取个名字', 'number': 73}, ...),)

[宿主] graph 让我回答: 请给数字 73 取个名字

=== 第 2 次调用(续跑)===
[human_name] 用户回了: '幸运数字'
  chunk: {'review': {'name': '幸运数字'}}
[finalize] 73 的名字是 '幸运数字'
  chunk: {'finalize': {}}

[最终 state] {'number': 73, 'name': '幸运数字'}
```

## 三个看清楚的点

**① `interrupt()` 是 yield,不是 return**

看 `human_name` 的 print:`[gen_number]` 之后**没有立刻**出现 `[human_name] 用户回了: ...`。第一次 invoke 时 `human_name` 跑到 `interrupt()` 就冻住了,**`print(f"[human_name] ...")` 那一行根本没执行**。直到 Command(resume=...) 回来才执行。

**② chunk 里的 `__interrupt__` 是 LangGraph 给宿主的"我冻住了"信号**

day4 写的 `stream_until_interrupt` 检测的就是这个 key。这个信号不是 state 的一部分,是 stream 的元事件。

**③ resume 时 `Command(resume=value)` 的 value 类型由你决定**

这里传了 str,day4 里传的是 dict(`{"action": "approve"|"reject", "reason": ...}`)。LangGraph 不解释这个 value,它只是把它当作 `interrupt()` 的返回值塞回去。**所以 payload 和 resume 的 schema 完全是你自己设计的契约**,跟 LangGraph 框架无关。

## 跟 day4 的对照

| 维度 | 这个 demo | day4_hitl.py |
|---|---|---|
| 触发条件 | 节点里直接 `interrupt()` | should_continue 路由到 human_review,human_review 里 `interrupt()` |
| payload | `{"prompt", "number"}` | `{"tool_calls": [...], "reasoning": ...}` |
| resume value | `str`(名字) | `{"action": "approve"\|"reject", "reason": ...}` |
| 后续路由 | 固定 → finalize | 条件 → tools(approve)/llm(reject) |
| reject 协议 | 不存在 | ToolMessage with tool_call_id(OpenAI 协议要求) |

**day4 复杂度的本质 = 这个 demo + 工具协议 + 条件路由**。HITL 机制本身就这么点东西。

## 下一步实验建议(reroll)

跑通后做一个小实验:

> 把 `human_name` 节点改成"如果用户回 'reroll',就抛出 raise GraphRecursionError 之类强制重来,否则正常 return"。看看怎么把"用户的拒绝"映射成"图的某种重跑"。

这个实验直接对应 day4 的 reject 路径设计,但**没有协议干扰**。跑通后再回头看 day4,会发现"reject → ToolMessage → 重跑 LLM"只是这个范式 + OpenAI 的协议补丁。

## 关联

- `StateSnapshot-schema.md` — `snap.tasks[0].interrupts` 字段路径来源
- `langgraph-stream-chunks.md` — `__interrupt__` chunk 的完整形态
- `langgraph-state-vs-control-flow.md` — interrupt 跟 return 的边界差异
- `hitl-design-protocol.md` — 在这个机制上叠加工具协议 + reject 路由的设计推理
- `dangerous-op-gating.md` — 把 HITL 用在破坏性操作 gating 上的范式
- `~/ai_agent_learning/week2/day4_hitl.py` — 真实工程实现
