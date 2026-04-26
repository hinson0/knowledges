# Python `async/await` 的底层机制

> 来源:对话学习笔记。简体中文。

## 一、最关键的认知:协程就是「可暂停的生成器」

`async/await` 本质上是 **生成器(generator)** 机制的语法糖升级版。理解 async 之前必须先理解 generator 的 `yield` 是怎么暂停函数执行的。

要点:

- Python 的 async 不是「真正的并发」,它是单线程内的协作式调度。
- `async def` 编译出来的字节码和普通函数完全不同 —— 它返回 coroutine 对象,函数体一行都不会执行。
- `await` 在字节码层面就是 `YIELD_FROM` / `SEND` 操作,跟 `yield from` 同源。

## 二、演化路线(理解历史就理解了机制)

```
普通函数 → 生成器 (yield) → 协程 (yield from) → 原生协程 (async/await)
   1990s        PEP 255          PEP 380              PEP 492
```

- **PEP 342 (2005)**: 给 generator 加了 `.send(value)` —— 让外部能往暂停的函数里塞值。这是协程的雏形。
- **PEP 380 (2014)**: `yield from` —— 允许一个 generator 委托给另一个 generator,异常和返回值会透传。
- **PEP 492 (2015)**: `async def` / `await` —— 用新关键字把「协程」从 generator 中独立出来,语义更清晰,但**底层机制基本相同**。

## 三、`async def` 背后发生了什么

当你写:

```python
async def foo():
    x = await bar()
    return x + 1
```

CPython 编译器做了三件事:

1. 给函数对象打上 `CO_COROUTINE` flag(`co_flags` 字段)。
2. 调用 `foo()` 时不会执行函数体,而是返回一个 **coroutine object**(类似 generator object)。
3. `await bar()` 被翻译成字节码 `GET_AWAITABLE` + `LOAD_CONST None` + `YIELD_FROM`(3.11 之前)或 `SEND` + `YIELD_VALUE`(3.11+)。

可以亲自验证:

```python
import dis
async def foo():
    await bar()
dis.dis(foo)
```

会看到 `GET_AWAITABLE`、`SEND`、`YIELD_VALUE` 这些指令。

## 四、协程对象的核心协议:`__await__` / `send` / `throw`

每个可被 `await` 的对象必须实现 `__await__`,它返回一个 **iterator**。事件循环就靠这个 iterator 驱动协程:

```
loop                         coroutine
 │                              │
 │── coro.send(None) ──────────▶│   恢复执行
 │                              │   遇到 await,挂起
 │◀── 抛出 StopIteration(value) │   或 yield 一个 Future
 │                              │
```

整个机制就这三个操作:

- `coro.send(value)` —— 把 value 作为上一次 `await` 表达式的结果,继续运行,直到下一次暂停。
- `coro.throw(exc)` —— 把异常注入到协程暂停点。
- `StopIteration` —— 协程 `return x` 时抛出 `StopIteration(x)`,事件循环捕获它拿到结果。

要点:

- 协程并不知道有 event loop 存在 —— 它只是「被 send 驱动的状态机」。
- event loop 也不直接关心协程 —— 它只调度 Future。协程通过 await Future 把自己挂到 loop 上。
- 这就是为什么 asyncio、trio、curio 可以是不同的 loop 实现,但跑同一份 async 代码。

## 五、事件循环如何串起来:Task / Future 是粘合层

光有协程还不够,因为协程暂停后总得有人再唤醒它。`asyncio.Task` 就干这事:

```python
# 简化伪代码,体现思想
class Task:
    def __init__(self, coro):
        self._coro = coro
        loop.call_soon(self._step)         # 立刻安排第一次执行

    def _step(self, value=None):
        try:
            future = self._coro.send(value)   # 推进协程
        except StopIteration as e:
            self._result = e.value            # 协程结束
            return
        future.add_done_callback(            # 协程在等一个 Future
            lambda f: self._step(f.result())  # Future 完成时再回来推进
        )
```

整个 asyncio 的核心流程就这么个循环:**send → 拿到一个 Future → 给 Future 装回调 → Future 就绪后再 send**。

## 六、为什么协程一遇 I/O 就「让出」CPU

底层的 `socket.recv` 在 asyncio 里被改写成:

1. 把 fd 注册到 `selector`(epoll/kqueue/IOCP)。
2. 创建一个 Future,把「fd 可读时 set_result」绑定为回调。
3. `await` 这个 Future —— 等于把当前协程挂起。
4. event loop 调用 `selector.select(timeout)` 阻塞等 OS 通知。
5. 哪个 fd 就绪 → 触发 Future 的 done_callback → `Task._step` → 协程恢复。

所以「异步」并不是协程自己异步,而是 **OS 的 I/O 多路复用 + 协程的可暂停** 这两个机制合作的结果。

## 七、动手验证(不依赖 asyncio,纯手工驱动协程)

下面这段代码最能说明问题。在 `python` 交互式环境敲一遍:

```python
async def child():
    print("child start")
    x = await some_awaitable()
    print("child got", x)
    return "done"

class some_awaitable:
    def __await__(self):
        value = yield "I'm waiting"   # 挂起,把字符串传给外层
        return value * 2              # 恢复后,把结果给 child 的 x

coro = child()
print(coro.send(None))      # 输出: child start, 然后 "I'm waiting"
print(coro.send(21))        # 输出: child got 42, 然后 StopIteration: done
```

观察到的现象:

- `coro.send(None)` 第一次启动协程,跑到 `yield` 就停下,把 `"I'm waiting"` 抛回来。
- `coro.send(21)` 把 21 注入到 `yield` 表达式的位置,继续跑完。
- 协程结束时 `return "done"` → 抛出 `StopIteration("done")`。

**这就是 event loop 在做的事,只不过它中间多了一层 Future 调度。**

要点:

- 协程的「魔法」全在 `send/yield/StopIteration` 这三件事上,没有任何线程或并行。
- `await` 本质就是 `yield from obj.__await__()`,把控制权交还给驱动者。
- CPython 3.11+ 用专用的 `SEND` 字节码替代了部分 `YIELD_FROM`,性能提升约 10%~15%,但语义没变。

## 八、推荐继续学习的路径

1. 读一遍 `cpython/Lib/asyncio/tasks.py` 中 `Task.__step` 的真实实现 —— 跟上面伪代码几乎一致,代码不长。
2. `dis` 一段 async 函数,看 `SEND` / `GET_AWAITABLE` / `YIELD_VALUE` 字节码。
3. 手写一个最小 event loop(就 50 行):用 `selectors` + 自己实现的 Task,跑通一个 echo server,这是最快的彻底搞懂方式。
4. PEP 492 / PEP 525 / PEP 530 三篇文档按顺序读。

##

需要我接下来把哪一块展开?比如:

- 手写最小 event loop 的步骤指引(老师模式)
- 字节码层面 SEND 指令的执行细节
- asyncio.gather / asyncio.wait 的调度差异
