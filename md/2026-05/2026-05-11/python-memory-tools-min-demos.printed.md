# Python 内存管理 + 工具链最小 Demo 合集

> 来源:`fastapi_web/src/learning_demo/main_reply_2.md`(2026-05-11 面试 TODO 答案集)
> 配套阅读:`interview_answer.md`「Python 内存管理 + 工具链 SOP」(概念部分)

## 概念

`tracemalloc`、`memory_profiler`、`objgraph`、`py-spy`、`gc.get_objects` 五个内存工具,以及"引用计数 / 循环引用 / 分代回收 / weakref"四个核心机制的**最小可运行 demo**。每个 demo 后给出一句话定位。

---

## 一、内存排查工具链 5 个最小 demo

### ① tracemalloc —— 标准库自带,定位"哪一行分配了多少内存"

```python
import tracemalloc

tracemalloc.start()

snap1 = tracemalloc.take_snapshot()

# 模拟可疑代码
leak = []
for i in range(100000):
    leak.append("x" * 100)

snap2 = tracemalloc.take_snapshot()

# 对比两个快照,按代码行排序
top_stats = snap2.compare_to(snap1, 'lineno')
for stat in top_stats[:3]:
    print(stat)
```

输出会告诉你:**`xxx.py:10: size=+9.5 MiB, count=+100000`** —— 第 10 行多分配了 9.5MB,这就是泄漏点。

**一句话:tracemalloc 告诉你"哪行代码涨了多少内存"。**

### ② memory_profiler —— 第三方库,按函数/按行看内存

```python
# pip install memory-profiler
from memory_profiler import profile

@profile
def my_func():
    a = [1] * 1000000
    b = [2] * 9000000
    del b
    return a

if __name__ == "__main__":
    my_func()
```

运行 `python -m memory_profiler script.py`,输出长这样:

```
Line #    Mem usage    Increment   Line Contents
================================================
     3     38.8 MiB     38.8 MiB   @profile
     4                             def my_func():
     5     46.5 MiB      7.6 MiB       a = [1] * 1000000
     6    115.9 MiB     69.4 MiB       b = [2] * 9000000
     7     46.6 MiB    -69.4 MiB       del b
```

**一句话:memory_profiler 给你的函数加装饰器,逐行打印内存变化,适合本地调试。**

vs tracemalloc:tracemalloc 是程序级的"前后对比",memory_profiler 是函数级的"逐行扫描"。

### ③ objgraph —— 看对象引用关系,定位循环引用

```python
# pip install objgraph
import objgraph

class A:
    pass

class B:
    pass

a = A()
b = B()
a.ref = b
b.ref = a   # ← 循环引用

# 看当前内存里哪些类型的对象最多
objgraph.show_most_common_types(limit=5)

# 画出 a 对象的引用关系图(需要 graphviz)
objgraph.show_refs([a], filename='refs.png')
```

`show_most_common_types()` 会输出:

```
dict       1234
function   567
A          1
B          1
```

如果你发现某个自定义类的实例数量在涨却从来不下降,**就是它在泄漏**。

**一句话:objgraph 回答"内存里到底攒了什么对象,它们被谁引用着"。**

### ④ py-spy —— 线上不停服,挂上去采样

```bash
# pip install py-spy
# 找到 Python 进程 PID
ps aux | grep python

# 实时看哪个函数在烧 CPU(像 top)
py-spy top --pid 12345

# 采样 30 秒,生成火焰图
py-spy record -o profile.svg --pid 12345 --duration 30
```

**最关键的优势:不需要改代码、不需要重启服务、对线上业务零侵入。** 这就是为什么生产事故首选它。

**一句话:py-spy 是线上服务的"听诊器",不动病人就能听出问题。**

### ⑤ gc.get_objects() —— 标准库,看 GC 跟踪的所有对象

```python
import gc

# 触发一次回收
gc.collect()

# 看 GC 跟踪着的所有对象总数
print(len(gc.get_objects()))

# 看有没有"无法回收的垃圾"(通常是带 __del__ 的循环引用)
print(gc.garbage)
```

**一句话:gc 模块用来手动检视垃圾回收器的状态,平时不用,排查"明明 del 了内存却不降"的时候用。**

### 工具链话术(面试可背)

> "排查 Python 内存泄漏,我的工具链是分层的:**线上先用 py-spy 无侵入采样定位嫌疑进程**;**程序内部用 tracemalloc 做前后快照对比,定位到具体代码行**;**怀疑循环引用就上 objgraph 看引用关系图**;**本地复现时用 memory_profiler 逐行扫描**。`gc.get_objects()` 和 `gc.garbage` 作为辅助手段,排查 GC 无法回收的对象。"

---

## 二、内存管理四点最小 demo

### ① 引用计数

```python
import sys

a = [1, 2, 3]
print(sys.getrefcount(a))   # 2 (a 本身 + getrefcount 临时引用)

b = a
print(sys.getrefcount(a))   # 3

del b
print(sys.getrefcount(a))   # 2
```

**体感:每多一个名字指向对象,引用计数就 +1。**

### ② 循环引用 + GC 回收

```python
import gc

class Node:
    def __init__(self, name):
        self.name = name
    def __del__(self):
        print(f"{self.name} 被回收")

a = Node("A")
b = Node("B")
a.ref = b
b.ref = a   # ← 循环引用

del a
del b
# 此时虽然 a、b 名字没了,但它们互相引用,引用计数 != 0,不会被立即回收

print("--- 手动触发 GC ---")
gc.collect()   # ← 这里才会回收
print("--- GC 结束 ---")
```

输出:

```
--- 手动触发 GC ---
A 被回收
B 被回收
--- GC 结束 ---
```

**体感:循环引用必须等 GC 跑一轮才能回收,引用计数搞不定。**

### ③ 分代回收 —— 看三代阈值

```python
import gc

print(gc.get_threshold())
# (700, 10, 10)
# 含义:0 代分配数 > 700 触发 0 代回收
#       0 代回收 10 次后触发 1 代回收
#       1 代回收 10 次后触发 2 代回收

print(gc.get_count())
# (412, 3, 1)
# 当前三代里各有多少未回收对象
```

**体感:Python 把对象按"活了多久"分三代,新对象死得快,老对象很少检查。**

### ④ weakref 弱引用 —— 避免循环引用

```python
import weakref

class Node:
    def __init__(self, name):
        self.name = name
    def __del__(self):
        print(f"{self.name} 被回收")

a = Node("A")
b = Node("B")
a.ref = b
b.ref = weakref.ref(a)   # ← B 用弱引用指向 A,不增加 A 的引用计数

del a   # A 立即被回收(不依赖 GC)
# 输出:A 被回收
```

**体感:弱引用让 B 能"看"到 A,但不"拽住"A,A 该死就死。常用于缓存、观察者模式。**

---

## 三、async def 路由 / 并发 vs 并行答疑

### Q1:FastAPI 端点可以用 `def` 声明吗?

**可以,而且完全合法。** 这是 FastAPI 的官方推荐用法之一。FastAPI 内部判断你的函数是不是协程(用 `asyncio.iscoroutinefunction`):

- 是协程 → 直接放到 event loop 跑
- 不是协程 → 用 `run_in_threadpool` 扔到**默认线程池**(starlette 用 AnyIO 管理,默认 40 个线程)

```python
from fastapi import FastAPI
import time

app = FastAPI()

@app.get("/sync")
def sync_route():
    time.sleep(2)   # 同步阻塞,但 FastAPI 把它扔线程池,不会卡 event loop
    return {"ok": True}

@app.get("/async")
async def async_route():
    import asyncio
    await asyncio.sleep(2)   # 异步等待
    return {"ok": True}
```

**两种都对,选哪个看你函数体里调用的是同步库还是异步库。**

### Q2:扔到线程池算并行编程吗?

**严格说,在 CPython 里它是"并发",不是"并行"。** 原因就是 GIL。

| 概念                  | 含义                                    |
| --------------------- | --------------------------------------- |
| **并发(Concurrency)** | 多个任务交替推进,看起来同时在跑         |
| **并行(Parallelism)** | 多个任务**真的同时**在多个 CPU 核心上跑 |

GIL 保证**同一时刻只有一个线程在执行 Python 字节码**。所以即使你开了 40 个线程,也是并发不是并行。

**但是!** 线程池在以下场景依然有用:

- **IO 阻塞会释放 GIL**:`time.sleep`、文件读写、`requests` 发请求时,底层 C 调用会释放 GIL,其他线程能继续跑。
- **CPU 密集型则没用**:多线程在 CPU 密集任务上没有加速效果,需要换 `ProcessPoolExecutor` 才是真并行。

**面试话术:**

> "FastAPI 的 `def` 路由会被扔到线程池执行。但因为 GIL 的存在,这不是真正的并行,而是并发 —— 同一时刻只有一个线程在跑 Python 字节码。不过对于 IO 阻塞型任务,线程在等 IO 时会释放 GIL,其他线程能继续跑,所以线程池对 IO 阻塞的同步库依然有效。CPU 密集型任务则需要进程池才能真正并行。"

---

## 四、HMAC-SHA256 念法

**正式念法:** "H-M-A-C dash S-H-A two-five-six"

中文环境下大家是这么念的:

- 💬 口语化:**"H-mac SHA-256"**(HMAC 读成"H-mac",像 mac 地址那个 mac)
- 💬 也有人读成:**"H-M-A-C SHA 二五六"** 或 **"HMAC sha 256"**

**面试里推荐这么说**:"HS256 算法,底层是 HMAC SHA-256,HMAC 是带密钥的哈希消息认证码"。

读音示范:

- HMAC = **"艾曲-mac"** 或 **"H-mac"**(两个读法都常见,后者更口语)
- SHA-256 = **"sha 二五六"** 或 **"sha two-five-six"**

**最稳的说法**:"HS256 是 HMAC 配合 SHA-256 的算法"。把缩写展开讲,既显得专业,又不会读错。

---

## 五、Starlette 双层异常中间件细节

Starlette 内部有两个特殊的中间件,**FastAPI 启动时会自动加上,排在你自己的中间件最外层和最内层**:

```
请求进来
  ↓
ServerErrorMiddleware       ← 最外层,捕获 500 错误,返回 500 响应
  ↓
你的中间件 (按 add 顺序的反向,洋葱模型)
  ↓
ExceptionMiddleware         ← 最内层,处理 exception_handlers 注册的异常
  ↓
路由处理函数(执行依赖、业务)
```

**两层异常中间件的分工:**

| 中间件                  | 位置             | 负责                                                                                                                    |
| ----------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `ServerErrorMiddleware` | 最外层           | 兜底,捕获所有没被处理的异常,返回 500。debug 模式下打印完整 traceback 给前端。                                           |
| `ExceptionMiddleware`   | 最内层(贴着路由) | 处理你用 `@app.exception_handler(XxxException)` 注册的异常,比如 `HTTPException`、`RequestValidationError`、自定义异常。 |

**完整生命周期:**

```
请求进来
  → ServerErrorMiddleware(兜底层)
    → 用户中间件 C
      → 用户中间件 B
        → 用户中间件 A
          → ExceptionMiddleware(异常分发层)
            → 依赖项注入(子依赖 → 父依赖)
              → 路由函数(业务逻辑)
            → 依赖项 yield 之后的清理代码
          ← ExceptionMiddleware
        ← 用户中间件 A
      ← 用户中间件 B
    ← 用户中间件 C
  ← ServerErrorMiddleware
响应返回
```

**重要的坑**:因为 `ExceptionMiddleware` 在用户中间件**内层**,如果你的自定义中间件里抛了异常,**`exception_handler` 抓不到**,只会被最外层 `ServerErrorMiddleware` 兜底成 500。所以中间件里务必自己用 try/except。

---

## 六、日志 + OpenTelemetry 最小 demo

### 最小可运行 demo —— 日志带 trace_id

```python
# pip install fastapi uvicorn structlog
import uuid
import logging
import contextvars
from fastapi import FastAPI, Request

# 1. 用 contextvars 存 trace_id (协程安全)
trace_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("trace_id", default="-")

# 2. 自定义 Formatter,从 contextvars 取 trace_id
class TraceFormatter(logging.Formatter):
    def format(self, record):
        record.trace_id = trace_id_var.get()
        return super().format(record)

# 3. 配置日志
handler = logging.StreamHandler()
handler.setFormatter(TraceFormatter(
    "%(asctime)s [%(levelname)s] [trace=%(trace_id)s] %(name)s - %(message)s"
))
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger(__name__)

app = FastAPI()

# 4. 中间件:每个请求生成 trace_id 塞进 contextvars
@app.middleware("http")
async def trace_middleware(request: Request, call_next):
    trace_id = request.headers.get("X-Trace-Id") or uuid.uuid4().hex[:12]
    token = trace_id_var.set(trace_id)
    try:
        logger.info(f"--> {request.method} {request.url.path}")
        response = await call_next(request)
        logger.info(f"<-- {response.status_code}")
        response.headers["X-Trace-Id"] = trace_id
        return response
    finally:
        trace_id_var.reset(token)

@app.get("/hello")
async def hello():
    logger.info("处理 hello 请求")
    return {"msg": "hello"}
```

启动后访问 `/hello`,日志输出:

```
2026-05-11 22:51:00 [INFO] [trace=a3f9b2c1d8e7] __main__ - --> GET /hello
2026-05-11 22:51:00 [INFO] [trace=a3f9b2c1d8e7] __main__ - 处理 hello 请求
2026-05-11 22:51:00 [INFO] [trace=a3f9b2c1d8e7] __main__ - <-- 200
```

**关键点**:同一个请求的所有日志共享同一个 `trace_id`,在 Kibana / Loki 里搜这个 ID 能拉出完整链路。

### OpenTelemetry 链路追踪最小 demo

```python
# pip install fastapi uvicorn opentelemetry-distro opentelemetry-instrumentation-fastapi opentelemetry-exporter-otlp
# pip install opentelemetry-sdk

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# 1. 配置 Tracer (这里导出到控制台,生产用 OTLP 导到 Jaeger)
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(ConsoleSpanExporter())
)

app = FastAPI()

# 2. 一行代码给所有路由自动打 span
FastAPIInstrumentor.instrument_app(app)

tracer = trace.get_tracer(__name__)

@app.get("/order/{oid}")
async def get_order(oid: int):
    # 3. 手动加业务 span
    with tracer.start_as_current_span("query_database") as span:
        span.set_attribute("order.id", oid)
        # 模拟查 DB
        result = {"id": oid, "amount": 100}

    with tracer.start_as_current_span("call_payment_service"):
        # 模拟调下游
        pass

    return result
```

启动访问 `/order/123`,控制台会打印一个嵌套的 span 树:

```
{
    "name": "query_database",
    "context": { "trace_id": "0xabc...", "span_id": "0x123..." },
    "parent_id": "0x456...",
    "attributes": { "order.id": 123 },
    ...
}
{
    "name": "GET /order/{oid}",
    "context": { "trace_id": "0xabc...", "span_id": "0x456..." },
    "parent_id": null,
    ...
}
```

**关键点**:

- `trace_id` 是请求级唯一,贯穿所有 span。
- 通过 W3C `traceparent` header 自动跨服务传播,微服务之间不用手动传。
- 生产把 ConsoleSpanExporter 换成 OTLP exporter 发到 Jaeger / Tempo,就能在 UI 上看到调用瀑布图。

### 两者结合(进阶,面试加分)

OpenTelemetry 跑起来后,**当前 span 的 trace_id 可以直接拿出来塞进日志**,这样日志和 trace 系统能通过同一个 ID 互相跳转:

```python
from opentelemetry import trace

class OtelTraceFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span()
        ctx = span.get_span_context()
        record.trace_id = f"{ctx.trace_id:032x}" if ctx.is_valid else "-"
        record.span_id = f"{ctx.span_id:016x}" if ctx.is_valid else "-"
        return super().format(record)
```

**面试话术:**

> "我们用 OpenTelemetry 做链路追踪,`FastAPIInstrumentor.instrument_app(app)` 一行接入自动给所有路由打 span,通过 W3C traceparent header 跨服务传播。日志侧用结构化日志(structlog 或自定义 Formatter),在中间件里从 OpenTelemetry 当前 span 里取出 trace_id 塞进 contextvars,日志格式化时自动带上 —— 这样 ELK 里搜日志、Jaeger 里看链路,通过同一个 trace_id 可以相互跳转,排查问题非常快。"

---

## 七、关于 Fluent Python "全有或全无" 名言

**安全替代说法**(直接背这句,既准确又有冲击力):

> "在 asyncio 编程里有一条铁律 —— **never call a blocking function in an async function**。一旦在 `async def` 里调用了同步阻塞的 IO 函数,整个 event loop 会被卡住,所有其他协程都会停下来等待,异步带来的并发收益直接归零。解决方法是用 `asyncio.to_thread` 或 `loop.run_in_executor` 把它丢到线程池。"

不挂名引用,讲的是公认的事实,谁都挑不出毛病。

(注:Fluent Python 第二版第 21 章「Asynchronous Programming」开篇题词引用 *RabbitMQ in Action* 的话:"异步编程的常规做法存在一个问题,它们都是『全有或全无』的命题。你要么重写所有的代码,让其中任何一部分都不阻塞,要么就是在做无用功。")

## 关联

- `interview_answer.md` 一/三章 — Python 内存管理与 asyncio 概念部分
- `fastapi-middleware-exception-demo.md` — Starlette 双层异常中间件可运行 demo
