# 12 — 大型 FastAPI 项目中，如何组织路由、模型、依赖项和配置？

> 来源：`~/fastapi_web/src/interview/12.py`。Python + FastAPI 面试题第 12 题答案。题目清单见 `2.printed.md:23`。

## 概念

在 FastAPI 官方文档中推荐"按功能/领域模块化"组织项目，同时结合分层架构思想。以下是一种经过验证的、生产环境友好的目录结构。

## 推荐目录结构

```text
myproject/
├── app/
│   ├── main.py                  # 应用程序入口，创建 FastAPI 实例，挂载路由
│   ├──   /
│   │   ├── config.py            # 环境变量加载、Pydantic Settings 配置类
│   │   ├── security.py          # 认证、JWT、密码哈希等
│   │   └── events.py            # 启动/关闭事件（lifespan）
│   ├── db/
│   │   ├── session.py           # 数据库引擎、会话管理
│   │   └── base.py              # SQLAlchemy Base 类
│   ├── models/                  # 数据库模型（ORM 表定义）
│   │   ├── user.py
│   │   └── item.py
│   ├── schemas/                 # Pydantic 模型（请求/响应/验证）
│   │   ├── user.py
│   │   └── item.py
│   ├── api/
│   │   ├── deps.py              # 公共依赖项（例如 get_current_user, get_db）
│   │   └── v1/
│   │       ├── router.py        # 汇总当前版本所有路由
│   │       ├── endpoints/
│   │       │   ├── users.py     # 用户相关端点
│   │       │   └── items.py     # 物品相关端点
│   │       └── dependencies.py  # v1 特有依赖项
│   ├── services/                # 业务逻辑层
│   │   ├── user_service.py
│   │   └── item_service.py
│   ├── repositories/            # 数据访问层（可选，有时 merged into services）
│   │   ├── user_repo.py
│   │   └── item_repo.py
│   └── utils/                   # 工具函数
│       ├── constants.py
│       └── exceptions.py
├── tests/                       # 测试
│   ├── conftest.py
│   ├── test_users.py
│   └── test_items.py
├── alembic/                     # 数据库迁移
├── .env                         # 环境变量
├── requirements.txt
└── Dockerfile
```

## 各层职责与设计思想

| 层级             | 职责                                  | 关键点                                                                                                                                 |
| ---------------- | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **core**         | 全局配置、安全工具、应用生命周期事件  | 使用 `pydantic.BaseSettings` 加载环境变量；JWT 工具函数与认证相关逻辑集中于此；`lifespan` 管理启动/关闭                                |
| **models**       | SQLAlchemy（或 Tortoise）ORM 表定义   | 纯数据库表映射，不包含业务逻辑；通常继承自 `Base` 类（在 `db/base.py` 中定义）                                                         |
| **schemas**      | Pydantic 模型（请求/响应/数据库读取） | 输入验证、响应序列化、与 ORM 模型分离；遵循"每功能一组 schemas"原则                                                                    |
| **api**          | 路由定义与请求处理                    | 版本化管理（v1, v2）；使用 `APIRouter` 将不同功能的路由分拆到不同文件；在 `router.py` 中统一汇总；一般只在端点层做参数提取和调用服务层 |
| **dependencies** | FastAPI 依赖注入项                    | 公共依赖（`get_db`, `get_current_user`）放在 `api/deps.py`；特定于某版本或某模块的依赖放在对应的 `dependencies.py` 中                  |
| **services**     | 业务逻辑                              | 编排多个 repository 或外部 API 的调用；事务边界在此控制；避免在端点内放复杂逻辑，使代码可重用、可测试                                  |
| **repositories** | 数据访问抽象（可选）                  | 封装原始 SQL / ORM 查询；减少服务层与 ORM 的直接依赖；便于单元测试时 mock                                                              |

## 核心原则

1. **分离关注点**：不要让路由函数直接包含业务逻辑或数据库查询语句；路由只负责接收请求、调用服务、返回响应。
2. **模型与模式分离**：数据库模型（`models`）和 API 模式（`schemas`）分开，避免数据库内部结构泄漏到接口。
3. **依赖注入**：数据库会话、当前用户等通过 `Depends()` 注入，使代码松耦合且易于测试。
4. **统一配置**：所有配置项通过 `Settings` 对象集中管理，不再在代码中硬编码常量。
5. **路由版本化**：通过 `api/v1`, `api/v2` 等目录结构实现，便于维护和灰度升级。
6. **测试隔离**：使用独立的 `conftest.py` 管理测试夹具（例如覆写依赖获取测试数据库会话）。

## 面试回答模板

> "在大型 FastAPI 项目中，我会采用分层的模块化架构：
>
> - **app/core** 负责全局配置、安全工具和生命周期管理；
> - **app/models** 定义数据库 ORM 模型；
> - **app/schemas** 定义 Pydantic 请求和响应模型；
> - **app/api** 使用 APIRouter 按资源或功能拆分路由，通过依赖项（如 `get_db`、`get_current_user`）实现横切关注点复用；
> - **app/services** 封装核心业务逻辑，它在路由与数据访问之间起到协调作用；
> - 可选地进一步引入 **app/repositories** 层来抽象数据访问，便于单元测试。
>
> 这种结构让代码职责清晰、易于维护、支持团队协作，并能够独立对每一层进行测试。"

这样的设计既能体现你对大型项目架构的理解，又符合 FastAPI 社区推荐的实践。

## 关联

- [1.printed.md](./1.printed.md) — 面试题系列第 1 题
- [2.printed.md](./2.printed.md) — 面试题清单（第 12 题题目所在）
- [3.printed.md](./3.printed.md) — 面试题系列第 3 题
- [../../fastapi/middleware-organization.printed.md](../../fastapi/middleware-organization.printed.md) — 中间件分层（架构补充）
- [../../fastapi/url-structure.printed.md](../../fastapi/url-structure.printed.md) — URL/路由层结构细节
- [../../sqlalchemy/session-expire-on-commit.md](../../sqlalchemy/session-expire-on-commit.md) — db/session.py 会话管理坑
- [../../pydantic/1.md](../../pydantic/1.md) — schemas 层 Pydantic 基础

---

来源：~/fastapi_web/src/interview/12.py
落盘日期：2026-05-11
