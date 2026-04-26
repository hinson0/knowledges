# SQLAlchemy `echo=True` — 引擎 SQL 日志开关

## 作用

`create_engine` / `create_async_engine` 的参数，打开后会把引擎**实际发给数据库的每一条 SQL**（含参数绑定和耗时）打印到标准输出。

```python
aengine = create_async_engine(
    f"sqlite+aiosqlite:///{db}",
    echo=True,
)
```

## 原理

本质是给 `sqlalchemy.engine` 这个 logger 挂了个 `INFO` 级别的 handler。

等价于：

```python
import logging
logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
```

所以如果项目已经配置了 logging，`echo=True` 会和你的 logger 打架（重复输出）。这时用 `echo=False` + 手动配 logger 更干净。

## 可选值

| 值 | 行为 |
|---|---|
| `False`（默认） | 不输出 |
| `True` | 输出每条 SQL + 参数 |
| `"debug"` | 额外输出**查询结果的每一行**（调试数据用） |

配套参数：

- `echo_pool=True` — 只打印连接池事件（获取/归还/回收），定位连接池耗尽或泄漏时比 `echo=True` 有针对性，不会被海量 SQL 淹没。

## 适用场景

| 场景 | 建议 |
|---|---|
| 学习 SQLAlchemy、看 ORM→SQL 翻译 | `True` |
| 调试 N+1、慢查询 | `True` |
| 定位连接池问题 | `echo_pool=True` |
| **生产环境** | **必须 `False`** |

## 生产禁用的三个理由

1. **性能**：每条 SQL 都打日志，I/O 开销大。
2. **安全/合规**：参数明文输出，密码、token 会被原样记录到日志文件。
3. **日志爆炸**：高 QPS 场景下会淹没真正重要的日志。
