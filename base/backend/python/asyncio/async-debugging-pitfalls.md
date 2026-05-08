# 手写 mini-asyncio 时踩过的坑

> 配套: `mini-asyncio-implementation.md`。
>
> 来源: 2026-04-25 ~ 2026-04-26 实操中真实犯过的错误。这些坑都不会被静态检查抓住, 只能跑起来看症状。

## 坑 1: 鸭子类型协议名拼错, 静默失败

### 症状
```
RuntimeError: bad yield: <Future object at 0x...>
```

### 原因
Future 类属性写的是 `_asyncio_future_blocking`, Task 的 `_step` 里 `getattr(result, "_async_future_blocking", None)` 拼错成 `_async_future_blocking` (少了 `io`)。

`getattr` 拿到默认值 `None`, `is not None` 为 False, 走错分支抛 `bad yield`。

### 教训
- 鸭子类型协议靠**字符串名字**对齐, 拼错就静默不工作
- 真实 asyncio 也用这个名字 —— 跟 cpython 保持一致, 别自己改
- 用搜索 (grep) 全文检查, 别只检查一处

---

## 坑 2: callback 里 `raise e` 而不是 `fut.set_exception(e)`

### 症状
异常炸穿 event loop, 整个程序退出。Future 永远 PENDING, 协程永远悬挂。

### 原因
```python
def on_readable():
    try:
        conn, addr = sock.accept()
    except Exception as e:
        raise e                    # ★ BUG
    else:
        fut.set_result((conn, addr))
```

`raise e` 让异常从 callback 抛出, 沿 `Loop.run_forever` 的 `cb(*args)` 行往上爬, 没人接住 → 整个 loop 崩溃。

### 修复
```python
except Exception as e:
    fut.set_exception(e)
```

### 教训
- **callback 是 loop 直接调的, 在 callback 里 raise 就是炸 loop**
- 异常应该走 Future 通道: `set_exception` → `_wakeup` → `_step(exc)` → `coro.throw(exc)` → 协程内的 try/except 可以接住
- 这就是 「异常隔离」 —— 一个协程挂掉不影响其他

---

## 坑 3: `_wakeup` 里用 `set_exception(exc)` 而不是 `_step(exc)`

### 症状
协程内的 `try: await fut except ValueError: ...` 接不住异常, Task 直接失败。

### 原因
```python
def _wakeup(self, future):
    try:
        future.result()
    except BaseException as exc:
        self.set_exception(exc)    # ★ BUG
    else:
        self._step()
```

`set_exception` 直接把 Task 自己标记为失败, 协程根本没机会处理这个异常。

### 修复
```python
except BaseException as exc:
    self._step(exc)                # 把异常 throw 进协程
```

### 教训
- async/await 的核心承诺是 「await 像同步代码一样能 try/except」
- 实现这一点必须靠 `coro.throw(exc)` 把异常注入到 await 表达式的位置
- 协程没接住时, 异常会冒到 `_step` 的 `except BaseException`, 那时才 set_exception

---

## 坑 4: `result` 用 `@property` 装饰

### 症状
```
RuntimeError: not done
```
出现在 `set_result` 里, 让人困惑 —— 我才刚要 set, 怎么就 already not done?

### 原因
```python
@property
def result(self):
    if self._state == "PENDING":
        raise RuntimeError("not done")
    ...

def set_result(self, result):
    if self.done(): raise ...
    self._result = self.result      # ★ BUG: 触发了 property getter
```

`self.result` 因为是 property, **触发 getter** 而不是访问字段。getter 检查 PENDING, raise。

### 修复
- 把 `@property` 去掉, `result` 改回普通方法
- `set_result` 里用参数 `result` (不是 `self.result`)
- 所有读取处加 `()`: `task.result()`, `future.result()`

### 教训
- `Future.result()` 在真实 asyncio 是方法不是 property —— 因为它可能 raise 业务异常
- Python 社区约定: `@property` 应该是 「廉价、幂等、不抛业务异常」 的, 看起来像字段; 「可能 raise / 有副作用」 的应该是方法

---

## 坑 5: level-triggered 模式不 `remove_reader` 会死循环

### 症状
程序 CPU 100% 不退出。

### 原因
`selectors` 默认 level-triggered: 只要 fd **当前是**可读状态, select 就反复返回它。

如果你 recv 完没 unregister, 而对端已关闭 (recv 返回 b""), fd 持续 「可读」, on_readable 反复触发。

### 修复
读完必须 `loop.remove_reader(fd)`。echo handler 中, 检测到 b"" 是对端关闭, 直接 close 并退出。

### 教训
- selectors 与 OS 的契约: 「我读完了 / 不再关心」 = 必须 unregister
- Linux epoll 还有 edge-triggered (ET) 模式可以避免这个问题, 但 stdlib 不暴露
- 在 `sock_recv` 里 「先 remove 再 recv」 而不是 「recv 完再 remove」 —— 异常隔离更好

---

## 坑 6: `_callbacks` 里存什么搞混了

### 症状
```
TypeError: cannot unpack non-iterable method object
```

### 原因
```python
def add_done_callback(self, fn):
    self._callbacks.append(fn)         # 存的是单个 fn

def _schedule_callbacks(self):
    while self._callbacks:
        cb, *args = self._callbacks.pop()   # ★ BUG: 当成 (cb, args) 解构
        self._loop.call_soon(cb, *args)
```

`pop` 拿到的是单个 `fn` (bound method), 不可迭代解构。

### 修复
```python
def _schedule_callbacks(self):
    for cb in self._callbacks:
        self._loop.call_soon(cb, self)     # Future 把自己作为参数
    self._callbacks.clear()
```

### 教训
- Future done callback 的协议: callback 签名是 `fn(future)`, Future 完成时把自己作为参数传过去
- 这正是 `Task._wakeup(self, future)` 能拿到 future 的原因

---

## 坑 7: `getattr` 不传默认值

### 症状
```
AttributeError: 'NoneType' object has no attribute '_asyncio_future_blocking'
```
或类似在非 Future 对象上的属性错误。

### 原因
```python
getattr(result, "_asyncio_future_blocking") is not None
```
两参数版会直接 `AttributeError`, 没机会进 else 分支报 `bad yield`。

### 修复
```python
getattr(result, "_asyncio_future_blocking", None) is not None
```

### 教训
- 三参数 `getattr(obj, name, default)` 是 「safe access」: 探测属性是否存在
- 两参数版语义是 「我**确定**有这个属性, 没有就是 bug」
- 「探测」 场景永远用三参数版

---

## 坑 8: `compile` 笔误成 `complete`

### 症状
```
TypeError: compile() missing required argument 'source' (pos 1)
```

### 原因
demo 中:
```python
loop.call_soon(compile)        # ★ 笔误, 想写 complete
```
`compile` 是 Python 内置函数 (用来编译源码字符串)。`call_soon(complete)` 只传函数对象不调用, 拼写错也不会被静态检查抓住。

### 教训
- 这种笔误防不住, 只能靠测试 + 类型标注
- 报错信息里出现内置函数名时立刻警觉 —— 大概率是变量名拼错撞了内置

---

## 通用规律

走完这 8 个坑, 总结出几条:

1. **callback 不能 raise** —— 必须走 Future 通道
2. **协议名是字符串, 拼错静默失败** —— 全文搜索一致性
3. **可能 raise 的访问做成方法不做成 property** —— Python 社区约定
4. **selectors 用完必须 unregister** —— level-triggered 契约
5. **getattr 探测用三参数版** —— 默认值挡住未知对象
6. **数据结构里存什么取什么** —— 不要在 append/pop 之间改格式

这些规律不限于 asyncio, 在任何「事件驱动 / 回调密集」的代码里都成立。
