## StreamingResponse 是 Response 的子类

```
Response                    ← 基类
├── HTMLResponse
├── JSONResponse
├── PlainTextResponse
└── StreamingResponse       ← 子类，是 Response
```

所以 `Awaitable[Response]` 完全能覆盖返回 `StreamingResponse` 的情况——这就是**里氏替换原则（LSP）**，子类可以在任何期望父类的地方使用。

## 那为什么 `.body` 不能用？

这正是这里"坑"的地方：

- **类型注解说的是 `Response`**，`Response` 确实有 `.body` 属性
- **运行时实际返回的是 `StreamingResponse`**，它**没有** `.body` 属性，用的是 `.body_iterator`

```python
# Response 基类
class Response:
    body: bytes              # ← 有这个属性

# StreamingResponse 子类
class StreamingResponse(Response):
    body_iterator: AsyncIterator  # ← 用这个代替
    # 没有 .body！
```

所以你写 `response.body = ...` 时：

- **类型检查器（mypy/pyright）不会报错**，因为它认为是 `Response`，有 `.body`
- **运行时静默失败**，因为 `StreamingResponse` 根本不读 `.body`

## Insight

1. **类型注解没错，但会给你虚假的安全感**。`call_next` 的返回类型标注为 `Response`，但运行时实际是 `StreamingResponse`。这是一个典型的"类型系统说 OK，运行时却不对"的场景。

2. **这也是 `BaseHTTPMiddleware` 被很多人诟病的原因之一**——它把 `StreamingResponse` 伪装成通用的 `Response`，让你以为可以像操作普通 Response 一样改 `.body`、`.status_code`，但实际上 body 相关的操作行为完全不同。Starlette 的维护者也曾建议复杂场景用纯 ASGI 中间件代替。
