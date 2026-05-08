# ECC 常见使用方法

## 核心概念

ECC 的使用分三层：**Skill 手动调用**、**Agent 自动调度**、**复合 Pipeline**。

## 1. Skill 直接调用

输入 `/ecc:技能名` 触发专业工作流：

| Skill                  | 用途                           |
| ---------------------- | ------------------------------ |
| `/ecc:plan`            | 拆解需求，生成实现计划         |
| `/ecc:code-review`     | 代码审查（本地 diff 或 PR）    |
| `/ecc:tdd`             | 测试驱动开发流程               |
| `/ecc:frontend-design` | 高质量 UI 设计输出             |
| `/ecc:context-budget`  | 查看当前 context 窗口消耗      |
| `/ecc:docs`            | 通过 Context7 MCP 拉最新库文档 |

## 2. Agent 自动调度

ECC 注册了 94 个 agent 定义（如 `ecc:code-reviewer`、`ecc:build-error-resolver`），Claude Code 在合适场景会自动选用，无需手动调用。

## 3. PRP — Pull Request Pipeline

PRP 是一套从需求到上线的完整流水线，每个环节可单独用，也可按顺序走完整 pipeline：

| 阶段    | Skill                | 做什么                               |
| ------- | -------------------- | ------------------------------------ |
| 1. 需求 | `/ecc:prp-prd`       | 交互式生成 PRD（问题优先，假设驱动） |
| 2. 规划 | `/ecc:prp-plan`      | 分析代码库，生成实现计划             |
| 3. 执行 | `/ecc:prp-implement` | 按计划逐步实现，带验证循环           |
| 4. 提交 | `/ecc:prp-commit`    | 用自然语言描述要提交什么             |
| 5. PR   | `/ecc:prp-pr`        | 自动发现模板、分析 diff、创建 PR     |

## 4. 其他常用复合工作流

| Skill                    | 做什么                                 |
| ------------------------ | -------------------------------------- |
| `/ecc:santa-loop`        | 双 reviewer 对抗审查，两个都通过才算过 |
| `/ecc:gan-style-harness` | Generator + Evaluator 循环迭代         |
| `/ecc:agent-sort`        | 根据 repo 技术栈推荐该装哪些 skill     |
| `/ecc:configure-ecc`     | 交互式安装向导                         |

## 5. coco 项目常用组合

> 技术栈：Expo RN + Python FastAPI + PostgreSQL + pnpm monorepo

新功能开发

/ecc:plan → /ecc:tdd → /ecc:code-review

查库文档

/ecc:docs

数据库变更

/ecc:database-migrations /ecc:postgres-patterns

Python 后端审查

/ecc:python-review
