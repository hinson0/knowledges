# AIMessage — LangChain LLM 回复消息类

> 来源:week2/0510/AIMessage.md(已并入 2226.md 的对照表内容)。LangChain 标准化后的"AI 助手回复"消息。call_llm 节点 return 后,经 `add_messages` reducer 转成这个对象进入 state。

## Schema

```python
class AIMessage(BaseMessage):
    content:             str | list           # 文本回复(只调工具时常为 "")
    tool_calls:          list[ToolCall]       # LangChain 标准化的工具调用(见下)
    invalid_tool_calls:  list[dict]           # args 解析失败的备份
    additional_kwargs:   dict                 # 非标准字段兜底(reasoning_content 等)
    response_metadata:   dict                 # token 用量、finish_reason 等
    id:                  str                  # 这条 message 的 UUID(BaseMessage 给的)
    name:                str | None           # 通常 None,标识 sender 时用
    example:             bool                 # 默认 False,few-shot 示例时设 True
```

## 字段详解

| 字段 | 类型 | 含义 / 取值场景 |
|---|---|---|
| `content` | `str` | 文本回复正文。**只调工具不说话时为空字符串 `""`**(不是 None);多模态可能是 `list[dict]` |
| `tool_calls` | `list[ToolCall]` | 标准化后的工具调用列表,详见下方 ToolCall sub-schema。**没有调用时是 `[]` 不是 None** |
| `invalid_tool_calls` | `list[dict]` | LLM 生成的 tool_call args 不是合法 JSON 时的兜底。**生产代码要同时检查这两个字段**,否则会出现"明明调了工具但 graph 直接 END"的 silent bug |
| `additional_kwargs` | `dict` | 非标 provider 字段的逃生舱。常见 key:<br>• `reasoning_content`(DeepSeek/OpenAI 思考模式产物)<br>• `refusal`(OpenAI 拒绝输出时的说明)<br>• `audio` / `annotations` / `function_call`(deprecated)<br>**这是 LangChain 故意设计的扩展点**,不是临时凑的 |
| `response_metadata` | `dict` | LLM API 返回的元数据。常见 key:`token_usage`(prompt/completion/total)、`model_name`、`finish_reason`(stop/tool_calls/length)、`system_fingerprint` |
| `id` | `str` | **这条 message 的 UUID 实例 id**,LangChain BaseMessage 给的。**注意不是 tool_call_id** —— 后者在 ToolCall.id 里 |
| `name` | `str \| None` | 通常 None。Multi-agent 场景里标识哪个 agent 发的(`name="Planner"`) |
| `example` | `bool` | 标记是否为 few-shot 示例消息;影响 LLM 的处理策略,默认 False 即可 |

## `ToolCall` sub-schema(LangChain 标准化后)

```python
class ToolCall(TypedDict):
    name: str          # 工具名(扁平,不再嵌在 function.name 里)
    args: dict         # 参数(已 json.loads,不是字符串)
    id:   str          # tool_call_id,跟后续 ToolMessage.tool_call_id 配对
    type: "tool_call"  # 字面量,固定值
```

## 与 OpenAI 原始格式的字段对照

| LangChain 路径 | OpenAI 原始路径 | 类型变化 |
|---|---|---|
| `tc["name"]` | `tc["function"]["name"]` | str → str(扁平化) |
| `tc["args"]` | `tc["function"]["arguments"]` | **str(JSON 字符串)→ dict(已 parse)** |
| `tc["id"]` | `tc["id"]` | str → str(不变) |
| `tc["type"]` | `tc["type"]` | `"function"` → `"tool_call"` |

## 真实数据样本

### 调工具的 AIMessage(content 为空,tool_calls 有内容)

```python
AIMessage(
    content='',                                     # ← 没文字,只调工具
    additional_kwargs={
        'refusal': None,
        'annotations': None,
        'audio': None,
        'function_call': None,
        'reasoning_content': '用户要求读取文件...让我先读取这个文件。'  # ← DeepSeek 思考产物
    },
    response_metadata={},
    id='edd322fe-3289-4122-8229-5cc1e4343377',     # ← message 实例 id
    tool_calls=[
        {
            'name': 'read_file',                    # ← 扁平化
            'args': {                               # ← 已 parse 成 dict
                'file_path': '/Users/a114514/.../math_utils.py'
            },
            'id': 'call_00_IdzTI2DyPqB8PYurECdT2931',  # ← tool_call_id,跟 ToolMessage 配对
            'type': 'tool_call'                     # ← 固定值
        }
    ],
    invalid_tool_calls=[]                           # ← 解析失败兜底,空表示全部成功
)
```

### 终结的 AIMessage(只说话,不调工具)

```python
AIMessage(
    content='文件中共定义了 **14 个函数**,如下:...',  # ← 文本回复
    additional_kwargs={
        'reasoning_content': '文件内容已经读取完毕,现在我需要列出所有的函数。'
    },
    response_metadata={},
    id='07328a60-...',
    tool_calls=[],                                  # ← 空 = 不再调工具
    invalid_tool_calls=[]
)
```

## 高频用法速查

```python
last = state["messages"][-1]                        # 假设是 AIMessage

# 判断要不要继续调工具
if last.tool_calls:                                 # 空列表 falsy,无需先判 None
    ...

# 取思考内容(可能不存在,要兜底)
reasoning = (last.additional_kwargs or {}).get("reasoning_content") or ""

# 取第一个工具调用
tc = last.tool_calls[0]
tool_name = tc["name"]                              # str
tool_args = tc["args"]                              # dict,直接用,不需 json.loads
tool_id   = tc["id"]                                # 串 ToolMessage.tool_call_id

# 取 token 用量(如果 provider 返回了)
tokens = last.response_metadata.get("token_usage", {})
total  = tokens.get("total_tokens", 0)

# 检查解析失败(生产代码必查)
if last.invalid_tool_calls:
    print(f"⚠ {len(last.invalid_tool_calls)} 个 tool_call 解析失败")
```

## 与 `ToolMessage` 的配对关系

```python
ToolMessage(
    content: str           # 工具执行结果(必须 str,不能是 dict)
    tool_call_id: str      # ← 必须等于上面 AIMessage.tool_calls[i].id
    id: str                # ← 这条 message 的 UUID(跟 tool_call_id 不一样)
)
```

LLM 通过 `tool_call_id` 把"调用"和"结果"配对;`add_messages` reducer 不验证配对,**配对错了 LLM 会困惑但不会崩**(无声 bug,排查靠 grep id)。

## ★ Insight

- **`tool_calls` vs `invalid_tool_calls` 是个常被忽略的二分**。当 LLM 生成的 tool_call args **不是合法 JSON**(罕见但发生过),LangChain 不抛异常,而是把它放到 `invalid_tool_calls` 里 —— `tool_calls` 仍是空列表。生产代码里如果只看 `tool_calls` 而忽略 `invalid_tool_calls`,就会出现"LLM 明明想调工具但 graph 直接 END"的诡异 bug。day4 你不会撞上(prompt 简单),但 day6/week6 mini-aider 复杂 prompt 时会。
- **`additional_kwargs.reasoning_content` 是 LangChain 标准化的"逃生舱"**。LangChain 不可能为每家 LLM 的特殊字段都加一等公民属性,所以专门留 `additional_kwargs` 这个 dict 装非标字段 —— 这是个**故意设计的扩展点**,不是临时凑的。任何 provider 想塞自定义字段都往这里塞,这样 LangChain 升级不会破坏下游代码。
- **`tool_calls = []`(空列表)而非 `None` 是 LangChain 一个刻意约定**。让你写 `if last.tool_calls:` 时不需要先判 None,空列表 falsy 自动覆盖"没有工具调用"的情况。这是个微小但贴心的 API 设计 —— Python 把 None 和空容器都当 falsy,LangChain 利用了这点让代码更短。

## 关联

- `StateSnapshot-schema.md` — AIMessage 在 state.values.messages 列表里的位置
- `hitl-design-protocol.md` — `human_review` 用 `additional_kwargs.reasoning_content` 做 payload 的 reasoning 字段
- `langgraph-state-vs-control-flow.md` — `add_messages` reducer 的形态约定
- DeepSeek 文档 — `reasoning_content` 字段的开启条件(`reasoning_effort` 参数)
