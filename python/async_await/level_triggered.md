```python
⏺ ★ Insight ─────────────────────────────────────
  • Python `selectors` 模块默认就是 level-triggered(LT) —— 这跟
  select/poll/epoll(默认)行为一致,所以你写代码不用关心模式选择,但**必须懂它的语义**
  • LT vs ET 的差异在你 demo 没读完数据时才暴露:LT 下 select 会反复唤醒你直到读干净;ET 下只叫一次,漏读就丢
  • asyncio 整个体系建立在 LT 假设上 —— 这就是为什么 `add_reader` 不要求你「一次读完」,你下一轮还会被叫醒
  ─────────────────────────────────────────────────

  Level-Triggered(LT)vs Edge-Triggered(ET)

  这是 OS 内核通知就绪事件的两种语义,是 select/poll/epoll/kqueue 这类多路复用器的核心设计选择。

  一句话定义

  ┌───────────────────────────┬───────────────────────────────────────────────┐
  │           模式            │                   通知语义                    │
  ├───────────────────────────┼───────────────────────────────────────────────┤
  │ Level-Triggered(电平触发) │ 「只要条件满足,我就一直告诉你」               │
  ├───────────────────────────┼───────────────────────────────────────────────┤
  │ Edge-Triggered(边沿触发)  │ 「条件从不满足变满足的那一刻,我只告诉你一次」 │
  └───────────────────────────┴───────────────────────────────────────────────┘

  电路类比(名字的来源)

  把 fd 的可读状态想成一个电压信号:

  fd 不可读: ─────┐                       ┌──────  (低电平)
                  │                       │
  fd 可读:        └───────────────────────┘        (高电平)
                  ↑   ↑   ↑   ↑   ↑   ↑   ↑
  LT 通知:        ✓   ✓   ✓   ✓   ✓   ✓   ✓        (高电平期间每次 select 都返回)
                  ↑                       ↑
  ET 通知:        ✓                       ✗        (只在「上升沿」通知一次)
                                          (这里是「下降沿」, ET 模式不通知)

  - Level:看「电平高低」,高电平期间每次轮询都被报告
  - Edge:看「边沿跳变」,只在状态切换的瞬间被报告

  ---
  实例对比

  假设 socket a 收到 1500 字节数据,你的 on_readable 只 recv(500)(只读了 500)。

  Level-Triggered(我们用的模式)

  T=0   1500 字节到达 → fd 变可读
  T=1   selector.select() 返回 a → on_readable() 调 recv(500), 还剩 1000
  T=2   selector.select() **再次返回 a** → 你又被叫醒
        → on_readable() 调 recv(500), 还剩 500
  T=3   selector.select() **再次返回 a**
        → on_readable() 调 recv(500), 剩 0
  T=4   selector.select() 阻塞(没数据了, 进入低电平)

  ▎ ✅ 省心:即使你一次没读完,下次还会被叫,数据不会丢。代价是一些性能(多几次 syscall)。

  Edge-Triggered

  T=0   1500 字节到达 → fd 「上升沿」
  T=1   selector.select() 返回 a → on_readable() 调 recv(500), 还剩 1000
  T=2   selector.select() **不返回 a**!(没有新的上升沿)
        → 永远阻塞, 那 1000 字节烂在内核 buffer 里

  ▎ ⚠️ 凶险:漏读会导致永久卡死。ET 下的正确写法必须是 while True: recv(...) 循环读到 BlockingIOError (EAGAIN)。

  ET 的正确读法(为什么 ET 写起来累)

  def on_readable_ET():
      while True:
          try:
              data = sock.recv(4096)
              if not data:                      # 对端关闭
                  close_and_unregister()
                  return
              handle(data)
          except BlockingIOError:               # buffer 空了 → 跳出
              break

  LT 下你想这样写也行,但不写也无所谓;ET 下必须这样写。

  ---
  在 Python selectors 里的体现

  selectors.DefaultSelector 在各平台底层映射:

  ┌─────────────┬──────────────────────────┬────────────────────────────────────────┐
  │    平台     │           底层           │                  模式                  │
  ├─────────────┼──────────────────────────┼────────────────────────────────────────┤
  │ Linux       │ epoll(不带 EPOLLET flag) │ LT                                     │
  ├─────────────┼──────────────────────────┼────────────────────────────────────────┤
  │ macOS / BSD │ kqueue                   │ LT(kqueue 默认 LT,可设 EV_CLEAR 切 ET) │
  ├─────────────┼──────────────────────────┼────────────────────────────────────────┤
  │ Windows     │ select                   │ LT(select 没有 ET)                     │
  └─────────────┴──────────────────────────┴────────────────────────────────────────┘

  结论:Python 标准库 selectors 全平台统一是 LT。你目前写的所有代码都不需要担心 ET 陷阱。

  asyncio 同理 —— loop.add_reader 内部用的就是 selectors,LT 语义。

  ---
  跟我们 Phase 2 demo 的关联

  回顾你 demo 的 on_readable:

  def on_readable():
      data = a.recv(1024)
      print(f"a received: {data!r}")
      loop.remove_reader(a.fileno())          # 读完就取消关心

  ▎ ❓ 思考:如果不调 remove_reader,而 b 刚才 send(b"hello from b")(12 字节),你 recv(1024) 一次读完了 —— 下一轮 select 会再次返回 a
  ▎ 吗?

  不会。LT 的语义是「只要可读就通知」 —— 你已经把 12 字节读完,fd 现在不可读(内核 buffer 空了),下次 select 不会唤醒。

  但如果 b 又 send 了新数据,a 又变可读,select 又会唤醒 on_readable 。

  这就是 LT 让你写代码省心的地方 —— 你的回调不需要循环读到 EAGAIN,因为没读完下次还会被叫;读完了下次不被叫。

  ▎ ❓ 更刁钻的:如果你 recv(2)(只读 2 字节),还剩 10 字节在 buffer,你不调 remove_reader,会发生什么?

  陷入 busy loop —— 但不是 100% CPU 那种,而是 selector 每轮都立刻返回 a,你每次只读 2 字节,直到 12 字节读完才安静。这期间 event loop
  跑了 6 轮,每轮都唤醒一次。

  这不算 bug(数据不丢),但是性能浪费。生产代码里通常用大 buffer(recv(65536))一次尽量读多。

  ---
  ET 在哪里有用

  ET 的优势在超大并发(C10M):

  - LT 下,10 万个 fd 里有 1 万个一直「半就绪」(buffer 里始终有少量数据),每次 epoll_wait 都返回这 1 万个 → 系统调用变贵
  - ET 下,只在状态跳变时通知一次,空转 syscall 大幅减少

  代价:必须配合非阻塞 socket + 循环读到 EAGAIN,代码复杂度高。

  著名的高性能服务器(Nginx、Redis、libevent 部分)用 ET。Python asyncio 不追求那个量级,LT 够用且简单。

  ---
  一句话总结

  ▎ Phase 2 你看到的 on_readable 之所以可以「不一次读完也没事」,根源是 selectors 默认 LT。换 ET 你的代码就要重写。

  回到你 Phase 2 任务,继续动手就好,LT 这个名字记下来 —— 后面我们 review 你 Phase 2 代码时会再次提到「为什么 remove_reader 之前 fd
  一直处于 LT 触发状态」。

```
