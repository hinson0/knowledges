# DeepSeek API 与 OpenAI 的兼容性陷阱

> DeepSeek 声称"OpenAI 兼容",实际是"格式兼容,但 schema 校验更严"。
> 用 OpenAI SDK 调 DeepSeek 时,看似一样的代码会因 schema 严格度不同报 400。

---

## 陷阱 ①:不能直接 append Pydantic 对象到 messages

### 错误现象

```python
resp = client.chat.completions.create(model="deepseek-v4-flash", messages=messages, tools=TOOLS)
assistant_msg = resp.choices[0].message
messages.append(assistant_msg)  # ← 直接 append 整个 Pydantic 对象
# 下一轮请求时报:
# BadRequestError: 400 - 'content should be a string or a list at line 1 column 863'
```

### 真因(实测验证)

错误指针指向 `content` 是**误导**——content 即使是 `None` 也可以正常传。
真因是:openai SDK 把 Pydantic 对象序列化时会带上一堆 DeepSeek 不认的字段:`refusal` / `audio` / `annotations` / `function_call`(deprecated) 等。DeepSeek 严格 schema 校验时被这些噎住,parser 第一个失败位置恰好落在 content 字段附近。

### 正解(实测可用)

手动构造 dict,**只保留 4 个必要字段**:

```python
messages.append(
    {
        "role": "assistant",
        "content": assistant_msg.content,            # None 也行,不要 patch 成 ""
        "tool_calls": assistant_msg.tool_calls,
        "reasoning_content": assistant_msg.reasoning_content,
    }
)
```

为什么 4 个字段缺一不可:
- `role` / `content` / `tool_calls`:OpenAI 标准
- `reasoning_content`:DeepSeek 特有,思考模式下保留思考链。即便当前轮没开思考,也保留 `None` 占位——后续切档(比如 Plan-and-Execute 把某轮切到 thinking="high")时不会丢上下文

---

## 陷阱 ②:思考模式与采样参数互斥

**触发**:同时传 `reasoning_effort="high"` 和 `temperature=0.7`。
**行为**:温度参数被忽略或报错。
**解法**:思考模式下不传 `temperature`/`top_p`/`top_k`/`presence_penalty` 等采样参数。

---

## 陷阱 ③:`reasoning_content` 是独立字段,不在 `content` 里

**误区**:以为模型把推理过程混在 `message.content` 里。
**实际**:DeepSeek 把思考链放在 `message.reasoning_content`,最终答案放在 `message.content`。两个字段都要读。

```python
resp = client.chat.completions.create(
    model="deepseek-v4-flash",
    messages=messages,
    reasoning_effort="high",
)
msg = resp.choices[0].message
print("思考过程:", msg.reasoning_content)
print("最终答案:", msg.content)
```

---

## 工程上怎么处理

写一个 `normalize_assistant_msg` adapter,所有 LLM 调用后过一遍:

```python
def normalize_assistant_msg(msg) -> dict:
    """把 OpenAI SDK 的 ChatCompletionMessage 转成 DeepSeek 安全格式"""
    return {
        "role": "assistant",
        "content": msg.content,
        "tool_calls": msg.tool_calls,
        "reasoning_content": getattr(msg, "reasoning_content", None),
    }
```

每次 `messages.append(...)` 都过一遍,可以解决 90% 的兼容问题。

---

## 参考来源

- 实测于 2026-04-29,DeepSeek V4(`deepseek-v4-flash`)
- OpenAI SDK ≥ 1.40.0
- 错误信息原文:`Failed to deserialize the JSON body into the target type: messages[2]: content should be a string or a list`
- 修正记录:最初猜测是 `content=null` 被拒,实测后确认与 content 值无关,真因是 Pydantic 对象自动序列化带入 DeepSeek 不认的字段
