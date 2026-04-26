太好了，这个需求很实用。下面给你一份 **Pydantic v2 实战速查表**，按“你写业务代码时最常碰到的场景”来排。

---

## **1) 模型定义 & 基础校验**

```python
from pydantic import BaseModel, EmailStr, Field

class User(BaseModel):
    id: int
    name: str = Field(min_length=2, max_length=20)
    email: EmailStr
    age: int = Field(ge=0, le=150)
```

- `BaseModel`：所有模型基类
- `Field(...)`：约束、描述、别名、默认值工厂等
- 常见约束：`gt/ge/lt/le/min_length/max_length/pattern`

---

## **2) 入参校验（最常用）**

### `model_validate()`：从 dict/对象创建并校验

```python
payload = {"id": "1", "name": "Tom", "email": "tom@example.com", "age": 18}
user = User.model_validate(payload)  # 自动类型转换 + 校验
```

### `ValidationError`

```python
from pydantic import ValidationError

try:
    User.model_validate({"id": "x"})
except ValidationError as e:
    print(e.errors())  # 结构化错误，适合返回前端
```

---

## **3) 输出序列化（接口返回/入库前）**

### `model_dump()`：转 dict

```python
data = user.model_dump()
data_no_none = user.model_dump(exclude_none=True)
data_public = user.model_dump(exclude={"email"})
```

### `model_dump_json()`：转 JSON 字符串

```python
json_str = user.model_dump_json()
```

---

## **4) 字段别名（前后端字段不一致）**

```python
from pydantic import BaseModel, Field, ConfigDict

class Item(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    item_id: int = Field(alias="itemId")
    item_name: str = Field(alias="itemName")

obj = Item.model_validate({"itemId": 1, "itemName": "Keyboard"})
print(obj.model_dump(by_alias=True))  # {'itemId': 1, 'itemName': 'Keyboard'}
```

---

## **5) 自定义校验器（重点）**

### 字段级：`@field_validator`

```python
from pydantic import BaseModel, field_validator

class Register(BaseModel):
    password: str

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("password too short")
        return v
```

### 模型级：`@model_validator`

```python
from pydantic import BaseModel, model_validator

class ChangePwd(BaseModel):
    old_password: str
    new_password: str

    @model_validator(mode="after")
    def check_diff(self):
        if self.old_password == self.new_password:
            raise ValueError("new_password must be different")
        return self
```

---

## **6) 默认值与动态默认**

```python
from datetime import datetime
from pydantic import BaseModel, Field

class Log(BaseModel):
    created_at: datetime = Field(default_factory=datetime.utcnow)
```

- `default_factory`：每次实例化动态生成值（时间戳、UUID等）

---

## **7) 配置项（v2 用 `ConfigDict`）**

```python
from pydantic import BaseModel, ConfigDict

class M(BaseModel):
    model_config = ConfigDict(
        extra="forbid",      # 禁止多余字段
        str_strip_whitespace=True,  # 自动去首尾空格
        frozen=False,        # 是否不可变
        validate_assignment=True,   # 赋值时也校验
    )
```

---

## **8) 嵌套模型（复杂请求体）**

```python
from pydantic import BaseModel

class Address(BaseModel):
    city: str
    zip_code: str

class Profile(BaseModel):
    user_id: int
    address: Address
```

- 自动递归校验
- 非常适合 FastAPI 的复杂 JSON body

---

## **9) 列表 / 联合类型**

```python
from typing import Literal, Union
from pydantic import BaseModel

class Cat(BaseModel):
    type: Literal["cat"]
    meow: int

class Dog(BaseModel):
    type: Literal["dog"]
    bark: int

Pet = Union[Cat, Dog]
```

- `Literal` 常用于判别字段
- 多态 payload 常用 `Union`

---

## **10) 实战：`.env` 配置（pydantic-settings）**

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    db_url: str
    redis_url: str
```

- `BaseSettings` 自动读环境变量
- 如果遇到 basedpyright 对 `Settings()` 的静态误报，可用“默认值 + model_validator 强校验”方案规避

---

## **11) v1 -> v2 迁移高频映射**

- `dict()` → `model_dump()`
- `json()` → `model_dump_json()`
- `parse_obj()` → `model_validate()`
- `@validator` → `@field_validator`
- `@root_validator` → `@model_validator`
- `class Config:` → `model_config = ConfigDict(...)`

---

## **12) 业务里最推荐的组合（开箱即用）**

- 入参：`model_validate()`
- 输出：`model_dump(exclude_none=True)`
- 规则：字段用 `Field`，跨字段用 `model_validator`
- 安全：`extra="forbid"`（防脏字段）
- 可维护：错误统一用 `ValidationError.errors()` 转 API 错误格式

---

如果你要，我可以下一条直接给你一份 **“后端项目常用 Pydantic 模板”**（请求模型 / 响应模型 / 分页模型 / 错误模型 / Settings 模型），你可以直接复制到项目里用。

---

好，给你一套**可直接复制**的 Pydantic v2 后端模板（偏 FastAPI / 常规后端）。

**模板内容**

- 请求模型（Create / Update）
- 响应模型（Public / Detail）
- 分页模型（统一返回）
- 错误模型（统一错误体）
- Settings 模型（避免 basedpyright `Settings()` 报错写法）

```python
from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


# =========
# 通用基类
# =========

class APIModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid",              # 禁止脏字段
        str_strip_whitespace=True,   # 自动 trim 字符串
        validate_assignment=True,    # 赋值时也校验
    )


# =========
# 业务模型（示例：用户）
# =========

class UserCreate(APIModel):
    name: str = Field(min_length=2, max_length=30)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserUpdate(APIModel):
    name: str | None = Field(default=None, min_length=2, max_length=30)
    email: EmailStr | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)


class UserPublic(APIModel):
    id: int
    name: str
    email: EmailStr
    created_at: datetime


class UserDetail(UserPublic):
    last_login_at: datetime | None = None
    is_active: bool = True


# =========
# 分页模型
# =========

T = TypeVar("T")

class PageMeta(APIModel):
    page: int = Field(ge=1)
    page_size: int = Field(ge=1, le=100)
    total: int = Field(ge=0)


class PageResult(APIModel, Generic[T]):
    items: list[T]
    meta: PageMeta


# =========
# 错误模型
# =========

class APIError(APIModel):
    code: str
    message: str
    detail: dict | list | str | None = None


# =========
# Settings（basedpyright 友好）
# =========

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    glm_api_key: str = ""
    tencent_secret_id: str = ""
    tencent_secret_key: str = ""
    supabase_url: str = ""
    supabase_service_role_key: str = ""

    @model_validator(mode="after")
    def validate_required(self) -> "Settings":
        required = (
            "glm_api_key",
            "tencent_secret_id",
            "tencent_secret_key",
            "supabase_url",
            "supabase_service_role_key",
        )
        missing = [k for k in required if not getattr(self, k)]
        if missing:
            raise ValueError(f"Missing env vars: {', '.join(missing)}")
        return self


settings = Settings()
```

**怎么用（实战）**

- 入参校验：`UserCreate.model_validate(payload)`
- 返回数据：`user.model_dump(exclude_none=True)`
- 分页返回：`PageResult[UserPublic](items=data, meta=meta)`
- 错误统一：返回 `APIError(code="VALIDATION_ERROR", message="...")`

如果你要，我下一条可以按你项目目录直接拆成：

- `schemas/user.py`
- `schemas/common.py`
- `config.py`（替换你当前 [config.py](file:///Users/a114514/coco/.claude/worktrees/refactor-backend/apps/backend/config.py)）  
  并给你一份一键粘贴版。
