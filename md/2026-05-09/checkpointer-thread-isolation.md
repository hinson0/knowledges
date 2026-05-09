# LangGraph Checkpointer · Thread 隔离的"假象续接"陷阱

> 来源:Week 2 · Day 3 实验 A 判断题 #4 的真实踩坑
> 关键词:`MemorySaver` / `thread_id` / `checkpointer` / 假象续接

---

## 一句话总结

**当 LLM 足够强,它会"自己救场"补全语境 —— 这种行为非常容易被误判成"checkpointer 续接"。判断 thread 是否真的隔离,不要看 LLM 的回答内容,要看 messages 列表的开头是不是历史 system / user。**

---

## 实验场景

```python
checkpointer = MemorySaver()
app = graph.compile(checkpointer=checkpointer)

# 第 1 轮:用 thread_id="yzb"
config_yzb = {"configurable": {"thread_id": "yzb"}, "recursion_limit": 30}
r1 = app.invoke(
    {"messages": [SYSTEM_PROMPT, USER_TASK], "iter_count": 0},
    config=config_yzb,
)
# r1: messages=9, iter_count=4

# 第 2 轮:换成 thread_id="bob",只塞一条 user message
config_bob = {"configurable": {"thread_id": "bob"}, "recursion_limit": 30}
r2 = app.invoke(
    {"messages": [HumanMessage(content="基于刚才看到的内容,add 这个函数是做什么的?")]},
    config=config_bob,
)
# r2: messages=N, iter_count=4
# r2 居然能"答出来" add 函数的功能!
```

## 第一反应(错误)

> "thread_id 都换了还能接到前一轮?难道 MemorySaver 不隔离?"

## 真相

**bob 跟 yzb 是完全独立的两个会话**,bob 的 messages 列表从空白开始。它"答出来"是因为 LLM 自己调了 `grep_code` + `read_file` 把 `math_utils.py` 重新读了一遍 —— **它把那条没头没尾的 user 当成普通问题,主动用工具补全了语境**。

### 区分"假象续接"vs"真续接"的判断方法

不要看回答内容。看 `messages[0]`:

| 现象              | messages[0]                      | 含义                       |
| ----------------- | -------------------------------- | -------------------------- |
| 真续接(同 thread) | SystemMessage(完整工作流)        | reducer 把历史 + 增量合并  |
| 假象续接(新 thread) | HumanMessage(本轮 input)         | 全新会话,LLM 自己重新查    |

### 数据对比(本次实验真实数字)

| 项                  | r1 (yzb)                     | r2 (bob)                              |
| ------------------- | ---------------------------- | ------------------------------------- |
| messages[0]         | system_prompt(完整工作流)    | HumanMessage("基于刚才看到的内容...") |
| 第一次 LLM reasoning | "用户要求...先读取文件"       | "用户问 add 函数,但没给我代码,我得先搜索" |
| 调用工具序列         | read_file → write_file → run_shell | grep_code → read_file                |
| iter_count          | 4(yzb 独立累加)              | 4(bob 独立从 0 累加)                 |

**两次 iter_count 都是 4,纯属巧合**。yzb 的 4 = system 给的工作流任务跑了 4 轮 LLM;bob 的 4 = 自己搜索 + 读取 + 回答跑了 4 轮 LLM。两个 4 互不相干。

---

## 程序化验证

如果还想再确认隔离生效,跑这段:

```python
print("yzb 历史 checkpoint 数:",
      len(list(app.get_state_history({"configurable": {"thread_id": "yzb"}}))))
print("bob 历史 checkpoint 数:",
      len(list(app.get_state_history({"configurable": {"thread_id": "bob"}}))))

print("yzb 当前 messages 数:",
      len(app.get_state({"configurable": {"thread_id": "yzb"}}).values["messages"]))
print("bob 当前 messages 数:",
      len(app.get_state({"configurable": {"thread_id": "bob"}}).values["messages"]))
```

两个 thread 的快照树完全独立,messages 列表互不重叠。

---

## 为什么会有这种"假象续接"

LLM 很强,有 3 重补救能力让你看起来"它记得":

1. **工具补全语境**:你问"刚才那个文件",它没历史就用 `grep_code` / `read_file` 找
2. **常识补全**:你问"add 函数",它从函数名就能猜到 90% 的语义
3. **训练数据补全**:开源代码的 `math_utils.py` 它"见过"

这三层叠加起来,就算 thread 完全隔离,LLM 也能给出**看起来像连贯对话**的回答。**这是 LLM 应用层调试的一类典型陷阱**:行为看着对,但底层机制是错的,生产环境换个新 LLM 模型可能就崩了。

---

## 教训(可迁移到其他场景)

1. **永远从底层数据(messages 列表)判断状态机行为,不要从 LLM 输出判断**
2. **MemorySaver 的隔离 key 就是 `thread_id`**,只要 key 不同就完全独立
3. **想真正测续接,要用同 thread_id**,而且 input 只塞差分(不要重塞 system)
4. **想真正测隔离,要看 messages[0]**,而不是看回答内容像不像"接上了"

---

## 相关知识

- LangGraph reducer "差分合并" 语义(见 0508 笔记 langgraph-core-concepts)
- `add_messages` 不去重 system → 重塞 system 会污染历史
- `get_state` / `get_state_history` 是诊断 checkpointer 状态的两把钥匙
