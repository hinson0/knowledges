```python
⏺ ★ Insight ─────────────────────────────────────
  • `writer.write()` 是**同步**且**非阻塞**的 — 它只把数据塞进 asyncio 的内部缓冲区,不等真的发出去。如果你不停
  write,缓冲区会无限增长,内存爆炸。`drain()` 是**背压(backpressure)** 机制:写得太快时主动让出 CPU,等缓冲区降下来再继续
  • 这是 asyncio Streams API 的一个不对称设计:**read 是 async,write 是 sync** — 因为读必须等数据来,写可以立刻塞缓冲。`drain`
  是这个不对称的「修补」,让你显式表达「我愿意等」
  ─────────────────────────────────────────────────

  一张图说清楚

  你的代码                     asyncio 内部缓冲                  操作系统 send buffer
     │                              │                                  │
     │── writer.write(data) ───────►│                                  │
     │   (立刻返回, 不阻塞)           ▼                                  │
     │                          [data 排队]                             │
     │                              │                                  │
     │                              │── 后台 transport ───────────────►│
     │                              │   (写到 OS, 这才是真的网络发送)   │
     │                              │                                  │
     │── await writer.drain() ◄─────┤  缓冲区还高于水位线 → 卡住等       │
     │                              │  缓冲区降到低水位线 → 唤醒你       │
     ▼                              ▼                                  ▼

  核心:write() 是「往传送带上扔包裹」,drain() 是「等传送带不那么挤了再继续扔」。

  不用 drain 会怎样?

  async def attacker():
      reader, writer = await asyncio.open_connection('slow-server', 80)
      while True:
          writer.write(b"x" * 1024 * 1024)   # ★ 1MB 一次, 死命写, 不 drain
          # 服务器很慢只能消费 1KB/s
          # 你的进程内存每秒涨 1MB → OOM

  write() 永远不会让你「等等」,它是 fire-and-forget 风格。慢消费者那边接收不过来,数据全堆在你这一侧的 asyncio 缓冲区里。

  ▎ 📌 真实事故:某个服务往日志收集器写日志,日志服务器卡住,服务进程内存几分钟涨到 32GB,被 OOM kill。原因就是 write 不配 drain。

  用 drain 的标准模式

  async def write_safely(writer, data):
      writer.write(data)                # 入缓冲
      await writer.drain()              # ← 关键: 等缓冲降下来

  drain 是 asyncio 的「信用卡限额检查」:
  - 缓冲 < 低水位线(默认 16KB) → drain 立刻返回,继续写
  - 缓冲 ≥ 高水位线(默认 64KB) → drain 卡住,直到缓冲被发出去降到低水位

  你之前写的 echo server,实战示例

  async def handle_client(reader, writer):
      data = await reader.read(1024)
      writer.write(b"echo: " + data)
      await writer.drain()              # ★ 让 OS 把数据真的送出去
      writer.close()
      await writer.wait_closed()

  如果省略 drain,通常也能跑 —— 但在「客户端慢 + 你疯狂 echo」的场景下会出问题。

  一句话记忆

  ▎ writer.write() 不阻塞,只入缓冲;await writer.drain() 才是「等真的发出去」的地方。 高并发或大数据量场景必加 drain,否则迟早 OOM。

  何时可以省略

  writer.write(small_data)
  writer.close()
  await writer.wait_closed()           # close 会等所有缓冲数据发完

  - 数据量小、连接立刻关闭 → 不用 drain(close 会兜底)
  - 一次性短交互(发个请求拿个响应) → 不用
  - 长连接、流式发送、循环写入 → 必须用

  完整循环写示例

  async def stream_video(writer, frames):
      for frame in frames:               # 假设有 1000 帧
          writer.write(frame)            # 入缓冲(立即返回)
          await writer.drain()           # 等缓冲压力降下来再发下一帧
      writer.close()
      await writer.wait_closed()

  每一帧后都 drain,保证生产速度跟消费速度匹配。这就是协程版的 backpressure。
```
