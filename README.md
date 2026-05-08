# 🧠 Knowledges

> 学习笔记与技术实践的知识仓库 — 由 [`learning`](https://github.com/hinson0/learning) 迁至

📚 **Knowledges** 是一个聚焦后端、前端、AI Native 与 AI Agent 方向的 **学习笔记仓库**，按"大方向 → 主题 → 笔记"两层结构组织。

---

## 📂 目录结构

按四大方向 + 工具杂项组织：

### `frontend/` — 前端 / 移动端

| 子目录       | 说明                              |
| ------------ | --------------------------------- |
| `vue3/`      | Vue 3 组合式 API、响应式与生态    |
| `android/`   | Android 开发实践                  |
| `pnpm/`      | pnpm 包管理与 workspace           |

### `backend/` — 后端 / 数据库 / 部署

| 子目录        | 说明                              |
| ------------- | --------------------------------- |
| `python/`     | Python 核心语法、asyncio 等       |
| `fastapi/`    | FastAPI Web 框架实践              |
| `pydantic/`   | 数据验证与配置管理                |
| `sqlalchemy/` | ORM 设计与使用                    |
| `sqlite3/`    | SQLite3 实践                      |
| `postgres/`   | PostgreSQL 原理与调优             |
| `monorepo/`   | 单体仓库管理                      |
| `docker/`     | 容器化、部署                      |
| `nginx/`      | 反向代理、静态站点                |

### `ai-native/` — 用 AI 工作的方法论与工具

| 路径                                | 说明                                      |
| ----------------------------------- | ----------------------------------------- |
| `claude-code/`                      | Claude Code 用法、技能、权限              |
| `ecc/`                              | ECC plugin 架构与工作流                   |
| `what-is-ai-native.printed.md`      | AI Native 概念                            |
| `ai-code-review-standards.printed.md` | AI 代码审核标准                         |
| `ROI.printed.md` / `SOTA.printed.md` | 通用术语                                 |

### `ai-agent/` — 构建 Agent 的技术与 LLM 基础

| 路径                              | 说明                                     |
| --------------------------------- | ---------------------------------------- |
| `system-prompt-sop.md` (+ pdf)    | Coding Agent System Prompt SOP 设计      |
| `agentic-workflow-design.md`      | Agentic Workflow 架构范式                |
| `context-engineering.printed.md`  | 上下文工程                               |
| `decoder-only-transformer.md`     | Decoder-only Transformer 架构            |
| `learning-roadmap.md` / `roadmap2.md` | AI Agent 学习路径                    |
| `stage-0-week1-checklist.md`      | 学习阶段 0 第 1 周 checklist             |
| `providers/`                      | 各 LLM provider 调用经验（DeepSeek 等）  |

### `tools/` — 编辑器与命令行工具

| 子目录    | 说明                       |
| --------- | -------------------------- |
| `just/`   | Justfile 命令运行器        |
| `vscode/` | VS Code 配置、snippets     |
| `image/`  | 图片处理（如 PNG 压缩）    |

---

## 🚀 使用方式

```bash
git clone https://github.com/hinson0/knowledges.git
cd knowledges

# 浏览某个主题
cd backend/postgres/
ls
```

新增笔记时遵循 `<大方向>/<主题>/<内容简要>.md` 的两层路径规则（详见 `~/.claude/CLAUDE.md`）。

---

## 🤝 贡献

欢迎 Issues 与 Pull Requests！若希望补充新方向或修正现有笔记，请直接发起 PR。

---

## 📄 许可

本项目仅用于个人学习与知识整理，仅供参考。
