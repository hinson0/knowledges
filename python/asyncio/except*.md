```python

让两种异常都被捕获的改法

让两个 faulty 同时抛(在同一次 event loop tick 里):

async def faulty():
    await asyncio.sleep(0)              # yield 一下让它进入 TaskGroup 调度
    raise ValueError("network error")

async def faulty2():
    await asyncio.sleep(0)
    raise TimeoutError("timeout...")


async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(health("A", 10))
            tg.create_task(health("B", 7))
            tg.create_task(faulty())
            tg.create_task(faulty2())
    except* (ValueError, TimeoutError) as eg:
        print(f"\ncaught {len(eg.exceptions)} exception(s)")
        for exc in eg.exceptions:
            print(f"    {exc.__class__.__name__}: {exc}")

预期输出:

[A] start, will run 10s
[B] start, will run 7s
[A] >>> cancelled <<<
[B] >>> cancelled <<<

caught 2 exception(s)
    ValueError: network error
    TimeoutError: timeout...

为什么?两个 faulty 几乎同时抛,在 TaskGroup 还没来得及 cancel 任何一个之前都已经 raise 了。TaskGroup
会把同一调度回合内抛出的所有异常都收集起来,组成 ExceptionGroup。

except* 的 3 个关键性质

① 可以多个 except* 叠加,各自处理一类

try:
    async with asyncio.TaskGroup() as tg:
        ...
except* ValueError as eg:
    print(f"got {len(eg.exceptions)} ValueError(s)")
except* TimeoutError as eg:
    print(f"got {len(eg.exceptions)} TimeoutError(s)")
except* OSError as eg:
    print(f"got {len(eg.exceptions)} OSError(s)")

注意:跟传统 except 不同,所有 except 都会被尝试,而不是只走第一个匹配。每个 except 拿走自己匹配的部分,剩下的继续往后传。

② 没被任何 except* 接住的异常会再被打包抛出

try:
    async with asyncio.TaskGroup() as tg:
        tg.create_task(faulty())            # ValueError
        tg.create_task(faulty2())           # TimeoutError
except* ValueError:
    pass                                    # 只接 ValueError
# TimeoutError 被重新打包抛出, 这里如果不在外层 try 里就会传播

③ except* 不能写 BaseException / BaseExceptionGroup

except* BaseException:                      # ★ TypeError
    ...

PEP 654 禁止这种「过宽」的 except*,因为它会跟 ExceptionGroup 自身的派生关系冲突。最宽用 except* Exception。

跟传统 except 的语法对照

┌──────────────────┬─────────────────────────────────────────────┐
│       写法       │                    语法                     │
├──────────────────┼─────────────────────────────────────────────┤
│ except T         │ 匹配 T 或子类                               │
├──────────────────┼─────────────────────────────────────────────┤
│ except (T1, T2)  │ 匹配任意一个                                │
├──────────────────┼─────────────────────────────────────────────┤
│ except T as e    │ e 是异常实例                                │
├──────────────────┼─────────────────────────────────────────────┤
│ except* T        │ 从 ExceptionGroup 提取所有匹配 T 的         │
├──────────────────┼─────────────────────────────────────────────┤
│ except* (T1, T2) │ 提取所有匹配任意一个                        │
├──────────────────┼─────────────────────────────────────────────┤
│ except* T as eg  │ eg 是 ExceptionGroup,eg.exceptions 是 tuple │
└──────────────────┴─────────────────────────────────────────────┘

▎ 📌 死记:except* 处理「一组异常」,变量名我习惯用 eg(exception group)。你的 demo 里这么写很对。

一句话总结

▎ 你的语法没问题,但 demo 看到 1 个异常是因为 TaskGroup 的 fail-fast 性质 —— 第一个失败者触发
▎ cancel,后来者来不及抛业务异常。让多个异常都进 ExceptionGroup,需要让它们「同时」抛出。

```
