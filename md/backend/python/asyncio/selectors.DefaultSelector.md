`selectors.DefaultSelector()` 是 Python 标准库提供的一个 **I/O 多路复用（I/O Multiplexing）抽象接口**。简单说，它是一个 **“系统级 I/O 事件监听器”**。

### 一句话解释

它能同时盯着多个网络连接（socket），哪个连接有数据来了、或者能写数据了，它会立刻通知你。**没有它，你只能一个连接一个连接地死等，程序就卡住了。**

### 在 Demo 中的作用

在你的 `MiniLoop` 里，它是事件循环的 **“眼睛”**。

```python
self.selector = selectors.DefaultSelector()
```

- **注册监听**：`selector.register(sock, EVENT_READ, data=callback)`  
  相当于告诉操作系统：“帮我盯着这个 `sock`，一旦它能读了，立刻叫我。”

- **等待事件**：`selector.select(timeout=0.1)`  
  相当于事件循环问操作系统：“刚才有谁准备好了吗？”，如果有，操作系统返回准备好的 socket 列表。

- **触发回调**：拿到列表后，事件循环执行对应的回调（`callback()`），也就是 `_on_readable` 函数，把数据塞进 `Future`。

### 为什么叫 `DefaultSelector`？

它不是一个具体的底层技术，而是一个**智能选择器**：

| 操作系统    | 底层实现 | 特点                     |
| :---------- | :------- | :----------------------- |
| Linux       | `epoll`  | 最高效，能处理数万个连接 |
| macOS / BSD | `kqueue` | 同样高效                 |
| Windows     | `select` | 兼容性好，但性能稍弱     |

`DefaultSelector()` 会自动检测你的操作系统，选择最优的那个，省得你自己写一堆 `if` 判断。

### 通俗比喻

想象你是一个餐厅服务员（事件循环），有 50 张桌子（socket 连接）。

- **没有 Selector**：你必须轮流站在每张桌子旁边问：“要加菜吗？要结账吗？”（忙轮询，累死且效率低）。
- **有了 Selector**：每张桌上有个按铃。你只需要在吧台等着，**哪个按铃响了（`select` 返回）**，你就去服务哪一桌。

在你的 Demo 里，`_on_readable` 函数就是 **“按铃触发后的处理动作”**——去后厨端菜（读 `recv` 数据）并放到客人的箱子里（`future.set_result`）。
