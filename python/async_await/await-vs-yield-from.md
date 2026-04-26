# `await` vs `yield from`:同源孪生

> 配套笔记: `async-await-internals.md` / `mini-asyncio-implementation.md`。
>
> 本篇专门讲清楚 PEP 492 (async/await) 与 PEP 380 (yield from) 的等价关系与差异。

## TL;DR

**`await x` 在底层 ≈ `yield from x.__await__()`**。

PEP 492 没发明新机制,它**重新封装**了已有机制 (yield + send + StopIteration),加上类型限制。

---

## 历史脉络

| 时间 | PEP | 引入 | 解决了什么 |
|---|---|---|---|
| 2005 | 342 | `generator.send(value)` | 让 generator 能接收外部值 → 协程的雏形 |
| 2014 | 380 | `yield from <iterable>` | 委托给子 generator, 异常/返回值透传 |
| 2015 | 492 | `async def` / `await` | 类型严格化: 区分「迭代用」与「协程用」的 generator |

---

## 字节码层面的等价

```python
# 你写这段:
async def foo():
    x = await some_awaitable
    return x

# Python 3.5 ~ 3.10 大致编译成 (示意, 不严谨):
def foo():
    __tmp = some_awaitable.__await__()
    x = yield from __tmp
    return x
```

3.11+ 用专用 `SEND` 字节码替代 `YIELD_FROM`, 性能提升约 10~15%, 语义不变。

可以用 `dis` 验证:

```python
import dis
async def foo():
    await bar()
dis.dis(foo)
# 看到 GET_AWAITABLE / SEND / YIELD_VALUE 等 opcode
```

---

## 关键差异表

| | `yield from <iterable>` | `await <awaitable>` |
|---|---|---|
| 用在哪 | `def` (generator function) | `async def` (coroutine function) |
| 委托对象 | 任何 iterable | 必须有 `__await__` |
| 协议方法 | `__iter__` | `__await__` |
| 协程对象作子任务 | ❌ 不能 `yield from coro` (coroutine 没 `__iter__`) | ✅ `await coro` |
| 普通 generator 作子任务 | ✅ | 需要 `@types.coroutine` 装饰 |
| 静态检测 | 弱 | 强 (Python 警告 coroutine never awaited) |

---

## 核心 Demo: 看 await 背后做了什么

```python
class WaitForValue:
    """最简 awaitable: 把名字 yield 出去, 等驱动者 send 回来一个值"""

    def __init__(self, name):
        self.name = name

    def __await__(self):
        # ★ 这就是 await 背后的真容: 一个 yield + 一个 return
        sent_value = yield self.name           # 暂停, 把 self.name 送出去
        return sent_value * 10                 # 恢复后, 把 sent_value*10 当作 await 表达式的值


async def my_coroutine():
    print("[coro] step 1")
    a = await WaitForValue("first")
    print(f"[coro] step 2, a={a}")
    b = await WaitForValue("second")
    print(f"[coro] step 3, b={b}")
    return a + b


# === 当 Task / event loop 的角色, 手动驱动协程 ===
coro = my_coroutine()                          # 拿到 coroutine 对象, 一行没执行

print("driver: send(None)  ← 启动协程")
yielded = coro.send(None)
print(f"driver: 协程暂停了, yield 出来: {yielded!r}\n")

print("driver: send(1)  ← 模拟「first 的值是 1」")
yielded = coro.send(1)
print(f"driver: 协程暂停了, yield 出来: {yielded!r}\n")

print("driver: send(2)  ← 模拟「second 的值是 2」")
try:
    yielded = coro.send(2)
except StopIteration as e:
    print(f"driver: 协程结束了, return: {e.value}")
```

**期望输出**:

```
driver: send(None)  ← 启动协程
[coro] step 1
driver: 协程暂停了, yield 出来: 'first'

driver: send(1)  ← 模拟「first 的值是 1」
[coro] step 2, a=10
driver: 协程暂停了, yield 出来: 'second'

driver: send(2)  ← 模拟「second 的值是 2」
[coro] step 3, b=20
driver: 协程结束了, return: 30
```

注意 `a=10` 和 `b=20` —— send 进去的是 1 和 2, 但协程拿到的是 10 和 20。这就是 `__await__` 的 `return sent_value * 10` 在做事。

---

## await 表达式的语义脱糖

`a = await WaitForValue("first")` 这一行展开:

```python
# 伪展开
__awaitable = WaitForValue("first")
__iter = __awaitable.__await__()
try:
    while True:
        __value_to_yield = next(__iter)       # 第一次是 next, 后续是 send
        __sent_back = yield __value_to_yield  # 把它 yield 给上层驱动者
        __iter.send(__sent_back)
except StopIteration as e:
    a = e.value                                # ← __await__ 的 return 值
```

**对应到机制的 5 步**:

```
源代码:  a = await WaitForValue("first")
       │
       ├─① 调用 WaitForValue("first").__await__() → 一个 generator
       │
       ├─② 这个 generator 的 yield "first" 把字符串送出去
       │     ──→ 在你的代码外, 这就是 coro.send(None) 的返回值 "first"
       │
       │  (驱动者拿到 "first", 决定将来要 send 回 1)
       │
       ├─③ coro.send(1) → 1 进入 __await__ 内部 yield 表达式的位置
       │     变成 sent_value = 1
       │
       ├─④ __await__ 执行 return sent_value * 10 → return 10
       │     ──→ 这变成 StopIteration(10), 在 yield from 委托中
       │           StopIteration 被捕获, .value (即 10) 作为整个 yield from 表达式的值
       │
       └─⑤ 这个值 (10) 被赋给 a
```

**`await` 在干的全部事情**: 没有调度、没有事件循环、没有 I/O。这些是框架层 (asyncio) 在 `__await__` 内部 `yield self` 出去后, 由 Task 接住 Future 实现的。

---

## yield from 等价版 (验证等价关系)

把上面的 demo 改写成 yield from 风格:

```python
class WaitForValue:
    def __init__(self, name):
        self.name = name

    def __iter__(self):                # ★ __await__ 改名 __iter__
        sent_value = yield self.name
        return sent_value * 10


def my_generator():                    # ★ 普通 def
    print("[coro] step 1")
    a = yield from WaitForValue("first")     # ★ await 改成 yield from
    print(f"[coro] step 2, a={a}")
    b = yield from WaitForValue("second")
    print(f"[coro] step 3, b={b}")
    return a + b


# 完全一样的驱动代码, 完全一样的输出
coro = my_generator()
...
```

**输出与 async 版一字不差**。这就是 PEP 492 「await ≈ yield from」的等价关系实证。

---

## 为什么还要发明 `await`?

字节码等价, 但 PEP 492 要解决三个问题:

### 1. 类型语义清晰化

```python
# 旧时代: 同一个 generator 既能用作迭代又能用作协程
def fetch_url():
    yield from socket_recv(...)

for x in fetch_url():               # 当迭代器
    ...
result = yield from fetch_url()     # 又当协程
```

调用方靠**使用方式**反推语义, IDE 帮不上忙。

```python
# 新时代: 名字就告诉你这是协程
async def fetch_url():
    return await socket_recv(...)

for x in fetch_url():               # ★ TypeError: coroutine is not iterable
```

### 2. 静态检测能力

```python
async def main():
    fetch_url()                     # ★ RuntimeWarning: coroutine 'fetch_url' was never awaited
```

普通 generator 没这种警告, 因为 generator 本来就允许「不被消费」。协程不允许。

### 3. 阻止常见误用

`async def` 里**禁止 `yield from`**, 只能用 `await`:

```python
async def main():
    yield from some_async_op        # ★ SyntaxError
```

把「协程内部的委托」锁定到一种语法。

---

## 异常透传 (await 的另一面)

await 不仅传值, 也传异常:

```python
class FailingAwaitable:
    def __await__(self):
        yield "step 1"
        yield "step 2"
        raise ValueError("boom!")     # __await__ 抛异常

async def main():
    try:
        await FailingAwaitable()
    except ValueError as e:
        print(f"caught: {e}")
        return "recovered"

coro = main()
print(coro.send(None))    # → "step 1"
print(coro.send(None))    # → "step 2"
try:
    coro.send(None)        # → ValueError 从 __await__ 抛出
except StopIteration as e:
    print(f"main returned: {e.value}")
```

**输出**:

```
step 1
step 2
caught: boom!
main returned: recovered
```

异常**穿透 await**, 从 `await FailingAwaitable()` 这一行抛出, 被协程的 try/except 接住。

这正是 asyncio 中 `Future.set_exception(e)` → `_wakeup` 的 `future.result()` raise → `_step(exc)` → `coro.throw(exc)` → 异常从 `await fut` 处抛出的机制基础。

---

## 记忆口诀

```
yield from <iterable>   ↔   await <awaitable>
       │                            │
       └─ generator 委托             └─ coroutine 委托
       └─ __iter__                   └─ __await__
       └─ def 函数内                  └─ async def 函数内
       └─ 任何东西能 yield from       └─ 必须有 __await__
```

**底层一回事 (yield + send + StopIteration), 上层两套类型系统**。

---

## 自检题

1. 下面这段为什么不工作?
   ```python
   async def main():
       yield from some_coro()
   ```
   答: `async def` 里禁止 `yield from`, 只能用 `await`。SyntaxError。

2. `await x` 中的 `x` 必须满足什么条件?
   答: 有 `__await__` 方法, 返回一个 iterator (通常是 generator)。

3. `__await__` 内部如果只有 `return value` 没有 `yield`, 会怎样?
   答: 协程**不会暂停**, 直接拿到 value 继续执行。这是「fast path」, 表示「这个 awaitable 立刻就有值」。`asyncio.Future` 在 `done()` 时就走这条路。
