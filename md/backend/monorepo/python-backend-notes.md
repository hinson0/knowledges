# Monorepo + Python 后端重构知识点

> 本次重构（Supabase Edge Functions → FastAPI）过程中涉及的工程知识。

---

## 1. Monorepo 根目录配置文件原则

根目录只放**对整个 monorepo 生效**的配置，其余跟着代码走。

| 文件                  | 放根目录？         | 原则                                        |
| --------------------- | ------------------ | ------------------------------------------- |
| `pnpm-workspace.yaml` | ✅                 | monorepo 核心，必须在根目录                 |
| `package.json`        | ✅                 | 工作区入口，只放跨包脚本和 packageManager   |
| `.npmrc`              | ✅                 | pnpm 全局行为配置（如 native build 白名单） |
| `.gitignore`          | ✅                 | 覆盖整个仓库                                |
| `.prettierrc`         | ❌                 | 跟着用它的子包走，通过软链接共享            |
| `tsconfig.json`       | ❌                 | 各包差异大时各自独立，不强求统一基础        |
| `eslint.config.js`    | ❌                 | 跟着代码走，放在 `apps/mobile/`             |
| `turbo.json`          | ❌（如不用 Turbo） | 没有 `turbo run` 脚本时是死文件             |

---

## 2. `.prettierrc` 在 monorepo 中的共享

Prettier 从被格式化的文件目录**向上**查找配置，找到第一个就用。

多包共享同一份 `.prettierrc` 的方式：在需要的包里建软链接。

```bash
# 从 packages/shared/ 指向 apps/mobile/.prettierrc
ln -s ../../apps/mobile/.prettierrc packages/shared/.prettierrc
```

**软链接路径规则**：路径是相对于**链接文件所在目录**，不是相对于执行命令的目录。

---

## 3. pnpm 全局 Store 机制

pnpm 使用**内容寻址存储**（content-addressable store）：

- 全局 store 位于 `~/.local/share/pnpm/store/`
- 每个版本的包只在 store 里存一份物理文件
- 各项目的 `node_modules/` 里是指向 store 的**硬链接**，不是拷贝

**实际影响**：100 个项目安装同一版本的 `prettier`，磁盘占用等于装 1 次。所以"谁用谁在自己的 package.json 里声明"是正确做法，不会浪费磁盘。

---

## 4. FastAPI 项目分层

```
routers/    HTTP 层 — 接收请求、调 service、返回响应，不含业务逻辑
services/   业务层 — 实际的 AI 调用（GLM、腾讯云），与 HTTP 解耦
schemas/    Pydantic schema — 定义 HTTP 请求/响应的数据格式，做参数校验
models/     SQLAlchemy ORM — 定义数据库表对应的 Python 类，做 DB 读写
config.py   环境变量集中管理，用 pydantic-settings 自动读取并校验
```

### `schemas/` vs `models/` 的区别

|      | `schemas/`                     | `models/`                |
| ---- | ------------------------------ | ------------------------ |
| 用途 | HTTP 边界（请求/响应格式）     | 数据库边界（表结构映射） |
| 库   | Pydantic                       | SQLAlchemy               |
| 场景 | FastAPI 自动校验参数、生成文档 | ORM 查询数据库           |

一个请求完整路径：`HTTP 请求 → schemas 校验 → services 业务逻辑 → models 查数据库 → schemas 序列化 → HTTP 响应`

---

## 5. Docker Compose 热重载原理

```yaml
volumes:
  - ./apps/backend:/app # 把本地目录挂载到容器内
```

挂载后，本地修改文件 → 容器内立即看到变化。配合 `uvicorn --reload`，保存代码即生效，不需要重新 `docker build`。

**为什么不在容器里起数据库**：本项目数据库在 Supabase 云端，移动端也连它。本地另起 PostgreSQL 容器反而要维护数据同步，麻烦大于收益。

---

## 6. uv — Python 包管理器

uv 是 Rust 写的，相当于 Python 界的 pnpm：做的事和 pip 一样，但快很多，内置虚拟环境管理。

```bash
uv init            # 初始化项目，生成 pyproject.toml（类比 package.json）
uv add fastapi     # 安装依赖（类比 pnpm add）
uv run main.py     # 在虚拟环境里运行
```

依赖声明在 `pyproject.toml`，Docker 构建时可用 `uv export > requirements.txt` 生成兼容格式。

---

## 7. Supabase `apikey` Header

Supabase Edge Functions 网关要求每个请求带 `apikey` header，值为 `SUPABASE_ANON_KEY`，用于网关层鉴权。

这是 Supabase 专有机制。迁移到 FastAPI 后，FastAPI 不认识这个 header，可以直接删掉。认证改为标准的 `Authorization: Bearer <JWT>` 由 FastAPI 自行处理。

---

## 8. pnpm 常用命令对照

| 操作           | pnpm                             | npm                            |
| -------------- | -------------------------------- | ------------------------------ |
| 安装依赖       | `pnpm install`                   | `npm install`                  |
| 运行脚本       | `pnpm dev`                       | `npm run dev`                  |
| 向子包添加依赖 | `pnpm add <pkg> --filter mobile` | `npm add <pkg> -w apps/mobile` |
| 运行子包脚本   | `pnpm --filter mobile test`      | `npm run test -w apps/mobile`  |
