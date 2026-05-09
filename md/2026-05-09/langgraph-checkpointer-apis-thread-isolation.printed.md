---
name: LangGraph Checkpointer、API变更与Message Role缺失
description: LangGraph 1.x检查点系统、get_state/get_state_history API、SystemMessage丢失问题、thread隔离验证方法
type: reference
---

## 核心概念

### 1. Checkpointer线程隔离验证

**判断标准**：不看LLM回答内容，看 `messages[0]` 是否是历史system message。

**陷阱**："现象正确但机制错误" —— LLM能通过三种方式掩盖系统bug：
- 工具补全（缺少信息时调用工具查询）
- 常识补全（基于通用知识推理）
- 训练数据补全（基于已知的常见场景）

结论：**LLM的正确输出 ≠ 系统实现正确**。设计隔离实验时，要**制造LLM无法自救的特殊语境**（如"基于刚才第47行的注释"），让LLM没有救场空间。

---

## LangGraph 1.x API详解

### StateSnapshot关键字段

```python
snap = app.get_state(config)  # → StateSnapshot

snap.values              # state dict：{"messages": [...], "iter_count": N}
snap.next               # 下一个要跑的node名；() 表示已END
snap.config             # 该快照的config（含checkpoint_id）
snap.metadata           # 包含：source / step / parents（1.x已去除writes）
```

### 倒序History的含义

```python
history = list(app.get_state_history(config))
# history[0]  = 最新快照
# history[-1] = 初始空快照（step=-1, messages=[]）
```

**三个关键观察**：
1. **倒序存储**：方便"回到最近节点"（类似git log）
2. **单调递增**：messages数 + iter_count 沿history倒序严格递增（reducer只追加，checkpoint不可变）
3. **step编号**：`metadata.get("step")` 显示super-step序号，从-1开始

---

## next字段的反推逻辑

**用途**：通过 `next` 推断**这一步是哪个node跑完的**（LangGraph 1.x从metadata.writes移除后的替代方案）

| history[i].next   | 含义                    | 推论：history[i-1]是                |
|-------------------|------------------------|-------------------------------------|
| `('__start__',)`  | 还没跑                  | (无前驱)                           |
| `('llm',)`        | 下一步要跑llm          | tools刚跑完或START                 |
| `('tools',)`      | 下一步要跑tools        | llm刚跑完                          |
| `()` 空tuple      | 已END                  | llm给最终答复刚跑完                |

---

## LangGraph 版本变更坑点

### 从0.x → 1.x的API迁移

**metadata.writes被移除**：
- 0.x：`metadata.get("writes")` → `{"llm": {...}, "tools": {...}}`
- 1.x：metadata只有 `source / step / parents` 三个字段

**观察node写入的新方式**：用 `app.stream(stream_mode="updates")`

```python
for chunk in app.stream(init_state, config=config, stream_mode="updates"):
    # chunk 形如 {"node_name": {字段: 值}}
    for node_name, patch in chunk.items():
        print(f"[{node_name}] 写入: {list(patch.keys())}")
```

期望输出：
```
[__start__] 写入: ['messages', 'iter_count']
[llm]       写入: ['messages', 'iter_count']
[tools]     写入: ['messages']
```

---

## SystemMessage Role丢失问题

### 根因：add_messages的隐式转换

**错误做法**（day3踩坑）：
```python
SYSTEM_PROMPT = "你是一个高效的代码修改助手..."  # ← 纯字符串
USER_TASK = "在/Users/..."                       # ← 纯字符串

input = {"messages": [SYSTEM_PROMPT, USER_TASK], ...}
```

`add_messages` reducer 对**裸字符串的默认转换**：`str → HumanMessage`
→ 结果：两条user message，**没有system**

### 修复方案（3选1）

**方案A · 显式Message对象（推荐）**：
```python
from langchain_core.messages import SystemMessage, HumanMessage

SYSTEM_PROMPT = SystemMessage(content="你是一个高效的代码修改助手...")
USER_TASK = HumanMessage(content="在/Users/...")
```

**方案B · dict+role**：
```python
input = {
    "messages": [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": USER_TASK},
    ]
}
```

**方案C · tuple语法**：
```python
input = {
    "messages": [
        ("system", SYSTEM_PROMPT),
        ("user", USER_TASK),
    ]
}
```

### Role缺失的影响

| 项                    | 影响                                                     |
|----------------------|--------------------------------------------------------|
| LLM收到的system      | ❌ 没有（变成两条user）                                  |
| 工作流遵守度          | ⚠️ 靠LLM语义理解硬扛（内容里写了"你是..."还能行事）     |
| 长对话稳定性          | ❌ 弱化（system有特殊注意力优先级，降级后易被压过）       |
| 跨模型迁移性          | ❌ GPT-4o/Claude对缺失system更敏感，DeepSeek宽容          |

**验证修复**：
```python
first = app.get_state(config)["messages"][0]
assert isinstance(first, SystemMessage)  # 修复后应为True
```

---

## 可迁移教训

1. **"现象对但机制错"的陷阱是LLM应用调试的通用范式**
   - Week 5 Langfuse埋点、Week 7 Eval Harness都会反复遇到
   - 提前建立"看底层数据而非LLM输出"的判断范式

2. **LangGraph版本迭代快，API小改容易踩坑**
   - 不信文档/记忆，**先dump完整数据结构** → `pprint(dict(...))`
   - 这是面试级的工程素养

3. **stream_mode是观测LLM agent的关键**
   - `stream_mode="updates"` 看增量写入
   - `stream_mode="debug"` 看最详细内部事件
   - Week 5可视化埋点时再次用到

4. **next字段被严重低估，它决定resume行为**
   - fork / interrupt 后resume都靠看 `next` 决定续点
   - Day 5 HITL做interrupt-resume时会看到它停在 `("human_review",)`
