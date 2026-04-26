# FastAPI 中间件拆分到独立文件

## 核心问题

`@app.middleware` 装饰器依赖 `app` 实例，无法直接在其他文件中使用，需要特殊组织方式。

---

## 方式 1：注册函数模式（保留装饰器风格）

```python
# middlewares/query_logger.py
from fastapi import Request

def register(app):
    @app.middleware("http")
    async def query_logger(request: Request, call_next):
        page = request.query_params.get("page")
        ...
        return await call_next(request)
```

```python
# main.py
from middlewares import query_logger, body_logger

app = FastAPI()
query_logger.register(app)
body_logger.register(app)
```

---

## 方式 2：类中间件（推荐）

```python
# middlewares/query_logger.py
from starlette.middleware.base import BaseHTTPMiddleware

class QueryLoggerMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        page = request.query_params.get("page")
        ...
        return await call_next(request)
```

```python
# main.py
from middlewares.query_logger import QueryLoggerMiddleware

app = FastAPI()
app.add_middleware(QueryLoggerMiddleware)
```

类中间件支持构造参数：

```python
app.add_middleware(LoggerMiddleware, log_level="DEBUG")
```

---

## 统一注册入口（推荐结构）

```
middlewares/
├── __init__.py        ← 统一注册
├── query_logger.py
└── body_logger.py
```

```python
# middlewares/__init__.py
from .query_logger import QueryLoggerMiddleware
from .body_logger import BodyLoggerMiddleware

def setup_middlewares(app):
    app.add_middleware(QueryLoggerMiddleware)
    app.add_middleware(BodyLoggerMiddleware)
```

```python
# main.py
from middlewares import setup_middlewares
setup_middlewares(app)
```

---

## 注意事项

- `@app.middleware` 是语法糖，底层等价于 `app.add_middleware()`
- 中间件执行顺序：**后注册先执行**（栈结构）
- 类中间件优势：支持构造参数，函数式中间件做不到
