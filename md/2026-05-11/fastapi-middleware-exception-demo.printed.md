# FastAPI 中间件 + 异常处理可运行 Demo

> 来源:`fastapi_web/src/learning_demo/1212.md`(2026-05-11 流水笔记)
> 配套阅读:`interview_answer.md`「FastAPI 异常处理机制」(概念部分)

## 概念

`BaseHTTPMiddleware`、`ExceptionMiddleware`、`ServerErrorMiddleware` 三层在生产中是怎么分工的——通过一个最小可跑 demo + 4 个 curl 场景**亲眼看到**谁兜底了什么。

## 完整 demo

新建 `middleware_demo.py`:

```python
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


app = FastAPI()


# ============================================================
# 用户自定义中间件
# ============================================================
class MyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        print(f"[中间件] 进入 - {request.url.path}")
        try:
            response = await call_next(request)
            print(f"[中间件] 退出 - 状态码 {response.status_code}")
            return response
        except Exception as e:
            # ⚠️ 注意:这里 try 不一定能抓到下游异常,看下文解释
            print(f"[中间件] 抓到异常: {type(e).__name__}: {e}")
            raise

app.add_middleware(MyMiddleware)


# ============================================================
# 注册一个自定义异常处理器(ExceptionMiddleware 负责调度)
# ============================================================
class MyBusinessError(Exception):
    pass


@app.exception_handler(MyBusinessError)
async def my_business_error_handler(request: Request, exc: MyBusinessError):
    print(f"[exception_handler] 抓到 MyBusinessError: {exc}")
    return JSONResponse(
        status_code=400,
        content={"error": "business", "msg": str(exc)},
    )


# ============================================================
# 三个端点,分别触发不同类型的异常
# ============================================================
@app.get("/ok")
async def ok():
    """正常响应"""
    return {"msg": "hello"}


@app.get("/business-error")
async def business_error():
    """业务异常 → 被 @app.exception_handler 注册的处理器接管"""
    raise MyBusinessError("订单不存在")


@app.get("/http-error")
async def http_error():
    """HTTPException → FastAPI 内置处理器接管"""
    raise HTTPException(status_code=404, detail="user not found")


@app.get("/unhandled")
async def unhandled():
    """未处理异常 → ServerErrorMiddleware 兜底"""
    raise ValueError("我是个没人管的异常 💥")


@app.get("/division")
async def division():
    """另一个未处理异常,Python 内置错误"""
    return 1 / 0
```

## 启动

```bash
uv add fastapi uvicorn
uv run uvicorn middleware_demo:app --reload
```

或者:

```bash
pip install fastapi uvicorn
uvicorn middleware_demo:app --reload
```

## 4 种场景,看每种谁兜底

### 场景 1:正常请求

```bash
curl http://127.0.0.1:8000/ok
```

**响应:** `{"msg":"hello"}`

**终端日志:**

```
[中间件] 进入 - /ok
[中间件] 退出 - 状态码 200
```

→ 一切正常,没异常。

### 场景 2:业务异常(被 exception_handler 抓住)

```bash
curl -i http://127.0.0.1:8000/business-error
```

**响应:**

```
HTTP/1.1 400 Bad Request
{"error":"business","msg":"订单不存在"}
```

**终端日志:**

```
[中间件] 进入 - /business-error
[exception_handler] 抓到 MyBusinessError: 订单不存在
[中间件] 退出 - 状态码 400
```

→ **关键观察**:中间件**没看到异常**,只看到状态码 400 的响应。因为 `ExceptionMiddleware`(在你的中间件**内层**)已经把异常转成了正常响应。

### 场景 3:HTTPException(FastAPI 内置)

```bash
curl -i http://127.0.0.1:8000/http-error
```

**响应:**

```
HTTP/1.1 404 Not Found
{"detail":"user not found"}
```

**终端日志:**

```
[中间件] 进入 - /http-error
[中间件] 退出 - 状态码 404
```

→ FastAPI 内置的 `HTTPException` 也是被 `ExceptionMiddleware` 调度的内置 handler 处理,中间件看到的还是正常响应。

### 场景 4:未处理异常(ServerErrorMiddleware 兜底)⭐ 重点

```bash
curl -i http://127.0.0.1:8000/unhandled
```

**响应:**

```
HTTP/1.1 500 Internal Server Error
Internal Server Error
```

**终端日志:**

```
[中间件] 进入 - /unhandled
ERROR:    Exception in ASGI application
Traceback (most recent call last):
  ...
ValueError: 我是个没人管的异常 💥
```

→ **核心发现:**

- 响应是 **500 Internal Server Error**,这就是 `ServerErrorMiddleware` 兜底
- **中间件的 "[中间件] 退出" 没打印** —— 因为异常向上冒泡,中间件的 `await call_next()` 直接抛了
- 终端打印了完整 traceback —— `ServerErrorMiddleware` 在 debug 模式下会打印 traceback

## 进一步实验:中间件自己抓异常返回响应

修改 `MyMiddleware`,把 `raise` 去掉,改成返回自定义响应:

```python
class MyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        print(f"[中间件] 进入 - {request.url.path}")
        try:
            response = await call_next(request)
            print(f"[中间件] 退出 - 状态码 {response.status_code}")
            return response
        except Exception as e:
            print(f"[中间件] 抓到异常: {type(e).__name__}: {e}")
            return JSONResponse(
                status_code=500,
                content={"error": "中间件兜底", "type": type(e).__name__},
            )
```

再访问 `/unhandled`:

```bash
curl -i http://127.0.0.1:8000/unhandled
```

**响应:**

```
{"error":"中间件兜底","type":"ValueError"}
```

**终端日志:**

```
[中间件] 进入 - /unhandled
[中间件] 抓到异常: ValueError: 我是个没人管的异常 💥
```

→ **重要发现**:`BaseHTTPMiddleware` 是**能抓到下游所有未处理异常的**(包括路由函数抛出的)。但这是 `BaseHTTPMiddleware` 的特殊实现,**纯 ASGI 中间件不一定能这样**。

## 总结:每种异常被谁抓住

| 异常类型                          | 触发位置 | 被谁处理                                   | 客户端看到                |
| --------------------------------- | -------- | ------------------------------------------ | ------------------------- |
| 正常返回                          | 路由     | 无                                         | 业务数据                  |
| `MyBusinessError`(注册了 handler) | 路由     | **ExceptionMiddleware** 调度自定义 handler | 400 + 自定义 JSON         |
| `HTTPException`                   | 路由     | **ExceptionMiddleware** 调度内置 handler   | 状态码 + detail           |
| `ValueError`(未注册)              | 路由     | **ServerErrorMiddleware 兜底**             | 500 Internal Server Error |
| 用户中间件内抛异常                | 中间件   | **ServerErrorMiddleware**(因为它在外层)    | 500                       |

## 坑/Why:面试加分点

```python
@app.exception_handler(ValueError)
async def value_error_handler(request, exc):
    return JSONResponse(status_code=400, content={"error": str(exc)})


# 中间件里抛 ValueError 呢?
class BadMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        raise ValueError("中间件里出错!")
```

→ 即使你注册了 `@app.exception_handler(ValueError)`,**中间件抛的 ValueError 它也抓不到**!

**Why:** 因为 `ExceptionMiddleware`(负责调度 `exception_handler`)在中间件**内层**,中间件抛的异常已经"越过"它了,只能被最外层的 `ServerErrorMiddleware` 兜底成 500。

**How to apply:** **中间件里务必自己 try/except,别指望 exception_handler。**

## 面试金句

> "FastAPI 的异常处理有两层 —— `ExceptionMiddleware` 调度 `@app.exception_handler` 注册的业务异常,`ServerErrorMiddleware` 在最外层兜底所有未捕获异常返回 500。我之前踩过一个坑:在中间件里抛了业务异常,**exception_handler 抓不到**,因为它在中间件的内层。后来我们的规范是中间件必须自己处理异常,不能把锅甩给外面的 handler。"
>
> "在生产环境,我们会在 main.py 里注册一个 `@app.exception_handler(Exception)` 顶层兜底,把未知异常转成统一的 500 JSON 格式,**不让 traceback 暴露给前端**。同时配合日志上报到 Sentry,既保证安全,又能追踪问题。"

## 关联

- `interview_answer.md` 二/三章 — 异常处理机制概念解释
- `fastapi_project_directory.md` — 项目目录结构,中间件挂载位置
