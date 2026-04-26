```python

★ Insight ─────────────────────────────────────
• fd 是 Unix「一切皆文件」哲学的核心抽象 —— socket、管道、终端、真实文件,在 OS 眼里都是同一种东西,统一靠 fd 操作
• Python 里几乎所有 I/O 对象都有 `.fileno()` 方法返回它的 fd —— 这就是为什么 selector 能同时监听 socket
和文件:它根本不区分类型,只看 fd
• fd 是「**进程内**」的编号,跨进程没有意义 —— 同一个数字 5 在 A 进程和 B 进程指不同对象
─────────────────────────────────────────────────

fd = file descriptor(文件描述符)

它是一个小整数,通常是 0、1、2、3、4...

一句话定义

▎ fd 是 OS 内核给进程的「句柄编号」 —— 进程要操作任何 I/O
▎ 对象(文件、socket、管道、终端、设备),都不直接拿对象本身,而是拿这个编号去问 OS:「编号 5 的那个东西,给我读 100 字节」。

为什么是「文件」描述符却能管 socket?

这是 Unix 设计哲学:一切皆文件(everything is a file)。

- 你打开 /tmp/a.txt —— 拿到一个 fd
- 你 socket.socket() —— 拿到一个 fd
- 你 os.pipe() —— 拿到两个 fd(读端 + 写端)
- 你的 stdin / stdout / stderr —— 它们就是 fd 0 / 1 / 2(进程启动时 OS 默认给的)

对内核来说,所有 fd 都用同一套 syscall 操作:read()、write()、close()、select()、poll()、epoll()...

▎ 这就是为什么 selectors.DefaultSelector 能同时监听 stdin、socket、pipe —— 它根本不关心你这个 fd 背后是什么,只关心「fd 5
▎ 现在能不能读」这种问题。

在 Python 里怎么拿到 fd

每个有 fd 的对象都有 .fileno() 方法:

import socket, sys

s = socket.socket()
print(s.fileno()) # 比如输出: 4

print(sys.stdin.fileno()) # 0
print(sys.stdout.fileno()) # 1
print(sys.stderr.fileno()) # 2

f = open('/tmp/a.txt', 'w')
print(f.fileno()) # 比如输出: 5

fd 编号是怎么分配的

OS 维护一张「进程 fd 表」,新打开一个对象就给一个最小可用编号:

进程刚启动:
fd 表 = { 0: stdin, 1: stdout, 2: stderr }

调用 socket.socket() →
fd 表 = { 0: stdin, 1: stdout, 2: stderr, 3: socket } ← 给最小可用 = 3

再调用 open('a.txt') →
fd 表 = { 0:..., 1:..., 2:..., 3: socket, 4: file } ← 给 4

close(3) 之后再 socket.socket() →
fd 表 = { 0:..., 1:..., 2:..., 3: socket(new), 4: file } ← 3 空了, 复用

▎ 所以 fd 编号会被复用 —— 这是个常见 bug 来源:你 close 了 fd 5,然后另一个对象拿到 fd 5,你的旧代码还在用旧的 fd 5
▎ 引用,就会读到错的对象。在 asyncio 里 remove_reader 之后立刻 close 是必要的。

fd 在 Phase 2 代码里出现的地方

回到我们的 demo:

a, b = socket.socketpair() # 拿到两个 socket 对象
loop.add_reader(a.fileno(), on_readable) # ← 用 .fileno() 取 fd 给 selector
↑
这里传的就是一个小整数, 比如 4

selector.register(fd, EVENT_READ, ...) 内部调用 kqueue / epoll 把这个数字提交给内核:「请在 fd=4 可读时通知我」。

能动手验证一下

跑一下这段,亲眼看到 fd 复用:

import socket
for i in range(3):
s = socket.socket()
print(f"socket #{i}: fd =", s.fileno())
s.close()

# 输出大概率三次都是同一个数字, 比如全是 4

因为每次 close 后那个数字立刻被释放,下次又被分配。

---
```
