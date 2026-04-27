# asyncio 日常 API 速查与陷阱

> 配套笔记: `async-await-internals.md` / `mini-asyncio-implementation.md` / `await-vs-yield-from.md`。
>
> 前几份讲内核,本篇回到「日常使用层」 — 哪个 API 解决哪个问题,以及它在 mini-asyncio 实现里对应什么。

## 速查表 (按使用频率排)

| 想做什么 | 用什么 | 内核对应 |
|---|---|---|
| 跑一个协程 | `asyncio.run(main())` | `loop.run_until_complete` |
| 让出 CPU 等一会 | `await asyncio.sleep(1)` | `loop.call_later` + Future |
| 并发跑多个 | `await asyncio.gather(*coros)` | spawn 多个 Task, 等完成 |
| 后台 fire-and-forget | `asyncio.create_task(coro)` | `Task(coro, loop)` |
| 设超时 | `async with asyncio.timeout(5):` | call_later + cancel |
| 取消任务 | `task.cancel()` | `coro.throw(CancelledError)` |
| 跑同步代码 | `await asyncio.to_thread(func)` | 线程池 + self-pipe |
| 同步原语 | `asyncio.Lock/Event/Queue` | Future 链式等待 |
| 网络客户端 | `asyncio.open_connection(host, port)` | `sock_connect` + `sock_recv` |
| 网络服务器 | `asyncio.start_server(handler, ...)` | echo server pattern |

---

## 1. `asyncio.run(main())` — 唯一入口

```python
import asyncio

async def main():
    print("hello")
    await asyncio.sleep(1)
    print("world")

asyncio.run(main())          # 现代写法 (Python 3.7+)
```

`asyncio.run` 内部:
1. 创建一个新 event loop
2. `loop.run_until_complete(main())`
3. 跑完关闭 loop, 清理资源

**重要**: 一个进程只能有一个 active loop。在 `main()` 里**不能**再 `asyncio.run(...)` — 会报错。

**Jupyter 特例**: Jupyter 已经在内部跑了 event loop, cell 里可以直接 `await foo()` 不需要 `asyncio.run`。但**不能在 Jupyter 里调 `asyncio.run(...)`**。

---

## 2. `asyncio.sleep` — 让出 CPU

```python
async def main():
    print("a")
    await asyncio.sleep(1)   # 让出 CPU 1 秒
    print("b")
```

**关键认知**: 这**不是** `time.sleep` — 它不会卡住 loop。`asyncio.sleep` 等价实现:

```python
async def sleep(delay):
    fut = loop.create_future()
    loop.call_later(delay, fut.set_result, None)
    await fut
```

**生死线**: 协程里**永远不要**写 `time.sleep()` / `requests.get()` / 阻塞 socket — 这些会卡死整个 loop, 所有其他 Task 都得等。

`await asyncio.sleep(0)` 特殊用法: 让出一轮调度但立刻回来, 长循环里偶尔加一行让其他 Task 有机会跑。

---

## 3. `asyncio.gather` — 并发跑多个

```python
import asyncio
import time

async def fetch(url, delay):
    await asyncio.sleep(delay)
    return f"{url} done"

async def main():
    t0 = time.time()
    results = await asyncio.gather(
        fetch("a", 2),
        fetch("b", 1),
        fetch("c", 3),
    )
    print(f"all done in {time.time()-t0:.1f}s, results: {results}")

asyncio.run(main())
```

**输出**:
```
all done in 3.0s, results: ['a done', 'b done', 'c done']
```

总耗时 3 秒(最慢那个), 不是 2+1+3=6 秒。三个 fetch 并发跑。

**返回值**: list, 顺序跟传入顺序对应(不是完成顺序)。

**异常处理**:
```python
results = await asyncio.gather(coro1, coro2, return_exceptions=True)
# 异常作为结果元素返回, 而不是直接 raise
```

---

## 4. `asyncio.create_task` — spawn 后台任务

```python
async def background():
    while True:
        print("ping")
        await asyncio.sleep(1)

async def main():
    task = asyncio.create_task(background())
    await asyncio.sleep(3)
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        print("background cancelled")

asyncio.run(main())
```

`create_task` = `Task(coro, loop)`。

### ⚠️ 重要陷阱: 必须保留引用

```python
asyncio.create_task(some_coro())   # 没保留引用!
```

GC 可能在中途回收 Task, 任务**没跑完**就被吞了。这是 asyncio 一个臭名昭著的坑。

**最佳实践**:
```python
_background_tasks = set()

def spawn(coro):
    t = asyncio.create_task(coro)
    _background_tasks.add(t)
    t.add_done_callback(_background_tasks.discard)
```

---

## 5. `async with asyncio.timeout` — 超时控制 (3.11+)

```python
async def main():
    try:
        async with asyncio.timeout(2):
            await asyncio.sleep(5)
    except TimeoutError:
        print("超时啦")
```

**老写法 (3.10 及以前)**:
```python
try:
    await asyncio.wait_for(coro, timeout=2)
except asyncio.TimeoutError:
    ...
```

`asyncio.timeout` 更现代: 支持嵌套、可以动态调整 deadline。

**底层机制**: `call_later` 安排 N 秒后 `task.cancel()`。被 cancel 的协程会从 await 处抛 `CancelledError`, timeout 上下文管理器把它转成 `TimeoutError`。

---

## 6. `asyncio.to_thread` — 桥接同步代码 (3.9+)

```python
import requests
import asyncio

async def fetch_url(url):
    response = await asyncio.to_thread(requests.get, url)
    return response.text

async def main():
    results = await asyncio.gather(
        fetch_url("https://example.com"),
        fetch_url("https://example.org"),
    )
```

**协程世界与同步世界的桥**。任何「会阻塞」的同步函数 (requests / psycopg2 / 文件 I/O) 都该走 `to_thread`。

**底层**: ThreadPoolExecutor + self-pipe trick。

**判断什么时候用**: 这个调用会阻塞超过 1ms 吗? 会就 to_thread。CPU 密集型任务别走 to_thread (GIL 限制), 用 ProcessPoolExecutor:

```python
from concurrent.futures import ProcessPoolExecutor

async def main():
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, cpu_heavy, arg)
```

---

## 7. 同步原语: Lock / Event / Queue

asyncio 提供协程版的同步原语, 用法跟 threading 类似但**不阻塞 loop**。

### Queue (最常用)

```python
async def producer(q):
    for i in range(5):
        await q.put(i)
        print(f"put {i}")
        await asyncio.sleep(0.5)
    await q.put(None)               # 哨兵, 表示结束

async def consumer(q):
    while True:
        item = await q.get()
        if item is None:
            break
        print(f"got {item}")
        await asyncio.sleep(1)

async def main():
    q = asyncio.Queue()
    await asyncio.gather(producer(q), consumer(q))

asyncio.run(main())
```

### Lock

```python
lock = asyncio.Lock()

async def critical():
    async with lock:
        await do_something()
```

**注意**: asyncio 是单线程协作式, **只在 `await` 处可能切换**。如果临界区**没有 await**, 根本不需要 Lock — 同步代码不会被其他协程打断。Lock 是用来保护「跨多个 await 的状态」。

### Event

```python
ready = asyncio.Event()

async def waiter():
    print("waiting...")
    await ready.wait()
    print("got signal")

async def setter():
    await asyncio.sleep(2)
    ready.set()                     # 触发, 所有等的人都醒来
```

---

## 8. 网络 I/O: open_connection / start_server

asyncio 提供高阶 streams API, 不用直接操作 socket。

### 客户端

```python
async def fetch(host, port):
    reader, writer = await asyncio.open_connection(host, port)
    writer.write(b"GET / HTTP/1.0\r\n\r\n")
    await writer.drain()
    data = await reader.read()
    writer.close()
    return data
```

### 服务器

```python
async def handle_client(reader, writer):
    data = await reader.read(1024)
    writer.write(b"echo: " + data)
    await writer.drain()
    writer.close()

async def main():
    server = await asyncio.start_server(handle_client, '0.0.0.0', 8888)
    async with server:
        await server.serve_forever()

asyncio.run(main())
```

`start_server` 内部每次 accept 都 spawn 一个 Task 跑 handler — 跟手写 echo server 是同一个 pattern。

---

## 9. 致命陷阱清单

```python
# ❌ 阻塞 loop 的禁词
time.sleep(1)                       # → asyncio.sleep
requests.get(url)                   # → aiohttp 或 to_thread(requests.get)
psycopg2.connect(...)               # → asyncpg
open("big.txt").read()              # → aiofiles 或 to_thread

# ❌ 忘了保留 task 引用
asyncio.create_task(bg())           # 可能被 GC, 任务消失

# ❌ 多个 asyncio.run 嵌套
async def main():
    asyncio.run(other())            # → RuntimeError
    # 应该: await other()

# ❌ 协程对象不 await
async def main():
    fetch_url("...")                # 警告: never awaited
    # 应该: await fetch_url(...) 或 create_task(fetch_url(...))

# ❌ 在 async def 里 yield from
async def main():
    yield from sub()                # SyntaxError
    # 应该: await sub() 或 async for x in sub_gen()

# ❌ 把 asyncio.sleep 当作 time.sleep 调
asyncio.sleep(1)                    # 没 await! 只是创建协程对象, 没暂停
# 应该: await asyncio.sleep(1)
```

---

## 10. 综合 demo: 并发抓取 + 超时

```python
import asyncio
import requests

async def fetch(url):
    print(f"fetching {url}")
    response = await asyncio.to_thread(requests.get, url, timeout=10)
    return url, response.status_code

async def main():
    urls = [
        "https://example.com",
        "https://httpbin.org/delay/1",
        "https://httpbin.org/delay/2",
    ]
    try:
        async with asyncio.timeout(5):
            results = await asyncio.gather(*[fetch(u) for u in urls])
        for url, code in results:
            print(f"{code}  {url}")
    except TimeoutError:
        print("超时!")

asyncio.run(main())
```

综合使用: `asyncio.run` + `gather` + `timeout` + `to_thread`。

---

## 学习路径建议

```
入门:    asyncio.run + asyncio.sleep + asyncio.gather   ← 覆盖 80% 场景
进阶:    create_task + cancel + timeout
高阶:    Queue + Event + Lock + streams API
扩展生态:
    aiohttp     替代 requests
    asyncpg     替代 psycopg2 (PostgreSQL)
    aiofiles    替代内置 open
    aiomysql    替代 mysqlclient
    motor       替代 pymongo
    aioredis    替代 redis-py (注: redis-py 4.2+ 已内置 async 支持)
```

这些是 asyncio 生态的「真异步」库, 用 await 风格 API 替代同步库。

---

## 与 mini-asyncio 实现的对应表

帮助巩固「日常 API 不是黑魔法, 都是内核组合」的认知:

| asyncio API | mini-asyncio 实现 |
|---|---|
| `asyncio.run(coro)` | `loop.run_until_complete(coro)` |
| `asyncio.create_task(coro)` | `Task(coro, loop)` |
| `await asyncio.sleep(s)` | 没实现, 但等价于 `call_later + Future + await` |
| `await asyncio.gather(*coros)` | `for t in [Task(c, loop) for c in coros]: await t` |
| `task.cancel()` | 没实现, 等价于 `task._step(CancelledError())` |
| `asyncio.open_connection` | `sock_connect` + 没实现 |
| `asyncio.start_server` | echo server 主循环 + spawn handler Task |
| `asyncio.to_thread` | 没实现, 需要线程池 + self-pipe |

mini-asyncio 是 asyncio 的「无装饰版」, 把 80% 概念都覆盖了。剩下 20% (call_later、cancel、to_thread) 是工程化的延伸, 套路相同。
