# Python Annotated 类型 — 给类型附加元数据

> `typing.Annotated` 在不改变基础类型的前提下，附加任意元数据。
> Python 3.9+ 原生支持，3.8 用 `typing_extensions`。

## 基础语法

```python
from typing import Annotated

# x 的类型是 str，但附带了额外元数据
x: Annotated[str, "一些元数据"]
#            ^^^   ^^^^^^^^^^^
#            基础类型  元数据（可以是任何东西）
```

## 核心特性

- 第一个参数是**基础类型**，后面都是**元数据**
- 对运行时类型检查没有影响，`Annotated[str, ...]` 本质还是 `str`
- 元数据由框架自行解读（FastAPI、Pydantic 等各取所需）

## 在 FastAPI 中的用法：依赖注入

```python
from typing import Annotated
from fastapi import Depends

# 定义可复用的依赖别名
UserId = Annotated[str, Depends(get_current_user)]

@router.post("/push")
async def sync_push(user_id: UserId):
    # FastAPI 自动调用 get_current_user()，将返回值注入 user_id
    ...
```

等价于老写法（每个路由重复声明）：

```python
@router.post("/push")
async def sync_push(user_id: str = Depends(get_current_user)):
    ...
```

**优势**：定义一次，到处复用；改依赖逻辑只需改一处。

## 在 Pydantic 中的用法：字段校验

```python
from typing import Annotated
from pydantic import BaseModel, Field

PositiveFloat = Annotated[float, Field(gt=0, description="必须为正数")]

class Budget(BaseModel):
    amount: PositiveFloat  # 自动校验 > 0
```

## 在 FastAPI 中的用法：请求参数校验

```python
from typing import Annotated
from fastapi import Query, Path

@router.get("/items/{item_id}")
async def get_item(
    item_id: Annotated[int, Path(ge=1)],           # 路径参数 >= 1
    q: Annotated[str | None, Query(max_length=50)] = None,  # 查询参数
):
    ...
```

## 可以叠加多个元数据

```python
# 多个元数据用逗号分隔，各框架各取所需
x: Annotated[str, Field(max_length=100), "额外说明"]
```

## 总结

| 场景             | 元数据              | 效果                       |
| ---------------- | ------------------- | -------------------------- |
| FastAPI 依赖注入 | `Depends(func)`     | 自动调用 func 并注入返回值 |
| FastAPI 参数校验 | `Query()`, `Path()` | 校验请求参数               |
| Pydantic 字段    | `Field(...)`        | 字段约束和文档             |
| 自定义           | 任意对象            | 框架自行解读               |
