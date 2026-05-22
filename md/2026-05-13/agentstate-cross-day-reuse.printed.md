# AgentState 跨 day/模块复用 — channel conflict 与 4 种工程方案

> 来源:`week2/day5_workspace/0513/0807.md`(channel conflict bug)+ `0814.md`(4 种方案对比)
> 落盘日期:2026-05-13

## 概念

**LangGraph 通过节点函数签名推断 state schema**,不是从一个中央定义读取。每个 `add_node()` 时,LangGraph 拆解函数 `state: AgentState` 注解里的字段,**作为 channel 注册到 graph**。

字段 = channel,reducer 配置 = channel 合并策略。**两个同名 `AgentState`(day5 一个 + infra 一个)如果同名字段的 reducer 不一致**,LangGraph 把 state 当数据库 schema 处理,会 fail-fast 拒绝继续:

```text
ValueError: Channel 'iter_count' already exists with a different type
```

这条 fail-fast 比 silent merge 友好得多 —— 想象 reducer 配错了 silent 跑下去,state 数据被悄悄覆盖,debug 起来想自杀。

## 字段表 · 现象 vs 根因

| 维度 | day5 自定义 `AgentState` | infra `AgentState`(被 `call_tools` 引用) | 后果 |
|---|---|---|---|
| `iter_count` 类型 | `NotRequired[int]` | `NotRequired[Annotated[int, operator.add]]` | reducer 不一致 |
| Reducer 行为 | last-write-wins(每次覆盖) | `operator.add`(累加) | 同 channel 注册时冲突 |
| 报错位置 | `g.add_node("tools", call_tools)` | 同 | LangGraph 注册 channel 时炸 |

**根因**:`call_tools` 是 infra 导入的,签名引用的是 infra 版本 AgentState;`retrieve` / `llm` 节点引用的是 day5 版本 AgentState。**LangGraph 不在乎"AgentState 是同一个类",在乎"channel `iter_count` 的 reducer 配置是否一致"**。

## 示例 · 一行修法(临时)

让 day5 的 `iter_count` 跟 infra 对齐,加 `operator.add` reducer:

```python
import operator

class AgentState(TypedDict):
    messages: Annotated[list, add_messages]
    iter_count: NotRequired[Annotated[int, operator.add]]   # ← 加 operator.add
    retrieved_memories: NotRequired[list[str]]
    thread_id: NotRequired[str]
```

跑通后 graph 应该 build 成功。但这是**临时手贴**,本质问题是"AgentState 多处定义",**工程化做法见下方 4 种方案**。

## 字段表 · 4 种工程方案对比

| 方案 | 思路 | 优 | 缺 | 何时选 |
|---|---|---|---|---|
| **A · TypedDict 继承** | `infra` 提供 base state,day5 继承 + 加字段 | base 字段+reducer 只在 1 处定义;day5 只声明新增 | TypedDict 继承在 Pyright 偶有小 quirks | **day5 推荐** |
| **B · 单一巨型 state** | 所有 day 的字段集中在一个 TypedDict | 一份 truth,绝对一致 | god-object 反模式,字段越来越多,day3-4 看着不用的字段 | **不推荐** |
| **C · Mixin 组合** | `CoreState + MemoryMixin + PlannerMixin` 按能力拼接 | 职责分离清晰,multi-agent 时各 agent 拼自己要的 | 比 A 多一档抽象,day5 用不上 | **week6 multi-agent 再做** |
| **D · LangGraph `input_schema`** | 每个节点声明自己关心的 state 子集 | 节点签名最干净 | LangGraph 文档少提,生态不成熟,坑多 | **week7 evaluation 系统再考虑** |

## 示例 · 方案 A 落地(3 步)

### Step 1 — 新建 `week2/infra/state.py`

```python
# week2/infra/state.py
import operator
from typing import Annotated, NotRequired, TypedDict
from langgraph.graph import add_messages


class AgentState(TypedDict):
    """所有 day 共享的基础 state schema。"""

    messages: Annotated[list, add_messages]
    iter_count: NotRequired[Annotated[int, operator.add]]
```

### Step 2 — 改 `infra/agent_graph.py`

```python
# 顶部加(re-export 让旧 import 还能用)
from .state import AgentState   # noqa: F401

# 删原文件就地定义的 AgentState
```

### Step 3 — 改 `day5_memory.py`

```python
# 替换原 AgentState 定义
from infra.state import AgentState as BaseAgentState


class AgentState(BaseAgentState):
    """day5 state:在 base 基础上加召回字段。"""

    retrieved_memories: NotRequired[list[str]]
    thread_id: NotRequired[str]
```

**关键**:`call_tools` / `call_llm` 的签名 `AgentState` 仍引用 base,**day5 的 AgentState 是 base 超集**,LangGraph 合并 channel 时不冲突。

## 示例 · 方案 C 预告(week6 multi-agent)

```python
# infra/state.py
class CoreState(TypedDict):
    messages: Annotated[list, add_messages]
    iter_count: NotRequired[Annotated[int, operator.add]]


class MemoryMixin(TypedDict):
    retrieved_memories: NotRequired[list[str]]
    thread_id: NotRequired[str]


class PlannerMixin(TypedDict):
    plan: NotRequired[list[str]]
    current_step: NotRequired[int]


# day5(目前)
class AgentState(CoreState, MemoryMixin): ...


# day6+ mini-Aider(未来)
class PlannerAgentState(CoreState, PlannerMixin, MemoryMixin): ...
class CoderAgentState(CoreState, MemoryMixin): ...
class ReviewerAgentState(CoreState): ...
```

## 坑 / Why

**结论**:LangGraph 多 day/模块复用 state,必须**单一定义 + 继承扩展**,不能就地各自定义同名 TypedDict。

**Why**:LangGraph 把 state 当数据库 schema 处理 —— 每个字段是一张表的列,reducer 是列的合并策略,**两个 TypedDict 同名字段不一致 = schema migration 不一致**,严格拒绝继续。这是 LangGraph "显式 schema" 哲学的代价。比 silent merge 友好得多。

**How to apply**:
- 单 day 单 graph 时,把 AgentState 放在 day 自己的文件里没问题
- 一旦跨 day 复用 infra 的节点函数(`call_tools` / `call_llm` 等),**必须用方案 A 继承**
- 改 base AgentState 时,所有 day 自动跟着改 —— 一次定义,处处生效
- multi-agent subgraph 时升级到方案 C(Mixin),不同 agent 拼自己要的字段
- production-grade 项目:**state 文件单独放,跟节点函数解耦**,放在依赖图最底端(节点依赖 state,state 不依赖节点)

## 坑 / Why · 为什么 state 单独放 `state.py`

**结论**:`state.py` 跟 `agent_graph.py` 分离是 **separation of concerns**。

**Why**:`agent_graph.py` 装"通用节点函数",`state.py` 装"通用 schema"。**state 是节点的 dependency,不是 byproduct** —— 节点需要 state 才能工作,所以 state 应该在依赖图更底端,独立文件让 import 关系单向(节点依赖 state,state 不依赖节点)。

**How to apply**:这条规则在任何 Python 项目都适用 —— model / schema / config 放在依赖图最底端。

## 坑 / Why · TypedDict 继承在 LangGraph 的特殊地位

**结论**:LangGraph state **必须用 TypedDict 而非 Pydantic BaseModel**。

**Why**:LangGraph 框架内部判断字段类型用的是 Python typing 内省,Pydantic 实例不被识别。所以 LangGraph state 设计哲学有点"复古" —— 直接拥抱 Python 原生 typing。

**How to apply**:
- 跨 day 复用 state 优先用 TypedDict 继承(方案 A)
- 不要试图用 `pydantic.BaseModel` 当 state 类型
- TypedDict 继承在 Pyright 偶有小 quirks(比如 `NotRequired` 字段继承顺序),但 LangGraph 完全支持

## 落地检查清单

- [ ] 新建 `week2/infra/state.py`,把 AgentState 抽进去
- [ ] `infra/agent_graph.py` 改成 `from .state import AgentState`(留个 import 让旧引用还能用)
- [ ] `day5_memory.py` 改成 `class AgentState(BaseAgentState):`,只列新增字段
- [ ] 跑 `app = build()`,确认 channel 冲突消失
- [ ] 跑端到端剧本,看 t2 LLM 回复有没有"Mac M2"
- [ ] day3 / day4 的 AgentState 也改成继承 base,改 base 一次到位

## 关联

- [langgraph-rag-memory-3-step-plan.printed.md](./langgraph-rag-memory-3-step-plan.printed.md) — day5 三步收口路线图(retrieve/inject/summarize)
- [../2026-05-10/langgraph-state-vs-control-flow.md](../2026-05-10/langgraph-state-vs-control-flow.md) — state delta 跟 control flow 的边界
- [../2026-05-10/StateSnapshot-schema.md](../2026-05-10/StateSnapshot-schema.md) — values/next/config/tasks/interrupts 字段
- `week2/infra/agent_graph.py` — 通用节点(`call_llm` / `call_tools` / `should_continue`)
- `week2/day5_workspace/day5_memory.py` — day5 主代码(继承 base 后)

---

来源:`week2/day5_workspace/0513/0807.md` + `0814.md`
落盘日期:2026-05-13
