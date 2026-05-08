# ECC 插件架构与使用指南

## 核心概念

ECC（Everything Claude Code）是 Claude Code 的插件，本质是 **"skill as prompt"**——每个 SKILL.md 是一段结构化 prompt 模板，告诉 Claude 在特定场景下该怎么思考和行动。不是传统可执行插件，只有被调用时才加载对应 prompt 到 context。

## 插件注册机制

### 命名空间规则

Claude Code 插件系统用 `插件名:技能名` 做 scope 隔离（类似 npm 的 `@scope/package`）：

```
Plugin: "ecc"  →  plugin.json 里 skills: ["./skills/"]
└── skills/frontend-design/SKILL.md
    → 注册为 ecc:frontend-design

Plugin: "frontend-design"  →  独立官方插件
└── skills/frontend-design/SKILL.md
    → 注册为 frontend-design:frontend-design
```

### 关键配置文件

```
~/.claude/plugins/cache/ecc/ecc/<version>/
├── .claude-plugin/plugin.json    # 主配置，声明 skills 目录
├── manifests/install-modules.json # 安装模块清单
├── skills/                       # 181 个 SKILL.md
└── agents/                       # 94 个 agent 定义
```

### 重复注册陷阱

`/ecc:configure-ecc` 安装向导会把选中的 skill 用 `cp -r` 复制到 `~/.claude/skills/`，导致同一个 skill 被注册多次（插件自动加载 + 本地副本）。本地副本可安全删除，只保留 `ecc:` 前缀版本即可。

## 三种使用方式

### 1. Skill 直接调用

输入 `/ecc:技能名` 触发专业工作流：

| Skill                  | 用途                           |
| ---------------------- | ------------------------------ |
| `/ecc:plan`            | 拆解需求，生成实现计划         |
| `/ecc:code-review`     | 代码审查（本地 diff 或 PR）    |
| `/ecc:tdd`             | 测试驱动开发流程               |
| `/ecc:frontend-design` | 高质量 UI 设计输出             |
| `/ecc:context-budget`  | 查看当前 context 窗口消耗      |
| `/ecc:docs`            | 通过 Context7 MCP 拉最新库文档 |

### 2. Agent 自动调度

ECC 注册的 agent 定义（如 `ecc:code-reviewer`、`ecc:build-error-resolver`）会被 Claude Code 在合适场景自动选用，无需手动调用。

### 3. 复合工作流 Pipeline

| Pipeline                                                | 做什么                         |
| ------------------------------------------------------- | ------------------------------ |
| `/ecc:prp-prd` → `/ecc:prp-plan` → `/ecc:prp-implement` | PRD → 规划 → 执行              |
| `/ecc:santa-loop`                                       | 双 reviewer 对抗审查           |
| `/ecc:gan-style-harness`                                | Generator + Evaluator 循环迭代 |

## coco 项目相关的 Skill

> 技术栈：Expo RN + Python FastAPI + PostgreSQL + pnpm monorepo

| 领域        | Skill                                                |
| ----------- | ---------------------------------------------------- |
| Python 后端 | `python-patterns`, `python-review`, `python-testing` |
| 前端        | `frontend-patterns`, `frontend-design`               |
| API         | `api-design`, `backend-patterns`                     |
| 数据库      | `postgres-patterns`, `database-migrations`           |
| 工程流程    | `plan`, `tdd`, `code-review`, `context-budget`       |
| 配置管理    | `configure-ecc`, `agent-sort`                        |

## macOS 注意事项

从网络下载的文件会被 Gatekeeper 标记 `com.apple.quarantine` 扩展属性（`ls -la` 显示 `@`），可能导致 `rm` 时 permission denied。用 `xattr -r -d com.apple.quarantine <path>` 清除后再操作。
