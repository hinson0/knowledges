# Parallel Function Calling —— LLM Agent 性能优化的"免费午餐"

> 同样的工作量,LLM 可以选择**并行**或**串行**编排工具调用。
> 真实数据:并行写法比串行写法**节省 2,301 token (-26.7%) + 1 轮 API 往返**。
> 这是 iterations 方差的根本来源,也是评估工程师必须监测的指标。

## 1. 什么是 Parallel Function Calling

OpenAI 兼容 API(2023 末引入,DeepSeek / Anthropic 跟进)允许 assistant 在**同一个响应**里返回多个 `tool_calls`,客户端**并行执行**后再回填多个 `tool` 消息。

```python
# 一个 assistant 响应可包含多个 tool_calls(并行):
{
    "role": "assistant",
    "tool_calls": [
        {"id": "call_001", "function": {"name": "write_file", "arguments": "{\"file_path\": \"a.py\", ...}"}},
        {"id": "call_002", "function": {"name": "write_file", "arguments": "{\"file_path\": \"b.py\", ...}"}}
    ]
}

# 客户端必须返回对应数量的 tool 消息(id 必须配对,顺序无关):
[
    {"role": "tool", "tool_call_id": "call_001", "content": "已写入 ..."},
    {"role": "tool", "tool_call_id": "call_002", "content": "已写入 ..."}
]
```

**LLM 是否选择并行 = LLM 自己的判断**——它感知到"多个独立、无先后依赖的操作"时倾向并行。

## 2. 真实实验数据(2026-05-05)

任务:在 math_utils.py 新增 fibonacci + 写 test_fib.py + run 测试。同一个 strong prompt 跑 5 次,**`tool_calls_count` 全是 4**,但 `iterations` 在 4-5 之间晃。翻 trace 对比:

### 并行写法(iterations=4)

```
iter 0: assistant → tool_calls=[read_file]              (1 call)
iter 1: assistant → tool_calls=[write_file, write_file] (2 calls 并行!)
iter 2: assistant → tool_calls=[run_shell]              (1 call)
iter 3: assistant → 给最终回答(无 tool_calls,return)
```

### 串行写法(iterations=5)

```
iter 0: assistant → tool_calls=[read_file]
iter 1: assistant → tool_calls=[write_file (math_utils)]   ← 拆成两轮
iter 2: assistant → tool_calls=[write_file (test_fib)]
iter 3: assistant → tool_calls=[run_shell]
iter 4: assistant → 给最终回答
```

### 真实代价对比

| 版本 | prompt tokens | completion tokens | total | iterations |
|---|---|---|---|---|
| 并行(iter=4) | 7,334 | 1,289 | **8,623** | 4 |
| 串行(iter=5) | 9,605 | 1,319 | **10,924** | 5 |
| 差额 | **+2,271** | +30 | **+2,301 (+26.7%)** | +1 |

**串行版多花 2,301 token (+26.7%)**——增长的几乎全在 prompt 端(+2,271 of 2,301)。

## 3. 为什么 prompt token 增长这么多

OpenAI 兼容 API 是**无状态**的——每次 LLM 调用都必须重发完整 messages 历史。多一轮 = 多重发一次完整上下文:

```
第 N 轮 prompt = system + user + (前 N-1 轮所有 assistant + tool messages)
```

第 5 轮的 prompt 包含前 4 轮所有内容,**第 5 轮单次就 ≈ 2300 token**。每多一轮,prompt token 几乎线性增长。

**生产意义**:1000 次任务规模下,串行 vs 并行 = 多花 230 万 token。在 DeepSeek V4 价格下(假设 ¥1/M tokens),约多花 ¥2.3——单次微小,规模化后是真金白银。

## 4. 如何用 prompt 引导并行

加一条原则到 system prompt(实测有效但需调措辞):

```
多个独立的写入或读取操作请在同一轮一次性并行发起 tool_calls,
不要分多轮。仅当后一个操作依赖前一个的结果时才串行。
```

**关键措辞要素**:
- ✅ 给具体动作("一次性并行发起")
- ✅ 给反例("不要分多轮")
- ✅ 给边界("仅当依赖时才串行")

不要写:
- ❌ "请尽量优化效率" —— LLM 不知道具体怎么做
- ❌ "禁止分多轮" —— 否定式 + 没考虑依赖边界

## 5. 不能并行的边界(LLM 必须知道)

| 场景 | 能并行吗 | 原因 |
|---|---|---|
| 写多个**独立**新文件 | ✅ | 互不影响 |
| 读多个**独立**文件 | ✅ | 都是只读 |
| `read_file → 处理后 write_file` | ❌ | 写依赖读的内容 |
| `write_file → 立即 run_shell 测试` | ❌ | shell 依赖文件已写完 |
| `git status → git add → git commit` | ❌ | 依赖链 |

**经验法则**:**写之前必须读**、**测试之前必须写**——这两条是 99% Coding Agent 任务的依赖底线。

## 6. 客户端实现:safe_dispatch 的并行处理

如果工具是 IO 密集型(文件读写、shell 调用、HTTP 请求),客户端**应该用线程池/asyncio**真正并行执行:

```python
# 串行(简单但不利用并行):
for tool_call in assistant_msg.tool_calls:
    result = safe_dispatch(tool_call)
    messages.append({"role": "tool", "tool_call_id": tool_call.id, "content": result})

# 并行(IO 密集场景):
import concurrent.futures
with concurrent.futures.ThreadPoolExecutor() as ex:
    futures = {tool_call.id: ex.submit(safe_dispatch, tool_call) for tool_call in assistant_msg.tool_calls}
    for tc_id, fut in futures.items():
        messages.append({"role": "tool", "tool_call_id": tc_id, "content": fut.result()})
```

**注意**:并行执行 != 并行 API 响应。LLM 已经决定并行(tool_calls 列表),客户端选择"是否真的并行 dispatch"是另一个层面的优化(降执行延迟,不影响 token)。

## 7. 评估系统该捕捉的指标

光看 `tool_calls_count` 看不出并行/串行差异(都是 4)。需要 derived metric:

```python
parallelism_ratio = tool_calls_count / max(iterations - 1, 1)
# 减 1 是因为最后一轮 LLM 通常给最终回答,没 tool_calls
```

| 值 | 含义 |
|---|---|
| `1.0` | 完全串行(每轮 1 个 tool_call) |
| `>1.0` | 有并行发生 |
| `2.0` | 平均每轮 2 个 tool_call |

监测 `parallelism_ratio` 的均值和方差 = 评估 prompt 对并行编排的控制力。

**今天数据**:
- 并行版 `4 / (4-1) = 1.33`
- 串行版 `4 / (5-1) = 1.00`

## 8. 关键认知

- **同样工作量可以有不同代价**:`tool_calls_count` 是"做了多少事",`iterations` 是"分几轮做"。后者贵 N 倍。
- **iterations 方差 ≈ 并行决策的非确定性**:strong prompt 在"做什么"上锁死(σ=0 of tool_calls),但在"怎么编排"上仍有自由度(σ=0.55 of iterations)。
- **Cursor / Aider / Claude Code 都重度依赖并行 FC**:多文件改动场景里,这是核心性能优化。
- **这是评估工程师该看的指标**:Week 7 Eval Harness 必须包含 `parallelism_ratio`,不能只统计 trap 命中率。

## 9. 实测验证:V2 prompt 把 iterations σ 压到 0

加入第 6 条原则(并行编排 + 依赖边界)后跑 5 次:

| 指标 | Strong V1 (5 条) | **Strong V2 (6 条)** |
|---|---|---|
| `tool_calls` 平均 / σ | 4.0 / 0.00 | 4.0 / 0.00 |
| `iterations` 平均 / σ | 4.4 / **0.55** | 4.0 / **0.00** ⭐ |
| 序列指纹种数 | 1 | 1 |
| `parallelism_ratio` | 1.18 | **1.33** |
| trap 命中 | 5/5 | 5/5 |

**结论**:`iterations` σ 从 0.55 → 0.00,5 次跑行为**字字相同**。LLM 全部选择并行写法。

V2 加入的第 6 条原则(可复用):

```
6. 多个独立的文件操作请在同一轮 tool_calls 中并行发起(例如同时创建两个互不依赖的文件)。但有先后依赖的操作必须串行:read_file 必须在 write_file 之前独立一轮(因为修改依赖原内容),run_shell 验证必须在所有 write_file 完成后独立一轮(因为测试依赖文件已写完)。
```

## 10. 简历素材(真实数字)

> 通过 trace 对比发现 LLM 在同任务下并行 vs 串行编排存在 26.7% token 差异(并行 8,623 / 串行 10,924,n=5),
> 在 system prompt 中加入并行编排原则与依赖边界约束后,**将 `iterations` σ 从 0.55 压至 0**,
> 5 次跑实现完全确定性行为(单一工具序列指纹 + tool_calls σ=0 + iterations σ=0),
> 设计 `parallelism_ratio` derived metric 用于持续监测 Agent 编排质量。

## 11. 与后续 Week 的连接

- **Week 5 Context Caching**:DeepSeek context cache 可以让前文重复部分按 0.1 倍价格计费。**与并行优化叠加** = 理论上把多轮的 prompt 重发代价压到极低。
- **Week 6 Multi-Agent**:Planner 输出多个独立 task → 让 Coder Agent 并行执行,这是 Multi-Agent 性能的根本依赖。
- **Week 7 Eval Harness**:`parallelism_ratio` 进入评估指标矩阵,与 trap 命中率 / token / latency 并列。

## References

- OpenAI Parallel Function Calling 文档:<https://platform.openai.com/docs/guides/function-calling#parallel-function-calling>
- DeepSeek FC 兼容文档:<https://platform.deepseek.com/api-docs/zh-cn/api/create-chat-completion>(支持 parallel,行为与 OpenAI 一致)
