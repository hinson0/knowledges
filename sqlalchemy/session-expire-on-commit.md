# SQLAlchemy `expire_on_commit` — commit 后对象是否立刻过期

## 作用

`sessionmaker` / `async_sessionmaker` 的参数，控制 `session.commit()` 之后，通过 session 加载/添加的 ORM 对象是否"过期"（expire）。

```python
asession = async_sessionmaker(
    bind=aengine,
    expire_on_commit=False,
)
```

## 两种取值对比

| 值 | commit 后的对象行为 |
|---|---|
| `True`（默认） | 所有属性标记为脏数据，下次访问任意属性**自动发 SELECT** 重新加载 |
| `False` | 保留内存值，访问属性不触发额外查询 |

## 直观示例

```python
# expire_on_commit=True（默认）
user = User(username="alice")
s.add(user)
await s.commit()
print(user.username)   # 触发一次 SELECT

# expire_on_commit=False
user = User(username="alice")
s.add(user)
await s.commit()
print(user.username)   # 直接读内存，不查库
```

## 为什么 async 场景几乎**必须**设 `False`

```python
async with asession() as s:
    user = await s.get(User, 1)
    await s.commit()
# session 已关闭
print(user.username)
# 💥 MissingGreenlet: greenlet_spawn has not been called
```

原因链：

1. `expire_on_commit=True` → 访问属性会触发 SQL
2. 属性访问是**同步语法**（没 `await`）
3. async engine 要求所有 I/O 必须 await
4. 抛异常

所以异步代码里关掉是标准配方。

## 为什么 FastAPI 场景也推荐 `False`

FastAPI 接口里常见模式：

```python
async def get_user(id: int, s: AsyncSession = Depends(...)):
    user = await s.get(User, id)
    await s.commit()
    return user   # Pydantic 序列化时访问属性
```

如果 `expire_on_commit=True`，序列化时触发隐式查询，但此时 session 可能已归还连接池 → 报错。

## 代价与补偿手段

关掉后**失去的能力**：

- 其他事务在 commit 间隙改了同一行，你手里的对象感知不到（仍是旧值）。
- 多人写同一行的业务（库存扣减、计数器）要特别小心。

**补偿手段**（显式刷新）：

| API | 作用 |
|---|---|
| `await s.refresh(user)` | 强制从 DB 重新加载该对象 |
| `s.expire(user)` | 仅让某个对象过期（下次访问时再查） |
| `asession(expire_on_commit=True)` | 为单个 session 临时覆盖默认值 |

## 决策速查

| 场景 | 推荐 |
|---|---|
| async SQLAlchemy | **`False`**（硬性约束） |
| FastAPI 同步 session，commit 后要返回对象 | `False` |
| 高并发同步 + 数据新鲜度要求高 | `True`（默认） |
