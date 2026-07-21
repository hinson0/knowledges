我给你整理一份 **Pydantic（以 v2 为主）常用方法 & 用法速查表**，偏实战一点，直接能用 👇

---

# 一、基础模型定义

```python
from pydantic import BaseModel

class User(BaseModel):
    id: int
    name: str
    age: int = 18  # 默认值
```

---

# 二、数据校验（最核心）

## 1. 自动类型转换

```python
user = User(id="1", name="Tom")
print(user.id)  # 1 (自动转 int)
```

---

## 2. 校验失败报错

```python
User(id="abc", name="Tom")
```

👉 会抛出 `ValidationError`

---

# 三、常用方法

## 1. `model_validate()`（替代 v1 的 parse_obj）

```python
data = {"id": 1, "name": "Tom"}
user = User.model_validate(data)
```

---

## 2. `model_dump()`（转 dict）

```python
user.model_dump()
# {'id': 1, 'name': 'Tom', 'age': 18}
```

### 常用参数：

```python
user.model_dump(exclude_none=True)
user.model_dump(include={"id", "name"})
```

---

## 3. `model_dump_json()`（转 JSON）

```python
user.model_dump_json()
```

---

## 4. `model_copy()`（复制对象）

```python
new_user = user.model_copy(update={"name": "Jerry"})
```

---

## 5. `model_fields`（查看字段信息）

```python
User.model_fields
```

---

# 四、字段高级用法

## 1. `Field`（增强字段）

```python
from pydantic import Field

class User(BaseModel):
    id: int = Field(gt=0)   # >0
    name: str = Field(min_length=3, max_length=10)
```

---

## 2. alias（字段别名）

```python
class User(BaseModel):
    user_id: int = Field(alias="id")

data = {"id": 1}
user = User.model_validate(data)
```

---

# 五、校验器（重点）

## 1. `field_validator`

```python
from pydantic import field_validator

class User(BaseModel):
    name: str

    @field_validator("name")
    def check_name(cls, v):
        if len(v) < 3:
            raise ValueError("too short")
        return v
```

---

## 2. `model_validator`

```python
from pydantic import model_validator

class User(BaseModel):
    password: str
    confirm: str

    @model_validator(mode="after")
    def check_password(cls, values):
        if values.password != values.confirm:
            raise ValueError("password mismatch")
        return values
```

---

# 六、环境变量配置（你刚好用得到）

👉 你刚问的 `.env` 就是这个场景

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    db_url: str
    api_key: str

    model_config = {
        "env_file": ".env"
    }

settings = Settings()
```

---

# 七、类型增强（非常实用）

## 1. Optional

```python
from typing import Optional

age: Optional[int] = None
```

---

## 2. List / Dict

```python
from typing import List, Dict

tags: List[str]
meta: Dict[str, str]
```

---

## 3. 嵌套模型

```python
class Profile(BaseModel):
    bio: str

class User(BaseModel):
    profile: Profile
```

---

# 八、序列化控制

## 1. 排除字段

```python
user.model_dump(exclude={"age"})
```

---

## 2. 只输出某些字段

```python
user.model_dump(include={"id"})
```

---

# 九、常见配置（model_config）

```python
class User(BaseModel):
    model_config = {
        "extra": "ignore",   # 忽略多余字段
        "frozen": True,      # 不可变
        "populate_by_name": True  # 支持 alias
    }
```

---

# 十、错误处理

```python
from pydantic import ValidationError

try:
    User(id="abc", name="Tom")
except ValidationError as e:
    print(e.errors())
```

---

# 🚀 给你总结一套“最常用组合”

你实际开发（比如 AI 记账后端）最常用的是：

- `BaseModel` → 定义 schema
- `Field` → 校验规则
- `field_validator` → 自定义校验
- `model_validate` → 解析输入
- `model_dump` → 输出数据
- `BaseSettings` → 管理 `.env`

---

# 如果你要更进阶（推荐）

我可以帮你继续补：

- ✅ FastAPI + Pydantic 最佳实践
- ✅ Pydantic v1 vs v2 差异（很多坑）
- ✅ 结合 Supabase / ORM 用法
- ✅ 你现在这个 Settings 报错的完整修复方案

直接说一声 👍

---

好，那我给你补一份 **🔥 FastAPI + Pydantic 最常用实战模板（直接能用）**，专门贴合你现在在做的 **Python 后端（AI 记账）**场景。

---

# 一、最小可用项目结构

```bash
app/
├── main.py
├── schemas.py   # Pydantic
├── config.py    # Settings
├── routers/
│   └── user.py
```

---

# 二、Pydantic（schemas.py）

```python
from pydantic import BaseModel, Field
from typing import Optional

class UserCreate(BaseModel):
    name: str = Field(min_length=2, max_length=20)
    age: Optional[int] = Field(default=None, ge=0)

class UserResponse(BaseModel):
    id: int
    name: str
    age: Optional[int]
```

👉 规范：

- `Create`：请求体
- `Response`：返回体

---

# 三、配置（config.py）

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    db_url: str
    api_key: str

    model_config = {
        "env_file": ".env"
    }

settings = Settings()
```

---

# 四、路由（routers/user.py）

```python
from fastapi import APIRouter
from app.schemas import UserCreate, UserResponse

router = APIRouter()

fake_db = []

@router.post("/users", response_model=UserResponse)
def create_user(user: UserCreate):
    new_user = {
        "id": len(fake_db) + 1,
        **user.model_dump()
    }
    fake_db.append(new_user)
    return new_user
```

---

# 五、主入口（main.py）

```python
from fastapi import FastAPI
from app.routers import user

app = FastAPI()

app.include_router(user.router)
```

启动：

```bash
uvicorn app.main:app --reload
```

---

# 六、🔥 核心用法解析（非常重要）

## 1. 自动校验 + 自动文档

你写：

```python
def create_user(user: UserCreate):
```

FastAPI 自动帮你做：

- JSON → Pydantic
- 校验参数
- 报错返回 422
- 生成 Swagger 文档

👉 访问：

```
http://localhost:8000/docs
```

---

## 2. response_model（强烈建议用）

```python
@router.post("/users", response_model=UserResponse)
```

作用：

- 自动过滤字段（安全！）
- 自动生成返回结构文档
- 防止你返回多余字段（比如密码）

---

## 3. model_dump()（必须会）

```python
user.model_dump()
```

等价于：

```python
dict(user)
```

但更强（支持 exclude/include）

---

# 七、进阶（你一定会用到）

## 1. ORM 模式（比如接 Supabase / SQLAlchemy）

```python
class UserResponse(BaseModel):
    id: int
    name: str

    model_config = {
        "from_attributes": True
    }
```

👉 可以直接返回 ORM 对象

---

## 2. 自定义校验（记账很有用）

```python
from pydantic import field_validator

class Bill(BaseModel):
    amount: float

    @field_validator("amount")
    def check_amount(cls, v):
        if v <= 0:
            raise ValueError("金额必须大于0")
        return v
```

---

## 3. 多层嵌套（账单分类）

```python
class Category(BaseModel):
    name: str

class Bill(BaseModel):
    amount: float
    category: Category
```

---

# 八、你现在这个报错本质原因（点你一下）

你之前那个：

> 缺少传入值 glm_api_key...

👉 本质是：

```python
settings = Settings()
```

但 `.env` 没有对应变量

---

✅ 正确 `.env` 示例：

```env
DB_URL=xxx
API_KEY=xxx
```

---

# 九、给你一套“生产级建议”（重点）

你做 AI 记账，建议这样分层：

```
schemas/   👉 Pydantic（输入输出）
models/    👉 数据库
services/  👉 业务逻辑
routers/   👉 API
config/    👉 Settings
```

---

# 🚀 如果你下一步想继续优化

我可以帮你直接升级到：

- ✅ FastAPI + Supabase（你现在正用）
- ✅ JWT 登录体系
- ✅ AI记账（OCR → LLM → 入库完整链路）
- ✅ 异常处理 + 日志体系（生产级）

直接说一句你要哪个 👍
