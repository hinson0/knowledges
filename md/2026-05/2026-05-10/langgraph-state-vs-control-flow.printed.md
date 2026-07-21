# LangGraph 状态变化 vs 控制流变化(`return {}` 的精确含义)

> 来源:week2/0510/0843.md。澄清"node return 跟 graph 流动"的边界,新手最容易在这里建错心智模型。

## `return {}` 的精确含义

**不是 "什么都不操作"**,而是 **"对 state 没有任何更新"**。控制流仍然往下走。

把 node 想成一个 "**状态增量计算器**":

- 输入:当前 state
- 输出:**state 的增量**(delta dict),框架用 reducer 把 delta merge 进 state
- 控制流:**完全由 edges 决定**,跟你 return 什么无关

所以 `return {}`:

- ✅ 状态:无更新(messages 不追加、iter_count 不变)
- ✅ 控制流:**仍然按 edge 走** —— 在 day4 里就是 `human_review → (post_review) → tools`

| 你以为它说"什么都不操作"包含 | 实际它管不管 |
|---|---|
| 不改 state | ✅ 管(空 delta = 不改) |
| 不往下执行节点 | ❌ **不管**(那是 edges 的事,跟 return 无关) |

如果想"不往下执行"必须用 edge:`graph.add_conditional_edges(... → END)`,而不是 `return {}`。

## 4 种 return 形态对照(node 函数语义全集)

```python
return {}                                  # 状态:零增量。最常见的"approve 但不改 state"
return None                                # 跟 return {} 完全等价(LangGraph 容忍)
return {"messages": [HumanMessage(...)]}   # 状态:append 一条消息(add_messages reducer)
return {"iter_count": 1}                   # 状态:iter_count += 1(operator.add reducer)
```

**没有任何一种 return 形态可以中断 graph 流动**。流动是 edges 的职责。

## 用 day4 具体例子套进去理解

```python
def human_review(state):
    decision = interrupt(...)
    if decision["action"] == "reject":
        return {"messages": [HumanMessage("[人工拒绝]")]}   # ① state 增量:append HumanMessage
    return {}                                              # ② state 增量:零

# 注意:① 和 ② return 完之后,graph 都会接着调 post_review 节点(因为有 edge 连过去)
# 区别只在于 post_review 看到的 state["messages"] 是不是多了一条
```

`post_review` 看到 state 末条:

- 走 ① 路径(reject)→ 末条是 HumanMessage → 路由到 `llm`
- 走 ② 路径(approve)→ 末条仍是原来那个 AIMessage → 路由到 `tools`

**控制流分叉是 post_review 干的**(它 return 一个字符串作为路由信号),**不是 human_review 的 `return {}` 干的**。

## ★ Insight

- **LangGraph 严格区分"状态变化"与"控制流变化"**,这是它跟"裸 if-else 调用 LLM"的最大设计差异。Node 只管"我要改什么状态",不管"下一步去哪";edges 只管"根据状态决定去哪",不改状态。这种**职责分离**让你能单独测试 node(给 fake state,断言 return delta),也能单独测试 edges(给 fake state,断言路由结果)。week1 的裸 ReAct loop 里,这两件事是耦合的(`if last.tool_calls: do_tool(); else: break`),所以测试要 mock 两层。
- **`return None` ≡ `return {}` 是个有趣的 ergonomic**。Python 的函数没显式 return 时默认返回 None —— LangGraph 容忍这一点是为了让"纯副作用 node"(如打 log、写 metric)写起来不啰嗦。但**约定俗成是写 `return {}`**,显式表达意图。下次你看见某个 node 没 return,不用慌,等价于零增量。
- **理解了 "node 是状态增量函数" 这个心智模型,你能秒懂为什么 reducer 是关键设计**。如果 node return 的是"完整 state",那就需要每个 node 都正确读+写所有字段,极易出现"我覆盖了别人的更新"。LangGraph 让 node 只 return delta、由框架做 merge,这跟 React 的 setState、Git 的 patch、CRDT 的 op 是同一种思想 —— **增量优于全量**。这个思想会贯穿你后面所有 multi-agent / subgraph 设计。

理解了这点,你看 `return {}` 时就不会再误解为"中断"。它纯粹就是"我对 state 没意见,继续往下走"。

## 关联

- `hitl-interrupt-mechanism.md` — interrupt 是节点内 yield 点,跟 return 是同一层(节点函数体内)的两种暂停/退出方式
- `hitl-design-protocol.md` — Day 4 设计三问的 Q3=A(消息总线)实现里,`return {}` 是 approve 路径的标准产物
- `langgraph-stream-chunks.md` — stream chunk 的 `{node: delta}` 形态本质就是 reducer 的 input preview
