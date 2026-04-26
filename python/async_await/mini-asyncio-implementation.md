# 手写 mini-asyncio:从 50 行代码理解 Python 异步

> 配套笔记: `async-await-internals.md`(机制) / `asyncio-task-step-source.md`(cpython 源码精读) / `async-debugging-pitfalls.md`(踩坑实录)。
>
> 来源: 2026-04-25 ~ 2026-04-26 学习对话, 通过 5 个 phase 渐进式手写 asyncio 内核。
>
> 实现路径: `~/fastapi_web/src/mini_asyncio/`

## 全景脑图

```
         ┌─────────────────────────────────────────┐
         │           应用层 async 函数              │
         │   echo_handler / main / sock_recv       │
         └────────────────┬────────────────────────┘
                          │ await
         ┌────────────────▼────────────────────────┐
         │              Future                     │
         │  - 状态: PENDING / FINISHED             │
         │  - __await__: yield self → 暂停协程     │
         │  - set_result / add_done_callback       │
         └────────────────┬────────────────────────┘
                          │ 被 yield 出来
         ┌────────────────▼────────────────────────┐
         │              Task (= Future + coro)     │
         │  - _step: send / throw 推进协程          │
         │  - _wakeup: Future 完成时回到 _step      │
         │  - StopIteration → set_result            │
         └────────────────┬────────────────────────┘
                          │ call_soon
         ┌────────────────▼────────────────────────┐
         │              Loop                        │
         │  - ready 队列: deque[(cb, args)]         │
         │  - run_forever: 跑 ready, 然后 select   │
         │  - add_reader: 把 fd 注册到 selector    │
         └────────────────┬────────────────────────┘
                          │ select()
         ┌────────────────▼────────────────────────┐
         │           OS (epoll/kqueue/select)       │
         │  把整个进程睡过去, 直到任何 fd 就绪      │
         └─────────────────────────────────────────┘
```

## 学习路线: 5 个 Phase

| Phase | 核心认知 | 行数累计 |
|---|---|---|
| 1 | event loop 的本质 = ready 队列 + 主循环 | ~15 |
| 2 | I/O 多路复用 = 把所有 fd 关心一次性提交给 OS, 让进程睡过去 | ~30 |
| 3 | `async/await` 不是新机制, 是 generator + Future 协议的语法糖 | ~80 |
| 4 | 桥接模式: 把 callback 风格 (add_reader) 包装成 await 风格 (Future) | ~100 |
| 5 | `Task(coro, loop)` = fire-and-forget;单线程并发的真容 | ~150 |

---

## Phase 1: 最小调度器

「event loop 剥到极致就是: 一个就绪队列, 主循环不停从队列头部取 callback 调用, callback 内部可以再往队列里塞新的 callback。队列空了就停。」

```python
from collections import deque

class Loop:
    def __init__(self):
        self._ready = deque()
        self._stopping = False

    def call_soon(self, cb, *args):
        self._ready.append((cb, args))

    def stop(self):
        self._stopping = True

    def run_forever(self):
        while not self._stopping and self._ready:
            cb, args = self._ready.popleft()
            cb(*args)
```

**关键设计**:
- `deque` 而非 `list` —— `popleft` 是 O(1)
- 两条退出路径: `stopping = True` 或 ready 队列空 (Phase 2 后第二条会变形)

---

## Phase 2: 加入 I/O 多路复用

```python
import selectors

class Loop:
    def __init__(self):
        self._ready = deque()
        self._stopping = False
        self._selector = selectors.DefaultSelector()  # macOS: kqueue / linux: epoll

    def add_reader(self, fd, cb, *args):
        self._selector.register(fd, selectors.EVENT_READ, data=(cb, args))

    def remove_reader(self, fd):
        self._selector.unregister(fd)

    def run_forever(self):
        while not self._stopping:
            while self._ready:
                cb, args = self._ready.popleft()
                cb(*args)

            if not self._selector.get_map():
                break

            events = self._selector.select(timeout=None)  # 阻塞等 OS
            for key, mask in events:
                cb, args = key.data
                self.call_soon(cb, *args)
```

**关键设计**:
- selector `data` 字段直接存 `(cb, args)` —— 鸭子类型, asyncio 真实代码也这么干
- I/O 事件不当场调用, 而是 `call_soon` 入队 —— 一致性 + 公平性
- `selectors` 是 stdlib 对 epoll/kqueue/select 的统一封装, 跨平台

**坑**: level-triggered 模式下读完必须 `remove_reader`, 否则 fd 持续可读会无限触发。

---

## Phase 3: Future + Task

### Future

```python
class Future:
    _asyncio_future_blocking = False  # 鸭子类型标记

    def __init__(self, loop):
        self._loop = loop
        self._state = 'PENDING'
        self._result = None
        self._exception = None
        self._callbacks = []

    def done(self):
        return self._state != 'PENDING'

    def result(self):
        if self._state == 'PENDING':
            raise RuntimeError("not done")
        if self._exception:
            raise self._exception
        return self._result

    def set_result(self, result):
        if self.done():
            raise RuntimeError("already done")
        self._result = result
        self._state = 'FINISHED'
        self._schedule_callbacks()

    def set_exception(self, exc):
        if self.done():
            raise RuntimeError("already done")
        self._exception = exc
        self._state = 'FINISHED'
        self._schedule_callbacks()

    def add_done_callback(self, fn):
        if self.done():
            self._loop.call_soon(fn, self)
        else:
            self._callbacks.append(fn)

    def _schedule_callbacks(self):
        for cb in self._callbacks:
            self._loop.call_soon(cb, self)
        self._callbacks.clear()

    def __await__(self):
        if not self.done():
            self._asyncio_future_blocking = True
            yield self                    # ★ 把自己 yield 出去给 Task
        return self.result()
```

### Task

```python
class Task(Future):
    def __init__(self, coro, loop):
        super().__init__(loop)
        self._coro = coro
        loop.call_soon(self._step)        # 创建即安排执行

    def _step(self, exc=None):
        try:
            if exc is None:
                result = self._coro.send(None)
            else:
                result = self._coro.throw(exc)
        except StopIteration as e:
            self.set_result(e.value)
            return
        except BaseException as e:
            self.set_exception(e)
            return

        if getattr(result, '_asyncio_future_blocking', None) is not None:
            result.add_done_callback(self._wakeup)
        else:
            raise RuntimeError(f"bad yield: {result!r}")

    def _wakeup(self, future):
        try:
            future.result()
        except BaseException as exc:
            self._step(exc)               # ★ throw 进协程, 不是 set_exception
        else:
            self._step()
```

### Loop.run_until_complete

```python
def run_until_complete(self, coro):
    task = Task(coro, self)
    task.add_done_callback(lambda t: self.stop())
    self.run_forever()
    return task.result()
```

**关键设计**:
- `result()` 是方法不是 property —— 因为可能 raise 业务异常
- `_callbacks` 里存单个 fn, callback 调用时 Future 把自己 (`self`) 作为参数传过去 —— 这是 Future done callback 的协议
- `_wakeup` 路径里异常必须 `_step(exc)` 不是 `set_exception(exc)` —— 让协程能用 try/except 接住
- `_asyncio_future_blocking` 是协议名, **拼错就静默失败** (`_async_future_blocking` 不行)

---

## Phase 4: 异步 I/O 原语 (桥接模式)

桥接模式 4 步: 创建 Future → 注册 fd 回调 → 回调里 set_result/set_exception → await Future。

```python
async def sock_recv(loop, sock, n):
    fut = Future(loop)
    fd = sock.fileno()

    def on_readable():
        loop.remove_reader(fd)            # ★ 先取消关心
        try:
            data = sock.recv(n)
        except Exception as e:
            fut.set_exception(e)          # ★ 不是 raise!
        else:
            fut.set_result(data)

    loop.add_reader(fd, on_readable)
    return await fut


async def sock_accept(loop, sock):
    """server socket 可读 = backlog 里有连接待领"""
    fut = Future(loop)
    fd = sock.fileno()

    def on_readable():
        loop.remove_reader(fd)
        try:
            conn, addr = sock.accept()
            conn.setblocking(False)        # ★ 新连接也要非阻塞
        except Exception as e:
            fut.set_exception(e)
        else:
            fut.set_result((conn, addr))

    loop.add_reader(fd, on_readable)
    return await fut


async def sock_sendall(loop, sock, data):
    """简化版: 不处理 EAGAIN。完整版需要 add_writer。"""
    sock.sendall(data)
```

**关键认知**:
- server socket 「可读」语义 = 「backlog 里有连接」, 不是 「有数据」 —— OS 给 listening socket 重载了语义
- 所有 asyncio I/O 原语 (sock_recv / sock_connect / sock_sendto) 都是这个 4 步套路

---

## Phase 5: 并发 echo server

```python
async def echo_handler(conn, addr):
    try:
        while True:
            data = await sock_recv(loop, conn, 1024)
            if data == b"":              # ★ 对端关闭语义
                break
            await sock_sendall(loop, conn, b"echo: " + data)
    finally:
        conn.close()


async def main(server_sock, n_connections):
    handlers = []
    for i in range(n_connections):
        conn, addr = await sock_accept(loop, server_sock)
        t = Task(echo_handler(conn, addr), loop)   # ★ fire-and-forget
        handlers.append(t)
    for t in handlers:                              # ★ 等所有 handler 完成
        await t
    return f"served {n_connections} clients"
```

**关键认知**:
- `Task(coro, loop)` 创建即并发, 不阻塞 main
- `await coro` = 串行;`Task(coro, loop)` = 并发
- `for t in handlers: await t` 是 `asyncio.gather` 的最简形态
- handler closed 之前还能 accept 下一个 —— 单线程多连接交错执行

---

## 这 50 行没做的事

按难度递增, 都是真实 asyncio 的扩展:

| 缺失能力 | 实现思路 |
|---|---|
| `call_later(delay, cb)` / `sleep` | `heapq` 维护 `(when, cb)`, 主循环算 next_deadline 给 `select(timeout=...)` |
| `task.cancel()` | `_step(CancelledError())`;若在等 fut 先 cancel fut |
| `add_writer` + 完整 `sock_sendall` | 同一 fd 用 `selectors.modify` 切换 events 位掩码 |
| `asyncio.gather(*coros)` | spawn Tasks, 挂回调统计完成数, 最后一个 set_result |
| `run_in_executor` (线程池桥接) | self-pipe trick: socketpair, worker 写一字节唤醒 select |

但核心心脏就是这 50 行。看懂这 50 行, 真实 asyncio 5000 行都能扒。

---

## 实操验证清单

跑完 5 个 phase 后, 自我检验:

- [ ] 能解释为什么 `coro.send(None)` 永远传 None (侧路传输)
- [ ] 能解释 `_asyncio_future_blocking` 的作用 (鸭子类型识别 Future-like)
- [ ] 能解释 `await coro` 与 `Task(coro)` 的区别 (串行 vs 并发)
- [ ] 能解释为什么 server socket 的 「可读」 不同于普通 socket
- [ ] 能解释为什么 callback 里不能 raise (会炸 loop)
- [ ] 能不参考代码, 把 phase 1+2 的 Loop 完整默写

全部能答, 这 50 行就真正成了你的资产。
