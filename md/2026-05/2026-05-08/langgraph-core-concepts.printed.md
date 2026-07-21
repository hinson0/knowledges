# LangGraph 核心概念:State / Node / Edge / Reducer

> 把手写 `run_agent` 状态机抽象到框架层,从循环思维转向图思维。

## 4 个核心概念(就 4 个)

```
┌──────────────────────────────────────────────────┐
│                                                  │
│   START ──► [Node A] ──► [Node B] ──► END        │
│                                                  │
│            ↑              ↑                      │
│            │              │                      │
│         读 State       读 State                   │
│         返回 dict      返回 dict                  │
│         (用 reducer    (用 reducer                │
│          merge 进去)    merge 进去)                │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 1. State = 全局共享的 dict

整个图运行期间有一个共享的 dict,所有 node 读它、改它。用 TypedDict 声明形状:

```python
from typing import TypedDict

class AgentState(TypedDict):
    messages: list
    counter: int
```

### 2. Node = 一个普通函数

签名固定 `(state) -> dict`,接受 state,返回"要更新的字段"(补丁,而非完整 state):

```python
def my_node(state: AgentState) -> dict:
    new_msg = call_llm(state["messages"])
    return {"messages": [new_msg]}    # ← 只返回要改的字段
```

### 3. Edge = 节点之间怎么跳

**静态边**:A 跑完一定去 B
```python
graph.add_edge("a", "b")
```

**条件边**:A 跑完看 state 决定去哪
```python
graph.add_conditional_edges("a", decide_fn, {"go_b": "b", "go_c": "c"})
# decide_fn(state) -> str,返回 key 经路由字典查到目标节点
```

**特殊节点名**:`START`(图入口)、`END`(图出口),都是 sentinel 字符串 `"__start__"` / `"__end__"`,不是真节点。

### 4. Reducer = 「补丁」怎么 merge 到 state 字段

**默认行为是覆盖**:

```python
class AgentState(TypedDict):
    messages: list   # ← 默认 reducer = 覆盖

# node 返回 {"messages": [msg_new]}
# state["messages"] 直接被替换成 [msg_new],之前的全没了!
```

**改成追加**:用 `Annotated` 给字段挂 reducer:

```python
from typing import Annotated
from langgraph.graph.message import add_messages

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]   # ← 现在是追加
```

`add_messages` 是 LangGraph 内置专给消息列表用的 reducer:不止追加,还自动处理 tool_call_id 配对、消息去重(按 id)。

## 完整最小例子(20 行)

```python
from typing import TypedDict, Annotated
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages

class State(TypedDict):
    messages: Annotated[list, add_messages]

def node_a(state: State) -> dict:
    return {"messages": [{"role": "assistant", "content": "hello"}]}

def node_b(state: State) -> dict:
    return {"messages": [{"role": "assistant", "content": "world"}]}

g = StateGraph(State)
g.add_node("a", node_a)
g.add_node("b", node_b)
g.add_edge(START, "a")
g.add_edge("a", "b")
g.add_edge("b", END)
app = g.compile()

result = app.invoke({"messages": [{"role": "user", "content": "hi"}]})
print(result["messages"])
# [{"role":"user",...}, {"role":"assistant","content":"hello"}, {"role":"assistant","content":"world"}]
```

## 拼图过程逐行解读

### `graph = StateGraph(AgentState)`

创建图构建器,把 `AgentState` 当 schema 绑上去。还没生成可执行的图,只是开了张白纸。
LangGraph 会在 `compile()` 时根据 schema 校验所有 node 返回值。

### `graph.add_node("llm", call_llm)`

注册节点 = `(name, callable)`:
- `name` 字符串,后面 `add_edge` 引用用
- `callable` 必须签名 `state -> dict`(纯函数,不修改 state)
- 不能重名,不能用保留字 `__start__` / `__end__`

### `graph.add_edge(START, "llm")`

固定边:从 `START` sentinel 连到 `llm`。
`app.invoke(initial_state)` 时 runtime 把 initial_state 投给 START 的所有出边目标。

### `graph.add_conditional_edges("llm", should_continue, {"tools": "tools", END: END})`

三参数:
| 参数 | 含义 |
|---|---|
| `"llm"` | 源节点 |
| `should_continue` | 路由函数 `state -> str` |
| `{"tools": "tools", END: END}` | 路由字典:把 key 映射到目标节点 |

执行时:llm 跑完 → 调 `should_continue(state)` → 拿到 key → 路由字典查目标 → 跳过去。

### `graph.add_edge("tools", "llm")`

回环边。tools 跑完无条件回 llm。**这一行是 ReAct 循环的本体**。

### `app = graph.compile()`

编译成可执行对象(内部 Pregel 引擎)。
- 校验拓扑:孤儿节点、unreachable 路径、conditional_edges key 缺映射
- 返回 `Runnable`,有 `.invoke()` / `.stream()` / `.astream()`

## 关键设计取舍 / 反直觉点

### "返回补丁"模式 vs "mutate state"

Python 工程师习惯 `messages.append(x)`,LangGraph 强迫你声明"补什么"。这是为了支持
**时间旅行(checkpoint 回滚)**——只有"每一步只描述变更"的纯函数式风格才能让框架精确知道
每一步修改了什么、可以原路退回。同思路在 Redux / React / Elm 里也是同一套。

### 为什么 conditional_edges 要传 dict 而不是直接用返回字符串

间接层。如果 `should_continue` 直接返回 node name,你就把"路由决策"和"目标节点命名"绑死了。
中间加 dict 让你可以**改图拓扑而不改条件函数**:加一个 `replan` 分支只要改路由字典
`{"tools": "tools", "replan": "planner", END: END}`。这就是路由表的标准设计。

### 没分支用 add_edge,有分支才用 add_conditional_edges

工程纪律:条件边越少,图越好理解、越好测试。`add_edge("tools", "llm")` 没决策可做,
不要硬塞 conditional。

### 节点改 state,边决定路径

这个对偶是 LangGraph 全部抽象的核心。Week 1 手写 `run_agent` 把"状态变更"和"流程控制"
混在 while 循环里(`messages.append(...)` 是改状态,`if tool_calls: continue` 是控制流)。
LangGraph **物理拆开**它们:
- 状态变更 → 由 reducer 接管 → 支持 checkpoint / 时间旅行
- 控制流 → 由 edge 接管 → 可视化、可重排

代价是繁琐。Week 1 两行 `while True: ... if not tc: break`,这里要 `add_node + add_conditional_edges + 路由字典 + should_continue` 一坨。**这是"框架税"**,买的是
checkpoint / interrupt / streaming 这些手写版做不到或要 hack 的能力。

### compile() 是校验关卡

LangGraph 错误分两类:
- **编译期错**(拓扑、reducer 签名、node 缺失)→ 改图
- **运行期错**(序列化、API、tool 调用)→ 改 node 内部逻辑

两类错根因和修法完全不同。

### START / END 不是真节点

它们是 sentinel(源码里就是字符串 `"__start__"` / `"__end__"`)。不能 `add_node("__start__", fn)`,
但可以在 `add_edge` / `add_conditional_edges` 里把它们当目标。把 END 想成"图的出口标记",
而不是"最后一个 node"——新手容易搞混。

## reducer 是字段级别的

不同字段可以挂不同 reducer:
```python
import operator

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]    # 消息追加
    counter: Annotated[int, operator.add]      # 数字累加
    flag: bool                                  # 默认覆盖
```

每个字段自己管自己怎么 merge,这是 LangGraph 比 LangChain 优雅的核心原因。

## 路径选择:dict-based vs object-based state

LangGraph 1.x 支持 `TypedDict`(state 是 dict)和 `BaseModel`(state 是对象,点访问 `state.messages`)两种形态。

**90% 教程用 TypedDict + dict**,理由:
- checkpointer 要把 state 序列化(JSON / SQLite),dict 最顺
- 踩坑路径最一致,框架内部 message 序列化也走 dict 格式

如果用 BaseModel,要注意 checkpointer 对 Pydantic 对象的序列化路径走 jsonplus,慢且偶尔出错。
**学习阶段 / 生产首选 TypedDict + dict**。
