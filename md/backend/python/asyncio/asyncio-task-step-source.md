# CPython `asyncio.Task.__step` 源码精读

> 配套笔记: `async-await-internals.md`(讲机制),本篇对照真实源码逐段拆解。

## 文件位置

本机路径(macOS, Python 3.14):

```
/Library/Frameworks/Python.framework/Versions/3.14/lib/python3.14/asyncio/tasks.py
```

关键符号定位:

- `class Task(futures._PyFuture)` —— 第 56 行(纯 Python 实现,生产用 `_asyncio.Task` C 扩展,逻辑一致)
- `def __step` —— 第 266 行(分发器)
- `def __step_run_and_handle_result` —— 第 283 行(真正干活,Python 3.12 起从 `__step` 拆出)
- `def __wakeup` —— 第 359 行(回调闭环)

打开方式:

```bash
code -g /Library/Frameworks/Python.framework/Versions/3.14/lib/python3.14/asyncio/tasks.py:266
```

---

## 第一段:`__step` 是个薄壳(266 ~ 281)

```python
def __step(self, exc=None):
    if self.done():
        raise exceptions.InvalidStateError(...)        # 防御 1
    if self._must_cancel:
        if not isinstance(exc, exceptions.CancelledError):
            exc = self._make_cancelled_error()         # 取消优先
    self._fut_waiter = None                            # 清空「我在等的 Future」
    _py_enter_task(self._loop, self)                   # 标记当前 task
    try:
        self.__step_run_and_handle_result(exc)         # 真正干活
    finally:
        _py_leave_task(self._loop, self)
```

做三件事:
1. 状态校验(`done` 的 task 不能再被推进)
2. 处理「外部要求取消」的情况
3. 进入/离开 task 上下文 —— 委托给 `__step_run_and_handle_result`

**`_py_enter_task` / `_py_leave_task` 的作用**: 维护一张「loop → 当前正在跑的 Task」映射表,这是 `asyncio.current_task()` 的实现基础。属于可观测性服务,与协程调度核心逻辑无关。

---

## 第二段:`coro.send` / `coro.throw` —— 真正推进协程(283 ~ 291)

```python
def __step_run_and_handle_result(self, exc):
    coro = self._coro
    try:
        if exc is None:
            # We use the `send` method directly, because coroutines
            # don't have `__iter__` and `__next__` methods.
            result = coro.send(None)         # ★ 第一句关键
        else:
            result = coro.throw(exc)         # ★ 第二句关键
```

两种推进方式:

- 正常: `coro.send(None)` —— 一路跑到下一个 `await` 暂停点,把它让出来的东西(通常是 Future)接住放进 `result`
- 异常: `coro.throw(exc)` —— 把 `exc` 注入到协程当前暂停的位置,让 `await` 处直接 `raise`

**为什么固定 `send(None)` 而不是 `send(value)`?**

asyncio 的 `Future.__await__` 实现大致是:

```python
def __await__(self):
    if not self.done():
        self._asyncio_future_blocking = True
        yield self                            # 让出 Future 自己
    return self.result()
```

它 `yield self`,并不期望从外部拿到 send 的值。Future 的「真正结果」由协程自己在 `await` 表达式恢复时通过 `return self.result()` 取得 —— 走的是侧路,不走 send 通道。所以 send 形参恒为 None。

---

## 第三段:异常分支 —— 协程结束的所有可能(292 ~ 307)

```python
except StopIteration as exc:
    if self._must_cancel:
        ...
        super().cancel(msg=self._cancel_message)
    else:
        super().set_result(exc.value)        # ★ return 值落到这里
except exceptions.CancelledError as exc:
    self._cancelled_exc = exc
    super().cancel()
except (KeyboardInterrupt, SystemExit) as exc:
    super().set_exception(exc)
    raise                                    # 这俩特殊,要 re-raise
except BaseException as exc:
    super().set_exception(exc)
```

| 异常类型 | 含义 | 处理 |
|---|---|---|
| `StopIteration` | 协程 `return x` 了 | `set_result(x)` —— Task 自身作为 Future 完成 |
| `CancelledError` | 协程被取消 | `Future.cancel()` |
| `KeyboardInterrupt` / `SystemExit` | 用户按 Ctrl+C 或 sys.exit | 既记录到 Task,又往上抛(让程序能退出) |
| 其它 `BaseException` | 协程出错抛了异常 | `set_exception(exc)` |

**强记**: `StopIteration.value` 就是 `return` 的返回值。这是 PEP 380 定下的协议,`yield from` 和 `await` 都靠它传返回值。

---

## 第四段:`else` 分支 —— 协程没结束,挂 callback(308 ~ 339)

整个文件最重要的 20 行。原代码:

```python
else:
    blocking = getattr(result, '_asyncio_future_blocking', None)
    if blocking is not None:
        if futures._get_loop(result) is not self._loop:
            ...                              # 错误: 跨 loop
        elif blocking:
            if result is self:
                ...                          # 错误: await 自己
            else:
                futures.future_add_to_awaited_by(result, self)
                result._asyncio_future_blocking = False
                result.add_done_callback(             # ★★★ 核心
                    self.__wakeup, context=self._context)
                self._fut_waiter = result             # 记录在等谁
```

**剥掉所有错误防御,核心只有 3 行**:

```python
result._asyncio_future_blocking = False
result.add_done_callback(self.__wakeup, ...)
self._fut_waiter = result
```

翻译成人话:

> 协程刚才 `await` 让我吐了一个 Future。我就在这个 Future 上挂一个回调 —— 「等你 `set_result` 了,记得回过头来喊我 `__wakeup`」。然后 Task 自己就返回了,把 CPU 还给 event loop。

**`_asyncio_future_blocking` 是什么?** —— asyncio 用来识别「Future-like 对象」的鸭子类型标记。任何对象只要带这个属性,asyncio 就把它当 Future 处理。`asyncio.Future`、`asyncio.Task`、`concurrent.futures.Future` 的桥接对象、第三方库自定义 Future 全靠它。

**Future 是怎么从 await 表达式里跑到 result 的?**

`await some_future` 在字节码层面变成 `yield from some_future.__await__()`。`Future.__await__` 内部 `yield self` 时,这个 `self` 穿过 Task 的 `coro.send(None)` 出来,变成 `result`。这就是「协程不知道有 event loop」的本质 —— 它只是把要等的 Future yield 出去,谁接谁负责。

### 其它 yield 类型的错误分支(341 ~ 355)

- `result is None` (裸 yield): 让出一轮 event loop,下一轮再 `__step`
- `inspect.isgenerator(result)`: 报错 `yield was used instead of yield from for generator`
- 其它任意值: 报错 `Task got bad yield`

---

## 第五段:`__wakeup` 闭环(359 ~)

```python
def __wakeup(self, future):
    futures.future_discard_from_awaited_by(future, self)
    try:
        future.result()                  # ★ 取出 Future 的结果(可能抛异常)
    except BaseException as exc:
        self.__step(exc)                 # 异常 → throw 进协程
    else:
        self.__step()                    # 正常 → send(None) 继续
```

闭环就在这两行:

- Future 正常完成 → `__step()` → `coro.send(None)` → 协程从 `await` 处恢复
- Future 异常 → `__step(exc)` → `coro.throw(exc)` → 协程的 `await` 处直接 raise

注意: `future.result()` 后面没有保存返回值。注释说得很清楚 —— 值不需要主动喂给协程,协程自己会通过 `Future.__await__` 里的 `return self.result()` 拿到。这就是第二段说的「侧路传输」。

---

## 整体闭环图

```
   loop.call_soon(__step)                 ← Task 创建时安排第一次执行
        │
        ▼
   __step(None)
        │
        ▼  coro.send(None)
   协程跑到 await fut 处暂停,fut 被 yield 出来
        │
        ▼  result = fut
   add_done_callback(__wakeup)            ← 把自己挂到 Future 上
        │
   Task 函数返回,event loop 拿回控制权
        │
   …event loop 处理其它 Task / I/O…
        │
   fut.set_result(value) 触发 callback
        │
        ▼
   __wakeup(fut)
        │  fut.result() 没异常
        ▼
   __step()
        │
        ▼  coro.send(None)
   协程从 await 恢复,跑到下一个暂停点
        │
        … 循环 …
        │
   协程 return → StopIteration
        │
        ▼
   __step 捕获 → super().set_result(value)   ← Task 自己作为 Future 完成
```

---

## 自我验证清单

打开 `tasks.py` 对照:

1. **289 行** `coro.send(None)` —— 笔记伪代码 `self._coro.send(value)` 的真身(value 永远是 None)
2. **298 行** `super().set_result(exc.value)` —— 协程 return 值的归宿
3. **327 行** `result.add_done_callback(self.__wakeup, ...)` —— 笔记伪代码 `future.add_done_callback(...)` 的真身
4. **365 行** `self.__step(exc)` —— 闭环回到 `__step`

## 延伸阅读

- `Future.__await__` —— 看 Future 怎么 yield self
- `BaseEventLoop._run_once` —— 事件循环主体,怎么调度 callback 和 selector
- `_asynciomodule.c` 中的 `task_step` —— C 扩展版的同名实现,生产路径
