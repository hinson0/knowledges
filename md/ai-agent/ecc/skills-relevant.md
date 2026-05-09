# ECC 插件技能筛选（coco 项目）

> 技术栈：Expo RN + Python FastAPI + PostgreSQL + pnpm monorepo
> 筛选日期：2026-04-12
> ECC 版本：1.10.0（插件共 181 个技能，以 `ecc:` 前缀注册）

## 直接相关（~15 个）

| 技能                  | 为什么相关                  |
| --------------------- | --------------------------- |
| `python-patterns`     | FastAPI 后端                |
| `python-testing`      | pytest 测试                 |
| `frontend-patterns`   | React/RN 前端模式           |
| `frontend-design`     | UI 设计质量                 |
| `backend-patterns`    | API 架构                    |
| `api-design`          | REST API 设计               |
| `postgres-patterns`   | PostgreSQL 查询优化、索引   |
| `database-migrations` | Alembic 迁移最佳实践        |
| `e2e-testing`         | Playwright E2E              |
| `tdd-workflow`        | TDD 流程                    |
| `verification-loop`   | 质量验证                    |
| `coding-standards`    | 通用编码规范                |
| `security-review`     | 安全审查                    |
| `git-workflow`        | Git 工作流                  |
| `docker-patterns`     | 部署容器化（如果用 Docker） |

## 通用工作流（~10 个）

| 技能                            | 用途             |
| ------------------------------- | ---------------- |
| `strategic-compact`             | 上下文压缩       |
| `continuous-learning-v2`        | 学习模式提取     |
| `eval-harness`                  | 评估驱动开发     |
| `council`                       | 多视角决策       |
| `iterative-retrieval`           | 渐进式上下文检索 |
| `safety-guard`                  | 防止破坏性操作   |
| `blueprint`                     | 多会话任务规划   |
| `search-first`                  | 先搜索再编码     |
| `agent-introspection-debugging` | 代理调试         |
| `ai-regression-testing`         | AI 辅助回归测试  |

## ECC 配置/元工具（~8 个）

| 技能                      | 用途           |
| ------------------------- | -------------- |
| `configure-ecc`           | 配置 ECC       |
| `context-budget`          | 上下文预算审计 |
| `skill-stocktake`         | 技能审计       |
| `workspace-surface-audit` | 工作区审计     |
| `rules-distill`           | 规则提炼       |
| `prompt-optimizer`        | 提示优化       |
| `codebase-onboarding`     | 代码库新人引导 |
| `token-budget-advisor`    | Token 预算建议 |

## 统计

- 有用：~33 个（18%）
- 无用：~148 个（82%）
- 无用技能在系统提示中白占约 6,500 tokens（1M 窗口下 <1%）
- 插件目前不支持按项目选择性加载，全量注册
