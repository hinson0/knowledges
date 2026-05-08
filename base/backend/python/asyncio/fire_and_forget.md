⏺ ★ Insight ─────────────────────────────────────
• "Fire-and-forget" 是个军事术语 —— 导弹发射后不需要持续制导,「发射即忘」。编程世界借用过来,描述「启动一个任务后不等它完成,继续做别的」
• 在 asyncio 里这是 `create_task` 与 `await` 的本质区别:前者是 fire-and-forget(并发),后者是同步等待(串行)
─────────────────────────────────────────────────

字面含义

Fire-and-forget = 发射就忘:启动任务 → 转身离开 → 不等结果。

在 asyncio 里的具体表现

# ❌ 不是 fire-and-forget(等任务完成)

result = await some_task()
print("继续") # 必须等 some_task 跑完才到这里

# ✅ Fire-and-forget(发射就忘)

task = asyncio.create_task(some_task())
print("继续") # 立刻执行, some_task 在后台跑

实际场景

回想你 Phase 5 echo server:

async def main():
while True:
conn, addr = await sock_accept(loop, server_sock)
Task(echo_handler(conn, addr), loop) # ★ fire-and-forget # 立刻继续 accept 下一个连接, 不等当前 handler 跑完

如果不是 fire-and-forget:

async def main():
while True:
conn, addr = await sock_accept(loop, server_sock)
await echo_handler(conn, addr) # ← 串行 # 必须等当前客户端断开, 才能 accept 下一个 → 一次只服务一个客户端

这就是 fire-and-forget 在并发 server 里的核心价值:server 能同时服务多个客户端。

常见的现实类比

┌──────────────┬────────────────────────────────┐
│ 场景 │ Fire-and-forget │
├──────────────┼────────────────────────────────┤
│ 后台日志写入 │ 写一条日志,继续主流程,不等磁盘 │
├──────────────┼────────────────────────────────┤
│ 推送通知 │ 把消息扔进队列,立刻返回 │
├──────────────┼────────────────────────────────┤
│ 缓存预热 │ 异步刷新缓存,不阻塞用户请求 │
├──────────────┼────────────────────────────────┤
│ 监控上报 │ 上报指标到监控系统,不等响应 │
└──────────────┴────────────────────────────────┘

关键陷阱:不能真的「忘」

Fire-and-forget 在 asyncio 里有个臭名昭著的坑:

# ❌ 危险

async def main():
asyncio.create_task(background_work()) # 没保留引用
await asyncio.sleep(10)

Python 的 GC 可能在中途把 task 回收,任务没跑完就被吞了。所以严格说 asyncio 的 fire-and-forget 不能完全「forget」 —— 你必须至少保留引用:

# ✅ 安全

\_tasks = set()

async def main():
t = asyncio.create_task(background_work())
\_tasks.add(t)
t.add_done_callback(\_tasks.discard) # 完成后从 set 里移除
await asyncio.sleep(10)

对比记忆

┌───────────────────┬─────────────────────────┬───────────────────────────┐
│ │ 语义 │ 何时用 │
├───────────────────┼─────────────────────────┼───────────────────────────┤
│ await coro │ 等它跑完拿结果 │ 我需要它的结果才能继续 │
├───────────────────┼─────────────────────────┼───────────────────────────┤
│ create_task(coro) │ 让它跑,我接着干别的 │ 后台任务、并发处理多事 │
├───────────────────┼─────────────────────────┼───────────────────────────┤
│ gather(\*coros) │ 同时启动所有,等全部完成 │ 并发跑一组任务,都需要结果 │
└───────────────────┴─────────────────────────┴───────────────────────────┘

▎ 📌 死记:看到 create_task / Task(coro, loop) / loop.spawn 这种 API,基本就是 fire-and-forget 模式。Go 的 go func()、JS 的 void promise、Erlang 的
▎ spawn 也都是同一个概念。
