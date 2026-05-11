# Python 后端开发面试准备文档

> **岗位**:Python 开发(武汉·汉阳区,17-30K,5-10年,本科)
> **核心技术栈**:Python / FastAPI / 微服务 / MySQL / PostgreSQL / MongoDB / Redis / Kafka / Docker / K8s / CI-CD
> **加分项**:汽车相关项目经历

---

## 📑 目录

1. [Python 语言基础](#一python-语言基础)
2. [FastAPI 框架(基础篇)](#二fastapi-框架基础篇)
3. [FastAPI 进阶(异步与生产实践)](#三fastapi-进阶异步与生产实践)
4. [微服务架构](#四微服务架构)
5. [MySQL](#五mysql)
6. [PostgreSQL](#六postgresql)
7. [MongoDB](#七mongodb)
8. [Redis](#八redis)
9. [消息队列](#九消息队列kafka--rabbitmq--activemq)
10. [Docker](#十docker)
11. [Kubernetes](#十一kubernetes)
12. [CI/CD 与 DevOps](#十二cicd-与-devops)
13. [系统性能调优与故障排查](#十三系统性能调优与故障排查)
14. [综合项目题](#十四综合项目题汽车物联网场景)

---

## 一、Python 语言基础

### 浅:list 和 tuple 的区别

**答案要点:**

- **可变性**:list 可变(增删改),tuple 不可变。
- **语法**:list 用方括号 `[1, 2, 3]`,tuple 用圆括号 `(1, 2, 3)`。本质上 tuple 是由**逗号**定义的,括号只是消歧义。
- **使用场景**:
  - list:需要修改元素、长度变化的场景(如收集结果、动态列表)。
  - tuple:固定数据、函数多返回值、作为 dict key、作为 set 元素(因为可哈希)。
- **性能**:tuple 占用内存更小,访问略快(CPython 对小 tuple 有缓存池)。

**加分句:** "因为 tuple 不可变所以可哈希,可以作为 dict 的 key 或 set 的元素,这是 list 做不到的。"

---

### 中:GIL 与多线程,CPU/IO 密集型如何选并发方案

**GIL 是什么:**

GIL(Global Interpreter Lock,全局解释器锁)是 CPython 解释器的一把全局互斥锁,**保证同一时刻只有一个线程在执行 Python 字节码**。即使你开了 10 个线程,实际只有 1 个在跑,其他 9 个等待。

**对多线程的影响:**

- **CPU 密集型**:多线程几乎没加速,因为 GIL 让线程必须串行执行字节码。
- **IO 密集型**:线程在等 IO(网络、文件读写)时会**主动释放 GIL**,其他线程能继续执行,所以多线程对 IO 阻塞型任务是有用的。

**并发方案选择:**

| 任务类型      | 推荐方案                                  | 原因                               |
| ------------- | ----------------------------------------- | ---------------------------------- |
| CPU 密集      | `multiprocessing` / `ProcessPoolExecutor` | 多进程绕过 GIL,真并行              |
| IO 密集(传统) | `threading` / `ThreadPoolExecutor`        | 等 IO 时释放 GIL,有效              |
| IO 密集(现代) | **`asyncio` + async/await**               | 单线程协程,无线程切换开销,扩展性强 |

**加分句:** "Python 异步编程通过 event loop 调度原生协程(async def 定义),协程之间通过 await 主动让出控制权,event loop 把 IO 任务委托给底层 selector(epoll/kqueue),IO 完成后回调唤醒协程。这是**协作式多任务**,不是抢占式,所以一旦在协程里调用了阻塞函数,整个 event loop 就卡死。"

---

### 深:Python 内存管理 + 线上内存泄漏排查

#### Python 内存管理三层机制

**1. 引用计数(主要机制)**

每个 Python 对象都有一个 `ob_refcnt` 字段,记录被引用的次数。引用 +1,解引用 -1,**归零立即销毁**。

- 优点:实时回收,确定性强。
- 缺点:**无法处理循环引用**(A 引用 B,B 引用 A,即使外部没人引用,计数也归不了零)。

**2. 分代垃圾回收(补充机制)**

Python 用 `gc` 模块解决循环引用,对象分 0、1、2 三代:

- 新对象进 0 代;熬过一次 GC 进 1 代,再熬过的进 2 代。
- **越年轻的代回收越频繁**(基于"新对象更容易死"的统计假设)。
- GC 遍历对象图,找出"互相引用但无外部引用"的循环引用组,统一回收。

**3. 内存池(小对象优化)**

CPython 的 `pymalloc` 对小于 512 字节的小对象用内存池管理,避免频繁调用 malloc/free。

#### 关键陷阱:`del` 不等于"还给操作系统"

**亲手验证过的事实**:

```python
b = [2] * 9_000_000   # RSS 涨到 139 MiB
del b                  # RSS 不降
gc.collect()           # RSS 还是不降
```

**原因**:`del` 减少引用计数,归零后对象销毁,内存还给 Python 的分配器(pymalloc / glibc malloc)。但分配器**保留内存以便复用**,**不一定归还给操作系统**。`psutil` 看到的 RSS 是 OS 视角,所以不降。

**真正能还给 OS 的方法**:

- 进程退出
- Linux 上调 `malloc_trim`(macOS 没有)
- 用 `multiprocessing.Process` 隔离大内存任务,子进程退出时 OS 强制回收

#### 内存排查工具链(完整 SOP)

**1. 线上无侵入诊断 —— `py-spy`**

```bash
sudo py-spy top --pid <PID>      # 实时看热点函数
sudo py-spy record -o p.svg --pid <PID> --duration 30   # 火焰图
sudo py-spy dump --pid <PID>     # 看当前堆栈(服务卡死时神器)
```

**2. 定位泄漏对象类型 —— `objgraph`**

```python
import objgraph
objgraph.show_growth(limit=10)
# ... 跑一段业务
objgraph.show_growth(limit=10)
# 看哪些类型在持续增长
```

**3. 找根本原因 —— `objgraph.show_backrefs`**

```python
suspects = objgraph.by_type('User')   # 找出某类型所有实例
objgraph.show_backrefs([suspects[0]], max_depth=5, filename='leak.png')
# 反向追踪:谁在持有这个对象?
```

**4. 定位代码行 —— `tracemalloc`**

```python
import tracemalloc
tracemalloc.start()
snap1 = tracemalloc.take_snapshot()
# ... 业务代码
snap2 = tracemalloc.take_snapshot()
for stat in snap2.compare_to(snap1, 'lineno')[:5]:
    print(stat)
```

**5. 本地逐行扫描 —— `memory_profiler`**

```bash
python -m memory_profiler script.py
```

#### 常见泄漏元凶

- **全局变量 / 模块级 cache** 持有大对象
- **`functools.lru_cache(maxsize=None)`** 无上限缓存
- **闭包**捕获大对象
- **ORM session 没关** / 连接池泄漏
- **log handler** 持有 record 引用
- **事件订阅者**没注销

#### 假泄漏(只是高水位)的处理

如果对象数量正常但 RSS 持续涨,这是**分配器高水位**,不是真泄漏。解决方案:

- **Gunicorn `--max-requests 1000 --max-requests-jitter 100`** 让 worker 跑满后自动重启
- 大内存任务用 `multiprocessing` 隔离到子进程

#### 面试金句(背下来)

> "我排查 Python 内存问题有一套完整流程:**线上先 py-spy 无侵入采样**,**objgraph 看对象类型增长**,**show_backrefs 反向追踪持有者**,**tracemalloc 定位代码行**。特别要区分**真泄漏**(对象数量持续涨)和**假泄漏**(分配器高水位)—— 后者用 Gunicorn `--max-requests` worker 定期重启就能缓解。"

#### RSS 概念补充

| 指标                       | 含义                                     |
| -------------------------- | ---------------------------------------- |
| **RSS**(Resident Set Size) | 进程**实际占用的物理内存**               |
| **VSZ / VMS**              | 进程申请的**虚拟内存总量**(可能没真分配) |
| **PSS**                    | RSS 公平版,共享内存按比例分摊            |
| **USS**                    | 只属于这个进程的独占内存                 |

**比喻**:VSZ 是租客申请的房间数,RSS 是实际住进去的房间数。

---

## 二、FastAPI 框架(基础篇)

### 浅:FastAPI 相比 Flask/Django 的优势

**核心优势:**

1. **异步原生支持**:基于 ASGI(Starlette),支持 async/await。
2. **自动生成 OpenAPI 文档**:Swagger UI 和 ReDoc 开箱即用。
3. **类型提示驱动**:用 Python 类型注解做参数解析、请求体校验、响应模型。
4. **Pydantic 数据校验**:声明 schema 后自动校验,失败返回 422。
5. **依赖注入系统**:`Depends` 实现解耦,适合分层架构。
6. **性能**:Starlette + uvicorn,接近 Node.js / Go 的性能。

**为什么"快":**

- **避免 WSGI 同步阻塞**:ASGI 让单 worker 能并发处理数千连接。
- **Pydantic v2** 用 Rust 实现核心校验,性能极高。
- **类型提示编译期解析**:运行时不需要反射。

**面试金句:** "FastAPI 把 Pydantic 的数据校验、Starlette 的 ASGI 框架、Python 的类型提示三者结合,既保证开发体验,又能拿到接近 Go 的吞吐量。"

---

### 中:依赖注入 Depends 工作原理

**核心理念**:实现业务逻辑与公共功能的解耦。数据库会话、用户认证、权限校验这些公共逻辑被抽象成依赖,通过注入方式使用。

**基础用法:**

```python
from fastapi import Depends

async def get_db():
    async with AsyncSession() as session:
        yield session

@app.get("/users/{uid}")
async def get_user(uid: int, db: AsyncSession = Depends(get_db)):
    ...
```

**推荐写法(Annotated,FastAPI 0.95+):**

```python
from typing import Annotated

DbDep = Annotated[AsyncSession, Depends(get_db)]
UserDep = Annotated[User, Depends(get_current_user)]

@app.get("/users/me")
async def me(db: DbDep, user: UserDep):
    ...
```

**用 Annotated 的好处**:可在多个端点复用同一类型别名,避免重复写 `Depends(...)`。

**子依赖**:依赖可以再依赖其他依赖,FastAPI 自动递归解析,先解析底层子依赖,再传给上层。

```python
async def get_token(request: Request): ...
async def get_user(token: str = Depends(get_token)): ...   # 子依赖 get_token
async def get_admin(user: User = Depends(get_user)): ...   # 子依赖 get_user
```

**依赖缓存**:**同一个请求生命周期内,同一个 Depends 默认只执行一次**。多个端点参数引用同一个依赖,只算一次。可通过 `Depends(xxx, use_cache=False)` 关闭。

**典型应用场景:**

| 场景       | 写法                        |
| ---------- | --------------------------- |
| 数据库会话 | `db: DbDep`                 |
| 用户认证   | `user: UserDep`             |
| 权限校验   | `Depends(require_admin)`    |
| 分页参数   | `pagination: PaginationDep` |
| 限流       | `Depends(rate_limit)`       |

---

### 深:请求完整生命周期 + 异常处理

#### 请求生命周期(洋葱模型)

```
请求进来
  → ServerErrorMiddleware(最外层兜底)
    → 用户中间件 C(最后 add 的)
      → 用户中间件 B
        → 用户中间件 A(最先 add 的)
          → ExceptionMiddleware(异常分发)
            → 依赖项(子依赖 → 父依赖)
              → 路由函数(业务)
            → 依赖项 yield 之后的清理
          ← ExceptionMiddleware
        ← 用户中间件 A
      ← 用户中间件 B
    ← 用户中间件 C
  ← ServerErrorMiddleware
响应返回
```

**关键点:**

- **中间件是洋葱模型**:最后 `add_middleware` 的最先执行(最外层)。
- **两层异常中间件**(Starlette 自动加):
  - `ServerErrorMiddleware`(最外层):兜底所有未捕获异常,返回 500。
  - `ExceptionMiddleware`(最内层贴路由):调度 `@app.exception_handler` 注册的处理器。

#### 异常处理机制

```python
@app.exception_handler(MyBusinessError)
async def my_handler(request: Request, exc: MyBusinessError):
    return JSONResponse(status_code=400, content={"error": str(exc)})
```

#### ⚠️ 重要坑(亲手验证过)

**用户中间件抛的异常,`@app.exception_handler` 抓不到**,因为它在中间件**内层**,只能被最外层 `ServerErrorMiddleware` 兜成 500。

**结论:中间件内务必自己 try/except,不能依赖外面的 handler。**

#### 异常分类与处理者对照表

| 异常类型                    | 在哪触发 | 谁处理                                   | 客户端看到          |
| --------------------------- | -------- | ---------------------------------------- | ------------------- |
| 业务异常(注册了 handler)    | 路由     | `ExceptionMiddleware` 调度自定义 handler | 自定义状态码 + JSON |
| `HTTPException`             | 路由     | `ExceptionMiddleware` 调度内置 handler   | 状态码 + detail     |
| 未注册异常(`ValueError` 等) | 路由     | `ServerErrorMiddleware` 兜底             | 500                 |
| 中间件抛异常                | 中间件   | `ServerErrorMiddleware` 兜底             | 500                 |

#### 依赖项的 yield 机制(加分点)

```python
async def get_db():
    async with AsyncSession() as session:
        yield session   # ← 把 session 交给路由
        # ↑ 路由结束后,这里相当于 finally,即使抛异常也会执行
```

**yield 之后的代码 = 清理代码**,这是 FastAPI 做资源管理的核心机制。

#### 面试金句

> "FastAPI 的异常处理是中间件机制的一部分。Starlette 在中间件栈两端自动加了两层:最外层 `ServerErrorMiddleware` 兜底返回 500,最内层 `ExceptionMiddleware` 调度用户注册的 handler。有个坑:用户中间件抛的异常不会被 exception_handler 捕获,因为它在更内层 —— 所以中间件必须自己处理异常。生产环境我会在 main.py 注册一个顶层 `@app.exception_handler(Exception)`,把所有未知异常转成统一的 500 JSON,**不暴露 traceback 给前端**,同时上报到 Sentry。"

---

## 三、FastAPI 进阶(异步与生产实践)

### 浅:def vs async def 路由函数

**核心区别:**

- `def`:同步函数。FastAPI 把它**扔到线程池**(starlette 的 `run_in_threadpool`,默认 40 线程)执行,**不阻塞 event loop**。
- `async def`:原生协程。**直接在 event loop 上跑**。

**怎么选:**

- 函数体里**全是异步代码**(`async with`、`await`、`httpx.AsyncClient`)→ 用 `async def`。
- 函数体里**调用了同步阻塞库**(`requests`、`pymysql`、`time.sleep`)→ **用 `def`**,让 FastAPI 扔到线程池。
- **最坑的情况**:在 `async def` 里调用了同步阻塞函数 → **整个 event loop 卡死**,所有协程停下来等待。

**关于"线程池是并行吗":**

严格说**是并发,不是并行**。因为 GIL 存在,同一时刻只有一个线程跑 Python 字节码。但**IO 阻塞会释放 GIL**,所以线程池对 IO 阻塞同步库依然有效。CPU 密集任务需要 `ProcessPoolExecutor` 才是真并行。

---

### 中:异步数据库 + 同步阻塞库陷阱

#### 异步数据库怎么用

**安装异步驱动**(不是数据库本身,是 Python 异步驱动):

- PostgreSQL → `asyncpg` 或 `psycopg[async]`
- MySQL → `aiomysql` 或 `asyncmy`
- SQLite → `aiosqlite`

**SQLAlchemy 2.0 async 示例:**

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

engine = create_async_engine("postgresql+asyncpg://user:pass@host/db", pool_size=20)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session

@app.get("/users")
async def list_users(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User))
    return result.scalars().all()
```

#### 在 async def 里调用同步阻塞库会怎样

**直接灾难**:整个 event loop 被卡住,**所有其他协程都停下来等**,异步带来的并发收益归零。

**面试铁律:** "Never call a blocking function in an async function."

#### 解决方案

```python
import asyncio

@app.get("/legacy")
async def legacy_endpoint():
    # 错误:这样会卡死 event loop
    # result = requests.get("https://api.example.com").json()

    # 正确:扔到线程池
    result = await asyncio.to_thread(
        requests.get, "https://api.example.com"
    )
    return result.json()
```

或者用 `loop.run_in_executor`:

```python
loop = asyncio.get_running_loop()
result = await loop.run_in_executor(None, blocking_func, arg1, arg2)
```

**更优解:换异步库** —— `requests` → `httpx.AsyncClient`,`pymysql` → `asyncmy`。

---

### 深:生产级 FastAPI 架构设计(30 分钟大题)

这是岗位最可能被深挖的题。完整答案分 8 块讲。

#### 1. 项目目录结构

```
myproject/
├── app/
│   ├── main.py                    # 应用入口,创建 FastAPI 实例
│   ├── core/
│   │   ├── config.py              # Pydantic Settings 配置
│   │   ├── security.py            # JWT、密码哈希
│   │   ├── logging.py             # 日志配置
│   │   └── events.py              # lifespan 启动/关闭事件
│   ├── db/
│   │   ├── session.py             # 异步引擎、session 工厂
│   │   └── base.py                # SQLAlchemy Base
│   ├── models/                    # ORM 表定义
│   │   ├── user.py
│   │   └── order.py
│   ├── schemas/                   # Pydantic 请求/响应模型
│   │   ├── user.py
│   │   └── order.py
│   ├── api/
│   │   ├── deps.py                # 公共依赖(get_db、get_current_user)
│   │   └── v1/
│   │       ├── router.py          # 汇总 v1 路由
│   │       └── endpoints/
│   │           ├── users.py
│   │           └── orders.py
│   ├── services/                  # 业务逻辑层
│   │   ├── user_service.py
│   │   └── order_service.py
│   ├── repositories/              # 数据访问层
│   │   ├── user_repo.py
│   │   └── order_repo.py
│   └── utils/
│       ├── exceptions.py          # 自定义异常
│       └── constants.py
├── tests/
│   ├── conftest.py
│   └── test_users.py
├── alembic/                       # 数据库迁移
├── .env
├── pyproject.toml
└── Dockerfile
```

**分层职责:**

- **endpoints**:HTTP 入参出参,调 services
- **services**:业务逻辑,编排多个 repository
- **repositories**:数据访问,纯 CRUD
- **schemas**:数据契约,跨层传递
- **models**:ORM 数据库映射

#### 2. 配置管理(Pydantic Settings)

```python
# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    APP_NAME: str = "MyApp"
    DEBUG: bool = False

    DATABASE_URL: str
    REDIS_URL: str

    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60

    KAFKA_BROKERS: str

settings = Settings()
```

**关键点**:Pydantic v2 后 `BaseSettings` 拆到独立包 `pydantic-settings`,要单独安装。

#### 3. ORM 选型与异步连接池

```python
# app/db/session.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=20,           # 连接池大小
    max_overflow=10,        # 突发额外连接
    pool_pre_ping=True,     # 取连接前 ping,避免死连接
    pool_recycle=3600,      # 一小时回收一次,避免 MySQL wait_timeout
)

AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)
```

#### 4. 依赖注入分层

```python
# app/api/deps.py
DbDep = Annotated[AsyncSession, Depends(get_db)]
UserDep = Annotated[User, Depends(get_current_user)]
AdminDep = Annotated[User, Depends(require_admin)]

# app/api/v1/endpoints/orders.py
@router.get("/orders/{oid}")
async def get_order(oid: int, db: DbDep, user: UserDep):
    return await order_service.get_order(db, oid, user)
```

#### 5. 统一异常处理

```python
# app/main.py
@app.exception_handler(BusinessException)
async def biz_handler(req, exc):
    return JSONResponse(status_code=400, content={"code": exc.code, "msg": exc.msg})

@app.exception_handler(Exception)
async def fallback_handler(req, exc):
    logger.exception("未捕获异常")
    sentry_sdk.capture_exception(exc)
    return JSONResponse(status_code=500, content={"error": "internal error"})
```

#### 6. 日志 + 链路追踪

**日志(带 trace_id):**

```python
import contextvars
import logging

trace_id_var = contextvars.ContextVar("trace_id", default="-")

class TraceFormatter(logging.Formatter):
    def format(self, record):
        record.trace_id = trace_id_var.get()
        return super().format(record)

@app.middleware("http")
async def trace_middleware(request, call_next):
    trace_id = request.headers.get("X-Trace-Id") or uuid.uuid4().hex[:12]
    token = trace_id_var.set(trace_id)
    try:
        response = await call_next(request)
        response.headers["X-Trace-Id"] = trace_id
        return response
    finally:
        trace_id_var.reset(token)
```

**OpenTelemetry 链路追踪:**

```python
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
FastAPIInstrumentor.instrument_app(app)
# 一行接入,自动给所有路由打 span,数据导出到 Jaeger / Tempo
```

通过 W3C `traceparent` header 跨服务传播,微服务间不用手动传。

#### 7. JWT 鉴权

```python
# app/core/security.py
from jose import jwt
from passlib.context import CryptContext

pwd_ctx = CryptContext(schemes=["bcrypt"])

def create_access_token(data: dict) -> str:
    payload = {**data, "exp": datetime.utcnow() + timedelta(minutes=60)}
    return jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")

def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
```

**JWT 知识点(避坑):**

- JWT 是**格式**(RFC 7519),OAuth 2.0 是**授权协议**(RFC 6749),两者经常一起用但不是一回事。
- FastAPI 推荐 `OAuth2PasswordBearer` + JWT 组合。
- HS256 底层是 **HMAC-SHA256**,不是单纯 SHA-256(HMAC 是带密钥的哈希)。
- JWT 三段:`header.payload.signature`,前两段是 base64 编码(**不是加密**),只有 signature 防篡改。**敏感数据不要放 payload**。

#### 8. 限流 + Prometheus + 部署

**限流**:`slowapi` 库,基于 Redis 滑动窗口。

```python
from slowapi import Limiter
limiter = Limiter(key_func=get_remote_address, storage_uri="redis://...")

@app.get("/api/data")
@limiter.limit("10/minute")
async def data(request: Request):
    ...
```

**Prometheus 监控:**

```python
from prometheus_fastapi_instrumentator import Instrumentator
Instrumentator().instrument(app).expose(app)
# 暴露 /metrics 端点,自动采集请求数、延迟、状态码分布
```

**部署方案:Gunicorn + Uvicorn worker**

```bash
gunicorn app.main:app \
    -w 4 \
    -k uvicorn.workers.UvicornWorker \
    -b 0.0.0.0:8000 \
    --max-requests 1000 \
    --max-requests-jitter 100 \
    --timeout 60 \
    --graceful-timeout 30
```

- `-w 4`:4 个 worker(通常 = CPU 核数)
- `--max-requests`:每个 worker 处理 1000 请求后重启,防内存泄漏高水位
- `--graceful-timeout`:优雅停机预留 30 秒

**优雅停机**:在 lifespan 里关闭连接池、消费者、定时任务:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    await init_kafka_consumer()
    yield
    # shutdown
    await kafka_consumer.stop()
    await engine.dispose()
    logger.info("Graceful shutdown done")

app = FastAPI(lifespan=lifespan)
```

#### 完整面试话术(可背)

> "我设计 FastAPI 生产项目的标准是**四层架构**:路由层只处理 HTTP 入参出参,服务层编排业务逻辑,仓储层做纯 CRUD,schemas 层定义跨层数据契约。
>
> **配置管理**用 Pydantic Settings 从环境变量加载,支持类型校验和默认值。
>
> **依赖注入分层**:用 Annotated 定义 DbDep、UserDep、AdminDep 等别名,端点直接用类型注解注入,既清晰又有 IDE 提示。
>
> **异常处理**注册顶层 handler,把业务异常转 4xx,未知异常转 500 + Sentry 上报,绝不暴露 traceback。
>
> **日志和追踪**用 contextvars 维护 trace_id,中间件生成 ID,日志格式化时自动带上;OpenTelemetry 一行接入自动给路由打 span,Jaeger 看链路。
>
> **JWT 鉴权**用 OAuth2PasswordBearer + python-jose,密码用 bcrypt 哈希。
>
> **部署**用 Gunicorn + Uvicorn worker,4 个 worker,加 `--max-requests` 防内存高水位,lifespan 里做优雅停机,关闭连接池和后台消费者。
>
> **限流**用 slowapi + Redis 滑动窗口,**监控**用 prometheus-fastapi-instrumentator 一行接入暴露 /metrics。"

---

## 四、微服务架构

### 浅:微服务 vs 单体

**微服务优势:**

- 独立部署、独立扩缩容
- 技术栈解耦(不同服务可以用不同语言)
- 故障隔离(一个服务挂不影响其他)
- 团队自治(每个团队负责自己的服务)

**微服务劣势:**

- **分布式复杂度**:网络调用、序列化、超时、重试
- **运维成本高**:服务发现、配置中心、链路追踪、日志聚合
- **数据一致性难**:跨服务事务变成分布式事务
- **测试困难**:集成测试需要拉起多个服务
- **延迟增加**:本地调用变 RPC

**何时拆分:** 团队规模 >50 人,单体代码 >10 万行,部署周期 >1 周,不同模块扩缩容需求差异大。

---

### 中:微服务通信 + 服务发现

**同步通信:**

- **REST/HTTP**:简单通用,适合外部 API。Python 用 `httpx` / `aiohttp`。
- **gRPC**:基于 HTTP/2 + Protobuf,性能高,适合内部服务。
- **GraphQL**:聚合多个数据源,适合 BFF 层。

**异步通信:**

- **消息队列**(Kafka / RabbitMQ):解耦、异步、削峰。
- **事件总线**(EventBridge):事件驱动架构。

**怎么选?**

- 需要立即响应、强一致 → 同步
- 允许最终一致、能接受延迟 → 异步
- 性能敏感的内部服务 → gRPC
- 简单 CRUD 外部服务 → REST

**服务注册与发现:**

- **客户端发现**:服务启动时把自己注册到注册中心(Consul/Eureka/Nacos),客户端从注册中心拿地址。
- **服务端发现**:客户端打到负载均衡器,LB 从注册中心拿后端列表(K8s Service 就是这种模式)。

K8s 环境下通常用 **DNS + Service** 做服务发现,简单可靠。

---

### 深:分布式事务 + 服务雪崩

#### 分布式事务方案对比

| 方案             | 一致性       | 性能         | 复杂度                              | 适用场景             |
| ---------------- | ------------ | ------------ | ----------------------------------- | -------------------- |
| **2PC**          | 强一致       | 差(同步阻塞) | 中                                  | 传统金融系统         |
| **TCC**          | 强一致       | 中           | 高(每个操作要写 try/confirm/cancel) | 资金转账等强一致场景 |
| **Saga**         | 最终一致     | 好           | 中(要写补偿逻辑)                    | 长流程业务(订单创建) |
| **本地消息表**   | 最终一致     | 好           | 低                                  | 互联网业务首选       |
| **最大努力通知** | 最终一致(弱) | 最好         | 最低                                | 通知类业务(发短信)   |

**Saga 模式举例:**

```
订单创建 → 扣库存 → 扣余额 → 发货
   ↓ 任何一步失败,反向补偿:
撤销发货 → 退余额 → 还库存 → 取消订单
```

**本地消息表:**

1. 业务操作 + 写消息到本地表(**同一事务**)
2. 后台任务轮询消息表,发到 MQ
3. 下游消费 + ack
4. 消费失败 → MQ 重试 → 最终一致

**选型考量:**

- 互联网场景**首选本地消息表 + 最终一致**,简单可靠。
- 资金强一致场景考虑 **TCC**(蚂蚁 Seata)。
- 2PC 性能太差,基本不用了。

#### 服务雪崩防护(熔断、降级、限流)

**雪崩**:下游服务慢 → 上游连接积压 → 资源耗尽 → 上游也挂 → 级联崩溃。

**防护手段:**

1. **超时**(必须设):每个 RPC 调用都要有 timeout,不能无限等。
2. **重试 + 退避**:幂等接口可重试,带指数退避避免压垮下游。
3. **限流**:漏桶 / 令牌桶 / Redis 滑动窗口,保护自己。
4. **熔断**(Circuit Breaker):错误率超阈值时直接快速失败,定期半开探测。Python 用 `pybreaker`。
5. **降级**:核心功能保留,非核心功能返回兜底数据。
6. **舱壁隔离**(Bulkhead):不同业务用独立线程池/连接池,避免互相影响。

#### 面试金句

> "微服务下的分布式事务我们一般不用 2PC,性能太差。互联网场景**首选本地消息表 + 最终一致**,业务操作和消息写入放在同一个本地事务里,后台任务发到 MQ,下游消费失败靠 MQ 重试,简单可靠。强一致场景才考虑 TCC。
>
> 服务雪崩防护是**超时、重试、限流、熔断、降级、舱壁**这六板斧。其中最容易被忽视的是超时 —— 很多事故就是因为没设超时,下游慢一秒,上游连接全部挂住。"

---

## 五、MySQL

### 浅:存储引擎对比

| 特性     | InnoDB          | MyISAM         |
| -------- | --------------- | -------------- |
| 事务     | ✅ 支持         | ❌ 不支持      |
| 外键     | ✅              | ❌             |
| 锁粒度   | 行锁            | 表锁           |
| 崩溃恢复 | ✅(redo log)    | ❌             |
| 全文索引 | ✅(5.6+)        | ✅             |
| 适用场景 | OLTP 业务(默认) | 只读统计、归档 |

**结论:5.5+ 默认 InnoDB,99% 业务都用它,MyISAM 几乎不用了。**

---

### 中:索引 + 索引失效

#### 聚簇索引 vs 非聚簇索引

- **聚簇索引**:数据**按主键**物理排序存储,叶子节点就是数据行。InnoDB **主键就是聚簇索引**,一张表只有一个。
- **非聚簇索引**(二级索引/辅助索引):叶子节点存的是**主键值**,需要**回表**到聚簇索引查完整数据。

**回表代价**:二级索引查到主键 → 再用主键查聚簇索引 → 拿完整数据。两次 B+ 树查找。

**覆盖索引**:如果二级索引包含的列就够 SELECT 用,不用回表,效率最高。

#### 最左前缀原则

复合索引 `(a, b, c)` 能命中:

- ✅ `WHERE a=?`
- ✅ `WHERE a=? AND b=?`
- ✅ `WHERE a=? AND b=? AND c=?`
- ✅ `WHERE a=? AND c=?`(用到 a,c 用不上)
- ❌ `WHERE b=?`(没有最左 a)
- ❌ `WHERE b=? AND c=?`

#### 索引失效常见原因

1. **函数 / 表达式**:`WHERE DATE(create_time) = '2024-01-01'` → 失效
2. **隐式类型转换**:字段是 varchar,查的时候 `WHERE phone = 13800000000`(数字)→ 失效
3. **`!=`、`NOT IN`、`OR`**:可能失效(取决于优化器)
4. **`LIKE '%xxx'`**:前缀模糊匹配,失效
5. **违反最左前缀**:见上文
6. **数据分布不均**:索引选择性低(如性别)优化器可能放弃索引,选择全表扫描

---

### 深:MVCC + RR 隔离级别 + 慢查询优化

#### MVCC 机制

**目的**:读写不互相阻塞,提升并发。

**实现要素:**

1. **隐藏字段**(每行):
   - `DB_TRX_ID`:最后修改的事务 ID
   - `DB_ROLL_PTR`:回滚指针,指向 undo log 中的旧版本
   - `DB_ROW_ID`:行 ID

2. **Undo log 版本链**:每次修改记录都把旧值写入 undo log,通过 `DB_ROLL_PTR` 串成链表。

3. **Read View**:事务开启时生成一个"快照",记录当前活跃事务 ID 列表。

**可见性判断:**

读到某行时,顺着 undo log 版本链找到第一个对当前 Read View **可见**的版本:

- 该版本的 `DB_TRX_ID` 是当前事务自己 → 可见
- 该版本的 `DB_TRX_ID` 在 Read View 生成之前已提交 → 可见
- 该版本的 `DB_TRX_ID` 在 Read View 生成时还活跃 → 不可见,继续往前找
- 该版本的 `DB_TRX_ID` 在 Read View 生成之后才开始 → 不可见,继续往前找

#### RC vs RR

- **RC(Read Committed)**:**每次查询**都生成新 Read View → 能读到其他事务的新提交。
- **RR(Repeatable Read)**:**事务开启时**生成 Read View,事务期间都用这个 → 多次读结果一致。

#### RR 是否解决了幻读?

**部分解决:**

- **快照读**(普通 SELECT):MVCC 保证多次读一致,**不会出现幻读**。
- **当前读**(`SELECT ... FOR UPDATE`、`UPDATE`、`DELETE`):用 **Next-Key Lock**(行锁 + 间隙锁)防止幻读。

**仍然可能出现幻读的场景:**

事务 A 快照读(MVCC),事务 B 插入并提交,事务 A 再做当前读(`FOR UPDATE`)→ 看到了 B 插入的新行(因为当前读读最新数据)。

#### 慢查询排查

1. 开启慢查询日志:`slow_query_log = ON`,`long_query_time = 1`
2. 用 `EXPLAIN` 看执行计划,重点看:
   - `type`:`ALL` 全表扫描 ❌,`ref`/`range`/`const` 好
   - `key`:实际用的索引
   - `rows`:扫描行数
   - `Extra`:`Using filesort` / `Using temporary` 是警告
3. 用 `SHOW PROFILE` 看耗时分布
4. 用 `pt-query-digest` 分析慢查询日志

#### EXPLAIN 实测对比(10 万行 users 表)

亲手验证过的 4 条查询的 EXPLAIN 输出,直观看索引和回表的差异:

```
mysql> explain select * from users where id = 50000;
+----+-------+-------+---------+---------+------+----------+-------+
| id | table | type  | key     | key_len | ref  | rows     | Extra |
+----+-------+-------+---------+---------+------+----------+-------+
|  1 | users | const | PRIMARY | 4       | const| 1        | NULL  |
+----+-------+-------+---------+---------+------+----------+-------+

mysql> explain select * from users where email = 'user50000@test.com';
+----+-------+------+-----------+---------+-------+------+-------+
| id | table | type | key       | key_len | ref   | rows | Extra |
+----+-------+------+-----------+---------+-------+------+-------+
|  1 | users | ref  | idx_email | 402     | const | 1    | NULL  |
+----+-------+------+-----------+---------+-------+------+-------+

mysql> explain select id, email from users where email = 'user50000@test.com';
+----+-------+------+-----------+---------+-------+------+-------------+
| id | table | type | key       | key_len | ref   | rows | Extra       |
+----+-------+------+-----------+---------+-------+------+-------------+
|  1 | users | ref  | idx_email | 402     | const | 1    | Using index |  ← 覆盖索引,免回表
+----+-------+------+-----------+---------+-------+------+-------------+

mysql> explain select * from users where name = 'User_50000';
+----+-------+------+------+---------+------+-------+-------------+
| id | table | type | key  | key_len | ref  | rows  | Extra       |
+----+-------+------+------+---------+------+-------+-------------+
|  1 | users | ALL  | NULL | NULL    | NULL | 98469 | Using where |  ← 全表扫描
+----+-------+------+------+---------+------+-------+-------------+
```

配合 `SHOW PROFILES` 看实际耗时:

```
SET profiling = 1;
SELECT * FROM users WHERE id = 50000;
SELECT * FROM users WHERE email = 'user50000@test.com';
SELECT id, email FROM users WHERE email = 'user50000@test.com';
SELECT * FROM users WHERE name = 'User_50000';
SHOW PROFILES;

+----------+------------+----------------------------------------------------------------+
| Query_ID | Duration   | Query                                                          |
+----------+------------+----------------------------------------------------------------+
|        1 | 0.00368450 | select * from users where id = 50000                           |
|        2 | 0.00307200 | select * from users where email = 'user50000@test.com'         |
|        3 | 0.00086925 | select id, email from users where email = 'user50000@test.com' |  ← 最快(覆盖索引)
|        4 | 0.05877525 | select * from users where name = 'User_50000'                  |  ← 最慢(全表扫描)
+----------+------------+----------------------------------------------------------------+
```

**核心发现:**

- `id = 50000`(主键 const):3.7 ms
- `email = ...`(走 idx_email + 回表):3.0 ms
- `email = ...` 但只 SELECT id+email(**覆盖索引免回表**):**0.87 ms** ⚡
- `name = ...`(无索引,全表扫):58.8 ms,**比覆盖索引慢 67 倍**

**结论**:覆盖索引比回表查询快 3-4 倍;全表扫描比覆盖索引慢两个数量级。生产高频查询尽量做成覆盖索引(SELECT 的列被索引完全包含)。

**优化思路:**

- 加索引(覆盖索引最优)
- 避免索引失效(见上)
- 分页深翻页用游标(`WHERE id > last_id LIMIT 20`)
- 大表归档
- 读写分离
- 分库分表(终极方案)

---

## 六、PostgreSQL

### 浅:PostgreSQL vs MySQL

| 维度     | PostgreSQL                    | MySQL             |
| -------- | ----------------------------- | ----------------- |
| 类型系统 | 丰富(JSON、数组、范围、地理)  | 基础              |
| SQL 标准 | 严格遵守                      | 部分支持          |
| 复杂查询 | 强(CTE、窗口函数、Lateral)    | 较弱              |
| 全文搜索 | 原生支持                      | 一般              |
| 并发模型 | 多进程(MVCC)                  | 多线程(MVCC)      |
| 适用场景 | 复杂业务、地理、JSON 重度使用 | 高 QPS、简单 CRUD |

**优先选 PG**:重度 JSON、地理信息(PostGIS)、复杂分析、需要数组/枚举/UUID。

---

### 中:JSONB 索引

**JSON vs JSONB:**

- **JSON**:存原始文本,每次查询要解析。
- **JSONB**:存二进制,查询快,支持索引。**99% 用 JSONB**。

**JSONB 索引:**

```sql
-- GIN 索引,支持包含查询
CREATE INDEX idx_data ON orders USING GIN (data);

-- 查询某个字段
SELECT * FROM orders WHERE data @> '{"status": "paid"}';

-- 表达式索引,精确加速某个字段
CREATE INDEX idx_status ON orders ((data->>'status'));
```

---

### 深:PG MVCC vs MySQL MVCC + VACUUM

**PG 的 MVCC**:

每行有 `xmin`(创建事务 ID)、`xmax`(删除事务 ID),修改 = 标记旧行 xmax + 插入新行。**旧行不立刻删除,等 VACUUM 清理**。

**vs MySQL InnoDB**:

InnoDB 的旧版本放在 **undo log**(独立空间),主表只有最新数据。PG 的旧版本**直接放在主表**,所以表会**膨胀**(bloat),需要 VACUUM 回收空间。

**VACUUM 干什么:**

- 标记可重用空间(普通 VACUUM)
- 物理回收空间归还 OS(`VACUUM FULL`,锁表慎用)
- 更新统计信息(`ANALYZE`)
- 防止事务 ID 回卷(`VACUUM FREEZE`)

**autovacuum**:PG 后台自动跑,但高频更新表可能跟不上,需要手动调参或 `pg_repack` 在线整理。

---

## 七、MongoDB

### 浅:基础概念

| MongoDB           | RDBMS       |
| ----------------- | ----------- |
| 文档 (document)   | 行 (row)    |
| 集合 (collection) | 表 (table)  |
| 字段 (field)      | 列 (column) |
| 嵌入文档          | JOIN        |

**核心特点:**

- 无 schema(灵活)
- 文档可嵌套
- 横向扩展强(分片)
- 弱事务(4.0 才支持多文档事务)

---

### 中:索引 + ESR 原则

**索引类型**:单字段、复合、多键(数组)、文本、地理、TTL、唯一、稀疏。

**ESR 原则**(复合索引设计):

按以下顺序排列字段:

1. **E**quality(等值):`{ status: "active" }`
2. **S**ort(排序):`.sort({ created_at: -1 })`
3. **R**ange(范围):`{ price: { $gt: 100 } }`

```js
// 查询:status = "active" AND price > 100 ORDER BY created_at DESC
// 最优索引:
db.products.createIndex({ status: 1, created_at: -1, price: 1 });
//                         E              S            R
```

---

### 深:副本集 + 分片 + 一致性

**副本集(Replica Set)**:

- 1 Primary + N Secondary + (可选 Arbiter)
- 写只能 Primary,读可路由到 Secondary
- Primary 挂了自动选举新 Primary(Raft)
- 数据复制通过 oplog(类似 binlog)

**分片集群(Sharded Cluster)**:

- **Config Server**(存元数据)+ **mongos**(路由)+ **Shard**(每个 shard 是个副本集)
- 数据按**分片键**(shard key)分布

**分片键怎么选?**

- 基数高(值多样)
- 写入分散(避免热点)
- 查询能带上分片键(否则全分片扫描)

**写关注(Write Concern)**:

- `w=1`:Primary 确认即可(默认,性能好但可能丢)
- `w=majority`:多数节点确认(安全,稍慢)
- `w=0`:不等确认(快,可能丢)
- `j=true`:写 journal 后才返回

**读关注(Read Concern)**:

- `local`:读 Primary 最新(可能未复制完)
- `majority`:读已复制到多数节点的数据(强一致)
- `linearizable`:线性一致性(最严格,最慢)

---

## 八、Redis

### 浅:数据类型 + 应用场景

| 类型           | 应用场景                            |
| -------------- | ----------------------------------- |
| String         | 缓存、计数器(INCR)、分布式锁(SETNX) |
| Hash           | 对象缓存(用户信息)                  |
| List           | 队列、最新消息列表                  |
| Set            | 去重、共同好友(SINTER)              |
| ZSet(有序集合) | 排行榜、延迟队列                    |
| Bitmap         | 签到、活跃用户统计                  |
| HyperLogLog    | UV 统计(允许误差)                   |
| Stream(5.0+)   | 消息队列(替代 List + Pub/Sub)       |

---

### 中:持久化 + 缓存三大坑

**RDB**:

- 周期性快照,fork 子进程写入
- 文件小,恢复快
- 可能丢最后一次快照后的数据

**AOF**:

- 记录每个写命令
- 安全(可配 `appendfsync always/everysec/no`)
- 文件大,恢复慢

**混合持久化**(4.0+):AOF rewrite 时把当前状态以 RDB 格式写入,后续增量用 AOF 格式追加。**推荐生产用混合**。

**缓存三大坑:**

- **缓存穿透**:查不存在的 key 一直打到 DB
  - 解法:**布隆过滤器** / 缓存空值(短 TTL)
- **缓存击穿**:热点 key 过期瞬间大量请求打到 DB
  - 解法:**互斥锁**(只让一个请求回源) / 永不过期 + 后台异步刷新
- **缓存雪崩**:大量 key 同时过期 / Redis 挂掉
  - 解法:**TTL 加随机**(过期时间错开) / Redis 集群 / 限流降级

---

### 深:Redis 部署模式 + 分布式锁 + 大 key/热 key

**部署模式对比:**

| 模式          | 容量     | 高可用           | 适用     |
| ------------- | -------- | ---------------- | -------- |
| 单机          | 单机内存 | ❌               | 开发测试 |
| 主从          | 单机内存 | ❌(主挂手动切)   | 读多写少 |
| 哨兵 Sentinel | 单机内存 | ✅(自动故障转移) | 中小规模 |
| Cluster       | 集群分片 | ✅               | 大规模   |

**分布式锁实现:**

```python
# 错误:SETNX + EXPIRE 两条命令不原子
redis.setnx("lock", "1")
redis.expire("lock", 10)

# 正确:SET 带 NX EX
redis.set("lock", token, nx=True, ex=10)
```

**释放锁要校验 token(防止释放别人的锁):**

```lua
-- Lua 脚本保证原子
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
```

**Redlock 算法争议:**

Redis 作者建议在多个独立 Redis 实例上获取锁,Martin Kleppmann 撰文反驳认为不可靠。生产中**单 Redis 实例 + SET NX EX + Lua 释放**对大部分场景够用了;真正需要强一致用 etcd/ZooKeeper。

**大 key**(value 几 MB+):

- 危害:网络阻塞、内存倾斜、迁移困难
- 排查:`redis-cli --bigkeys`、`MEMORY USAGE key`
- 解法:拆分(hash 拆成多个小 hash)、压缩、过期清理

**热 key**(QPS 几万+):

- 危害:单分片 CPU 打满,流量倾斜
- 排查:`redis-cli --hotkeys`、监控 slowlog
- 解法:本地缓存(进程内 LRU)、多副本读分流、key 加随机后缀分散

---

## 九、消息队列(Kafka / RabbitMQ / ActiveMQ)

### 浅:为什么用 MQ

**三大场景:**

1. **解耦**:生产者不需要知道消费者
2. **异步**:慢操作扔队列,前台立即返回
3. **削峰**:突发流量先入队列,后端按节奏消费

---

### 中:Kafka vs RabbitMQ

| 维度     | Kafka                     | RabbitMQ                 |
| -------- | ------------------------- | ------------------------ |
| 设计哲学 | 日志流(分布式 commit log) | 传统消息队列(AMQP)       |
| 吞吐量   | 百万 QPS                  | 几万 QPS                 |
| 延迟     | ms 级                     | μs 级                    |
| 顺序     | 分区内有序                | 队列内有序               |
| 路由     | 简单(topic + partition)   | 灵活(exchange + binding) |
| 适用     | 日志、大数据、事件流      | 业务消息、RPC、复杂路由  |

**Kafka 核心概念:**

- **Topic**:逻辑分类
- **Partition**:物理分片,**有序的核心单元**,可并行消费
- **Consumer Group**:同组内分摊 partition,**一个 partition 同时只能被一个消费者消费**
- **Offset**:消费位移,可自动/手动提交

---

### 深:消息可靠性三端保证 + Kafka 高吞吐原理

#### 生产端不丢

```python
producer = KafkaProducer(
    acks="all",           # 所有 ISR 副本确认
    retries=3,            # 自动重试
    enable_idempotence=True,  # 幂等生产者,防止重试导致重复
)
```

- `acks=0`:不等确认(快但丢)
- `acks=1`:leader 确认(默认)
- `acks=all`:所有 ISR(in-sync replicas)确认(最安全)

#### Broker 端不丢

- **副本因子 ≥ 3**(`replication.factor = 3`)
- **min.insync.replicas = 2**:至少 2 个副本同步才允许写
- **unclean.leader.election.enable = false**:不让落后副本当 leader

#### 消费端不丢

```python
# 错误:自动提交可能导致消息丢失或重复
consumer = KafkaConsumer(enable_auto_commit=True)

# 正确:消费完业务后手动提交
consumer = KafkaConsumer(enable_auto_commit=False)
for msg in consumer:
    process(msg)        # 业务处理
    consumer.commit()   # 处理完才提交 offset
```

#### 不重复消费(幂等)

**两种思路:**

1. **生产端幂等**:`enable_idempotence=True`,Kafka 自动去重(只防生产重试重复)。
2. **消费端幂等**:业务侧用 message_id 做去重表,或 DB 用 `INSERT ... ON CONFLICT DO NOTHING`。

#### 有序消费

- 同一 key 总进同一 partition → partition 内有序
- 消费端单线程消费一个 partition

#### Kafka 高吞吐量原理

1. **顺序写磁盘**:append-only log,磁盘顺序写接近内存速度
2. **PageCache**:OS 文件缓存,读写不直接落盘
3. **零拷贝**(sendfile):数据从 PageCache 直接发到网卡,不经过用户态
4. **批量发送**:生产端攒批,减少网络往返
5. **分区并行**:多 partition 并行读写

#### 面试金句

> "Kafka 消息可靠性要从生产、Broker、消费三端考虑:**生产端用 acks=all + 幂等生产者**;**Broker 端副本数 ≥3 + min.insync.replicas=2 + 禁用 unclean leader 选举**;**消费端关闭自动提交,业务处理完手动 commit**。不重复消费要靠业务幂等,通常在 DB 用唯一约束去重。
>
> Kafka 高吞吐核心是**顺序写、PageCache、零拷贝、批量、分区并行**这五板斧,所以单机能跑到百万 QPS。"

---

## 十、Docker

### 浅:Docker vs VM,镜像 vs 容器

**Docker vs VM:**

- VM:Hypervisor + GuestOS + 应用(隔离强,启动慢,资源占用大)
- 容器:共享宿主 Kernel + 隔离用户空间(轻量,秒级启动)

**镜像 vs 容器:**

- 镜像:只读模板(类比"类")
- 容器:镜像的运行时实例(类比"对象")

---

### 中:Dockerfile + 镜像优化

**优化手段:**

1. **多阶段构建**:builder 阶段编译,final 阶段只复制产物

```dockerfile
FROM python:3.11 AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
CMD ["python", "app.py"]
```

2. **基础镜像选 slim/alpine**:python:3.11-slim ~100MB,python:3.11 ~900MB
3. **合并 RUN**:减少层数

```dockerfile
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

4. **.dockerignore**:排除 .git、node_modules、**pycache**
5. **利用缓存**:把变动少的步骤放前面(COPY requirements 先于 COPY 代码)

---

### 深:底层原理 + 网络

**Docker 三大底层技术:**

1. **Namespace**(隔离):
   - PID(进程)、NET(网络)、MNT(挂载点)、UTS(主机名)、IPC、USER
   - 每个容器有自己的命名空间,看不到宿主和其他容器

2. **Cgroups**(限制):
   - CPU、内存、磁盘 IO 配额
   - `docker run --memory=512m --cpus=1`

3. **UnionFS**(文件系统):
   - 镜像分层,共享相同层节省空间
   - 写时复制(Copy-on-Write)

**网络模式:**

| 模式         | 说明                                |
| ------------ | ----------------------------------- |
| bridge(默认) | 容器在虚拟网桥 docker0 上,有独立 IP |
| host         | 共用宿主网络栈,无隔离               |
| none         | 无网络                              |
| container    | 共用其他容器的网络栈                |
| overlay      | 跨主机通信(Swarm/K8s)               |

**跨主机通信**(K8s 中):

- **CNI 插件**(Flannel/Calico/Cilium)实现 Pod 跨节点通信
- 通过 VXLAN 隧道、BGP 路由、eBPF 等技术

---

## 十一、Kubernetes

### 浅:核心组件

**Master 节点:**

- **kube-apiserver**:所有操作的入口(REST API)
- **etcd**:分布式 KV 存储,保存集群状态
- **kube-scheduler**:决定 Pod 调度到哪个 Node
- **kube-controller-manager**:控制器(Deployment、ReplicaSet、StatefulSet 等)

**Node 节点:**

- **kubelet**:管理 Pod 生命周期
- **kube-proxy**:实现 Service 流量转发(iptables/IPVS)
- **容器运行时**(containerd/CRI-O)

**核心资源:**

- **Pod**:最小调度单位,一个或多个容器
- **Deployment**:无状态应用,管理 ReplicaSet 和滚动更新
- **StatefulSet**:有状态应用(DB)
- **Service**:稳定的访问入口
- **ConfigMap / Secret**:配置和密钥
- **Ingress**:外部访问入口(L7 路由)

---

### 中:Service 类型 + Pod 通信

**Service 类型:**

| 类型            | 说明               | 场景           |
| --------------- | ------------------ | -------------- |
| ClusterIP(默认) | 集群内部访问       | 内部服务间通信 |
| NodePort        | 每个 Node 开放端口 | 调试           |
| LoadBalancer    | 云厂商 LB          | 暴露公网       |
| Ingress         | L7 路由(域名/路径) | 多服务共享 LB  |

**Pod 通信:**

- **同 Pod 内容器**:共享 network namespace,localhost 互访
- **同 Node 跨 Pod**:走宿主网桥(cni0/docker0)
- **跨 Node Pod**:通过 CNI(Flannel VXLAN / Calico BGP)
- **Pod → Service**:kube-proxy 配 iptables/IPVS 规则,Service ClusterIP 是虚拟 IP
- **外部 → Pod**:Ingress / NodePort / LoadBalancer

---

### 深:滚动更新 + HPA + 故障排查

#### 滚动更新

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1 # 最多多创建 1 个 Pod
      maxUnavailable: 0 # 不允许有不可用 Pod
```

**回滚:**

```bash
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp --to-revision=2
```

#### HPA(水平自动扩缩容)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

**工作原理:**

1. **metrics-server** 采集 Pod CPU/内存
2. HPA controller 每 15s 检查一次
3. CPU > 70% → 扩容,< 50% → 缩容
4. 计算公式:`desiredReplicas = ceil(currentReplicas × (currentMetric / targetMetric))`

**自定义指标**:通过 Prometheus Adapter 支持 QPS、队列长度等。

#### 常见 Pod 故障排查 SOP

```bash
# 1. 看状态
kubectl get pod -o wide

# 2. 看事件(80% 问题在这看到)
kubectl describe pod <pod-name>

# 3. 看日志
kubectl logs <pod-name>
kubectl logs <pod-name> --previous   # 看 crash 前的日志

# 4. 进容器排查
kubectl exec -it <pod-name> -- /bin/sh
```

**常见状态及解决:**

| 状态               | 原因                | 排查方向                                 |
| ------------------ | ------------------- | ---------------------------------------- |
| `Pending`          | 资源不足、调度失败  | `kubectl describe` 看 Events             |
| `ImagePullBackOff` | 镜像拉不到          | 检查镜像名、私有仓库 secret              |
| `CrashLoopBackOff` | 容器启动后又挂      | `kubectl logs --previous`                |
| `OOMKilled`        | 内存超限被杀        | 调大 `resources.limits.memory`           |
| `Evicted`          | Node 资源不足被驱逐 | 检查 Node 资源、PriorityClass            |
| `Init:Error`       | initContainer 失败  | `kubectl logs <pod> -c <init-container>` |
| `Running` 但不响应 | 程序问题            | 进容器用 py-spy dump 看堆栈              |

---

## 十二、CI/CD 与 DevOps

### 浅:CI/CD 概念

- **CI(Continuous Integration)**:代码合并到主分支前自动测试。
- **CD(Continuous Delivery)**:自动构建产物到可发布状态,**人工触发部署**。
- **CD(Continuous Deployment)**:自动部署到生产,**全自动**。

---

### 中:Python CI/CD 流程

**典型 GitLab CI 流程:**

```yaml
stages:
  - lint
  - test
  - build
  - deploy

lint:
  stage: lint
  script:
    - ruff check .
    - mypy app

test:
  stage: test
  script:
    - pytest --cov=app --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)/'

build:
  stage: build
  script:
    - docker build -t registry.example.com/myapp:$CI_COMMIT_SHA .
    - docker push registry.example.com/myapp:$CI_COMMIT_SHA

deploy_staging:
  stage: deploy
  script:
    - kubectl set image deployment/myapp app=registry.example.com/myapp:$CI_COMMIT_SHA
  only:
    - main
```

---

### 深:发布策略 + 数据库变更

**蓝绿发布**:

- 新版本(绿)和旧版本(蓝)同时存在,流量切换一次性
- 优点:回滚快(切回去就行)
- 缺点:需要双倍资源

**金丝雀发布**(Canary):

- 先把新版本部署到 1% 流量,观察指标
- 逐步扩大到 5% → 25% → 100%
- 优点:风险小
- K8s 实现:用 Ingress 权重 / Service Mesh(Istio)

**特性开关**(Feature Flag):

- 代码上线但功能默认关闭,通过配置中心(如 Apollo/Nacos)动态开启
- 优点:发布和上线解耦,可灰度到指定用户

**数据库变更(DDL)的安全发布:**

1. **向后兼容**:加字段而非改字段,新代码兼容老数据
2. **分阶段**:
   - 阶段 1:加字段(代码不依赖)
   - 阶段 2:写入双字段
   - 阶段 3:迁移老数据
   - 阶段 4:代码切到读新字段
   - 阶段 5:删除老字段
3. **大表变更工具**:`gh-ost` / `pt-online-schema-change`(MySQL),避免锁表

---

## 十三、系统性能调优与故障排查

### 浅:接口变慢排查思路

**自顶向下:**

1. 看监控:接口 P99 延迟、QPS、错误率
2. 看分布:慢在哪一层(网关、应用、DB、缓存、下游)
3. 看链路:OpenTelemetry / Jaeger 看 trace
4. 看日志:错误日志、慢查询日志

**常见原因:**

- 数据库慢查询(没索引、N+1)
- 缓存失效
- 下游服务慢(网络、超时)
- GIL 阻塞(异步代码里调了同步库)
- GC / 内存压力

---

### 中:Python 性能分析工具

| 工具              | 用途                         |
| ----------------- | ---------------------------- |
| `cProfile`        | 标准库,函数级 CPU 分析       |
| `py-spy`          | **无侵入**采样 + 火焰图      |
| `line_profiler`   | 逐行 CPU 分析                |
| `memory_profiler` | 逐行内存分析                 |
| `tracemalloc`     | 内存快照对比                 |
| `objgraph`        | 对象引用图,排查泄漏          |
| `scalene`         | 现代综合分析器(CPU+内存+GPU) |

---

### 深:CPU 100% / OOM 完整排查流程(亲手验证过)

#### CPU 飙高到 100%

**Step 1:无侵入定位**

```bash
sudo py-spy top --pid <PID>
# 看哪个函数 %Own 最高
```

**Step 2:火焰图采样**

```bash
sudo py-spy record -o profile.svg --pid <PID> --duration 30
open profile.svg
# 看最宽的"平顶",就是瓶颈
```

**Step 3:看当前堆栈(服务卡死时)**

```bash
sudo py-spy dump --pid <PID>
```

**线程标签含义:**

- `(active+gil)`:正在跑 Python 字节码,真在烧 CPU
- `(active)`:在跑但没 GIL(可能在等锁)
- `(idle)`:在 sleep 或等 IO

**常见原因:**

- 死循环 / 算法 O(n²)
- 异步代码里调了同步阻塞库
- 正则没缓存(每次 re.compile)
- 大对象 JSON 序列化(换 orjson)

#### 内存持续上涨直到 OOM

**Step 1:确认是不是真泄漏**

```python
import objgraph
objgraph.show_growth(limit=10)
# ... 跑一段业务
objgraph.show_growth(limit=10)
# 看哪些类型只涨不跌
```

**Step 2:定位泄漏对象的持有者**

```python
suspects = objgraph.by_type('User')
objgraph.show_backrefs([suspects[0]], max_depth=5, filename='leak.png')
# 反向追踪谁在持有
```

**Step 3:定位分配代码行**

```python
import tracemalloc
tracemalloc.start()
snap1 = tracemalloc.take_snapshot()
# 跑业务
snap2 = tracemalloc.take_snapshot()
for stat in snap2.compare_to(snap1, 'lineno')[:5]:
    print(stat)
```

**Step 4:区分真假泄漏**

- **真泄漏**:对象数量持续涨 → 修代码
- **假泄漏**(分配器高水位):对象数稳定但 RSS 涨 → Gunicorn `--max-requests` 让 worker 定期重启

#### 完整面试话术(背)

> "我排查 CPU 飙高的标准流程:**py-spy top 实时定位热点,record 生成火焰图分析,dump 看当前堆栈**。看 `(active+gil)` 标签找真在烧 CPU 的线程。常见原因是异步代码里调了同步阻塞库,导致 event loop 卡死。
>
> 内存问题先用 RSS 区分真假泄漏,**真泄漏用 objgraph.show_growth 找类型,show_backrefs 找持有者,tracemalloc 定位代码行**。假泄漏用 Gunicorn `--max-requests` 让 worker 定期重启缓解。
>
> 整套工具最大优势是**对运行中的进程零侵入,不需要改代码不需要重启**,这是生产环境的关键。"

---

## 十四、综合项目题(汽车物联网场景)

### 浅:介绍最有挑战的项目

**STAR 结构:**

- **S**ituation:背景(业务规模、技术挑战)
- **T**ask:你的角色和职责
- **A**ction:具体做了什么(技术选型、架构设计、关键决策)
- **R**esult:结果(性能、稳定性、业务价值的量化指标)

**示例话术框架:**

> "我做过一个 [汽车 IoT 平台/订单系统/xxx],主要是 [核心业务]。规模大概 [QPS / 数据量 / 用户量]。
>
> 我作为 [后端核心开发/技术负责人],主要负责 [业务模块 + 架构设计]。
>
> 技术栈是 [FastAPI + PG + Kafka + Redis + K8s]。
>
> 最有挑战的是 [某个具体技术难点],我们的解决方案是 [具体方案],最终达到 [量化指标,如 P99 < 100ms、月度可用性 99.95%]。"

---

### 中:微服务拆分 + 数据库设计

**拆分原则:**

- **DDD 限界上下文**:按业务领域拆(用户域、订单域、库存域)
- **数据所有权**:每个服务独占自己的库
- **变更频率相近的放一起**
- **避免过度拆分**(早期单体即可,有痛点再拆)

**数据库设计:**

- 主键:雪花 ID / UUID,不用自增(分库分表友好)
- 时间字段:`created_at` / `updated_at`(必备,审计 + 排序)
- 软删除:`deleted_at`(慎用,加复杂度)
- 状态字段:用枚举值 + 状态机
- 大字段独立表:varchar(1000+) 单独存,主表只存索引列

---

### 深:车联网平台架构设计(完整方案)

#### 业务需求

- 百万级车辆实时数据上报(位置、速度、油量、告警)
- 数据频率:每车每 10 秒上报一次 → **峰值 100k QPS**
- 实时告警(超速、电量低、碰撞)
- 历史轨迹查询、统计分析

#### 架构分层

```
车端 (TBox)
   ↓ MQTT (持久连接)
接入层:MQTT Broker (EMQX 集群)
   ↓
消息队列:Kafka (按 vin 分区,保证同车有序)
   ↓
   ├→ 实时处理:Flink (告警检测、状态聚合)
   ├→ 落库:消费者写入时序库 (InfluxDB / TimescaleDB)
   └→ 离线分析:落 HDFS/S3,Spark 批处理
   ↓
存储层
   ├ TimescaleDB:实时数据 + 时序查询
   ├ PostgreSQL:业务数据(车辆、用户、订单)
   ├ Redis:车辆最新状态、热点缓存
   └ ES:日志、全文搜索
   ↓
应用层
   ├ FastAPI:对外 REST API
   ├ WebSocket / SSE:推送告警、实时位置
   └ gRPC:内部服务间通信
   ↓
监控
   ├ Prometheus + Grafana:指标
   ├ Jaeger:链路追踪
   └ ELK:日志聚合
```

#### 关键技术决策

**1. 接入层选 MQTT 不选 HTTP**

- 持久连接,省去频繁握手
- QoS 0/1/2 满足不同可靠性需求
- 消息格式小,适合移动网络

**2. Kafka 分区策略**

- 按 `vin`(车辆识别号)哈希分区
- **保证同车数据有序**(同 vin 进同 partition)
- 分区数 = 峰值 QPS / 单分区吞吐(约 10k)= 10 个起步,预留扩容

**3. 时序数据选 TimescaleDB**

- PostgreSQL 扩展,SQL 兼容
- 自动分区(按时间)
- 数据压缩(节省 90% 空间)
- 也可选 InfluxDB,但 SQL 生态更弱

**4. 实时告警**

- Flink 流处理(状态管理 + 窗口)
- 或者 Kafka Streams 轻量方案
- 简单场景:消费者 + Redis 状态缓存

**5. 高并发写入**

- Kafka 分区并行
- 时序库批量写(buffer + 定时 flush)
- 写入冷热分离:热数据 SSD,冷数据归档 S3

**6. 高可用**

- MQTT Broker 集群
- Kafka 副本因子 3
- 数据库主从 + 读写分离
- K8s 部署,Pod 自动重建
- 多可用区部署

**7. 数据一致性**

- 接入层至少一次(at-least-once)
- 消费端幂等:用 `(vin, timestamp)` 做唯一约束

#### 面试金句(完整方案讲解)

> "车联网平台要支持百万车辆 10s 上报一次,峰值 100k QPS。我会这样分层:
>
> **接入层用 MQTT** 不用 HTTP,EMQX 集群支撑长连接,QoS 1 保证至少一次送达。
>
> **缓冲层用 Kafka**,按 vin 哈希分区保证同车有序,10 分区起步预留扩容。这一层也是削峰,后端来不及处理时车端不会被拒绝。
>
> **实时处理**用 Flink 做告警检测和状态聚合,也可以简化成 Python 消费者 + Redis 状态。
>
> **存储分两块**:时序数据进 TimescaleDB,自动分区 + 压缩;业务数据进 PostgreSQL。Redis 缓存每车最新状态,API 查询不打到时序库。
>
> **API 层用 FastAPI**,实时推送用 WebSocket / SSE。
>
> **高可用方面**:Kafka 副本 3,DB 主从,K8s 部署 Pod 自动重建,多 AZ 容灾。
>
> **数据一致性**:接入至少一次,消费端用 (vin, timestamp) 唯一约束做幂等。
>
> 整套架构在 [假设性能指标,如:写入 10W QPS,P99 < 200ms,99.95% 可用性] 下稳定运行。"

---

## 📋 面试当天 Checklist

### 自我介绍准备(2 分钟)

- 工作经验年限
- 最熟悉的技术栈
- 最有亮点的 1-2 个项目(STAR)
- 求职动机

### 高频问题准备答案

- [ ] 上家公司离职原因
- [ ] 期望薪资
- [ ] 5 年职业规划
- [ ] 最大的优势和不足
- [ ] 为什么投我们公司

### 反问环节(必备 2-3 个)

- 团队规模和技术栈?
- 目前最大的技术挑战?
- 评审/晋升机制?
- 这个岗位 3-6 个月的核心目标?

### 必查信息

- [ ] 公司主营业务
- [ ] 最近新闻动态
- [ ] 团队规模
- [ ] 加分项"汽车相关项目"准备 1-2 个相关经验或学习

---

## 🎯 核心面试技巧

1. **诚实**:不会就说不会,但要给出"如果遇到我会怎么学"。胡说会被一连串追问拆穿。

2. **结构化表达**:用"先说结论,再展开"或"分三点讲"的结构,比想到哪说到哪好十倍。

3. **量化**:能说数字就说数字。"性能提升了" vs "P99 从 800ms 降到 80ms"。

4. **讲"为什么"**:不要只讲"用了什么",要讲"为什么选它不选另一个"。

5. **预埋钩子**:故意提一个有趣的点("我们后来踩了个坑..."),诱导面试官深入问,把节奏抓在自己手里。

6. **管理预期**:遇到不会的题,说"这个我没深入研究过,但根据 [相关知识] 我猜可能是 [推测]",比直接 "不会" 好。

---

**祝面试顺利 🚀**
