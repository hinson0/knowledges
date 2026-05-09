# add_messages Reducer 的 4 种输入 + 隐式转换坑

> 来源:Week 2 · Day 3 实验 A 判断题 #2 + 实验 C/D 后续踩坑
> 关键词:`add_messages` / `SystemMessage` / 隐式转换 / role 降级 / 调用约定

---

## 一句话总结

**`add_messages` 接受 4 种输入形式,字符串会被默认转成 `HumanMessage` —— 这条规则会悄悄"吞掉"你的 system 角色,而且不报错不警告。**

---

## 4 种合法输入形式

`add_messages` 这个 reducer 为了"让用户用得方便",接受 4 种 messages 元素:

```python
from langchain_core.messages import SystemMessage, HumanMessage, AIMessage

# 形式 1:Message 对象(最明确)
SystemMessage(content="你是助手")
HumanMessage(content="你好")

# 形式 2:dict + role(OpenAI 风格)
{"role": "system", "content": "你是助手"}
{"role": "user", "content": "你好"}

# 形式 3:tuple (role, content)
("system", "你是助手")
("user", "你好")

# 形式 4:裸字符串 ⚠️ 隐式转 HumanMessage!
"你好"   # ← 等价于 HumanMessage(content="你好")
```

**形式 4 是隐藏的坑**:不报错不警告,但 role 信息悄悄丢失。

---

## 真实踩坑现场

### 错误代码

```python
SYSTEM_PROMPT = "你是一个高效的代码修改助手,..."   # ← 字符串
USER_TASK = "在 X 文件里加 lucas 函数..."           # ← 字符串

app.invoke(
    {"messages": [SYSTEM_PROMPT, USER_TASK]},   # ← 两个裸字符串
    config=config,
)
```

### 实际收到的消息列表

```python
[
    HumanMessage(content="你是一个高效的代码修改助手,..."),  # ← role 降级!
    HumanMessage(content="在 X 文件里加 lucas 函数..."),
]
```

LLM 收到的是 **两条 user message,没有 system**。

---

## 修复 3 选 1

### 方案 A · 显式构造 Message 对象(最推荐)

把字符串常量改成对象:

```python
from langchain_core.messages import SystemMessage, HumanMessage

SYSTEM_PROMPT = SystemMessage(content="你是一个高效的代码修改助手,...")
USER_TASK = HumanMessage(content="在 X 文件里加 lucas 函数...")

# invoke 写法不变
app.invoke({"messages": [SYSTEM_PROMPT, USER_TASK]}, config=config)
```

**优点**:一次改完,后续所有 invoke 都干净;IDE 能补全字段、类型检查能发现 bug。

### 方案 B · dict + role(最少改动)

invoke 处显式包装:

```python
app.invoke(
    {"messages": [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": USER_TASK},
    ]},
    config=config,
)
```

### 方案 C · tuple (role, content)

```python
app.invoke(
    {"messages": [
        ("system", SYSTEM_PROMPT),
        ("user", USER_TASK),
    ]},
    config=config,
)
```

---

## 影响盘点

| 项                        | system 降级成 user 后的影响                                                      |
| ------------------------- | -------------------------------------------------------------------------------- |
| LLM 收到 system prompt    | ❌ 没有                                                                          |
| 工作流约束是否生效        | ⚠️ 靠 LLM 强语义理解硬扛(prompt 里写"你是 X"会被部分理解)                       |
| token 计费                | ✅ 一致(role 不影响计费)                                                       |
| reasoning_content 行为    | ✅ 一致                                                                          |
| **长对话稳定性**          | ❌ 弱化 — system 在注意力机制里有特殊待遇,降级后容易被新消息"压过"             |
| **跨模型迁移性**          | ❌ 弱 — DeepSeek 宽松,GPT-4o / Claude 对 system 缺失更敏感,可能直接拒绝执行流程 |

**结论**:在 DeepSeek 上看似没事,但生产化前必须改掉 —— 是定时炸弹。

---

## `add_messages` 的另一个隐式行为:不去重 system

即使你正确传了 `SystemMessage`,**第 2 次 invoke 又传一次 SystemMessage,reducer 不会去重,会无脑追加到历史末尾**:

```python
# 第 1 次 invoke 后历史:[Sys, Human, AI(tool), Tool, AI(final)]
# 第 2 次 invoke 又塞 system(错误!)
app.invoke(
    {"messages": [SystemMessage(...), HumanMessage("新问题")]},
    config=config,
)
# 结果历史:[Sys, Human, AI, Tool, AI, Sys(又一条!), Human, AI]
#                                     ↑ 中途冒出 system,LLM 会很懵
```

**修复**:第 2 次 invoke **只塞 user 增量**,不要重塞 system。

---

## 守卫式编码(团队代码可加)

如果想强制每次输入都明确角色,在 invoke 之前加一条断言:

```python
from langchain_core.messages import BaseMessage

def _assert_typed_messages(messages):
    for m in messages:
        assert isinstance(m, BaseMessage), (
            f"裸字符串 / dict 容易踩坑,请显式用 SystemMessage / HumanMessage 等。"
            f"实际收到: {type(m).__name__}"
        )

_assert_typed_messages(state["messages"])
app.invoke(state, config=config)
```

---

---

## 隐藏坑 ③ · 模块级常量 message 导致跨调用 id 共享

### 现象

写 thread 隔离测试,断言"yzb 和 bob 两个 thread 的 message.id 不重叠",**居然失败**:

```
AssertionError: ❌ message.id 不该重叠
```

### 根因

```python
LIGHT_SYSTEM = SystemMessage(content="...")   # ← 模块级常量,创建时已分配 id=A
USER_TASK = HumanMessage(content="...")       # ← 同上,id=B

def run_thread(app, thread_id):
    return app.invoke(
        {"messages": [LIGHT_SYSTEM, USER_TASK], ...},  # ← 同一对象塞了两次
        config=...,
    )

run_thread(app, "yzb")   # input 是 [LIGHT_SYSTEM(id=A), USER_TASK(id=B)]
run_thread(app, "bob")   # input 还是 [LIGHT_SYSTEM(id=A), USER_TASK(id=B)]
```

**两个 thread 的 input messages 是同一个 Python 对象,id 当然相同**。`add_messages` 看到 message 已有 id,会**保留不重新生成**(为了支持"按 id update / replace 历史消息"的高级用法)。

### 修复 3 选 1

```python
# 方案 A · tuple 语法,每次解包新建
def run_thread(app, thread_id):
    return app.invoke(
        {"messages": [("system", SYSTEM_TEXT), ("user", USER_TEXT)], ...},
        config=...,
    )

# 方案 B · 工厂函数,每次返回新对象
def fresh_inputs():
    return [SystemMessage(content=SYSTEM_TEXT), HumanMessage(content=USER_TEXT)]

# 方案 C · 直接内联(最简单)
def run_thread(app, thread_id):
    return app.invoke(
        {"messages": [
            SystemMessage(content="..."),  # 每次新建
            HumanMessage(content="..."),
        ], ...},
        config=...,
    )
```

### 核心知识点

> **`BaseMessage.id` 不是"消息内容的指纹",而是"消息对象的实例标识"。**
>
> 同一个对象塞多次,id 不变;不同对象就算 content 完全一样,id 也不同。

### 可迁移规律

**任何带"实例标识符"(id, uuid, primary key)的可变对象,都不应该作为模块级常量复用**。同样会踩的:

- Pandas `DataFrame`(`.copy()` 才能脱离原对象)
- PyTorch `nn.Parameter`(共享会导致梯度耦合)
- SQLAlchemy `declarative_base()` 实例
- LangChain `BaseMessage` / `Document`

**模块级常量适合"值",不适合"标识"**。如果你需要"内容固定 + id 不同",用工厂函数或 tuple 语法,不要用常量对象。

---

## 经验总结(可迁移到任何"善意但危险"的隐式转换)

1. **善意转换不报错** = 很难发现的 bug 来源,要主动加守卫
2. **`role` 错位是"行为奇怪但代码全对"的头号嫌疑犯** —— agent 表现异常时,先 dump messages 列表看 role 分布,再去查 prompt 内容 / tool schema / temperature
3. **跨模型测试是发现这类坑的最有效手段** —— 同一个 prompt 在 A 模型 work、B 模型崩,极可能是 role 没生效

---

## 相关知识

- [LangGraph Checkpointer 持久化基础](langgraph-checkpointer-basics.md) — 续接时为什么不能重塞 system
- [Day 2 错处理 4 件套](../2026-05-08/langgraph-core-concepts.md) — 之前讲过 reducer 的差分语义
