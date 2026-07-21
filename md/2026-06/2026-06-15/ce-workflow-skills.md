# CE Workflow 涉及的 Skill 清单

## 目的

本文档梳理当前 CE workflow 在一个功能从需求进入、工作区准备、实现、联调、验证、评审到交付过程中涉及的 skill，以及各 skill 的职责边界。

CE workflow 的主入口是 `$ce-workflow`。其他 skill 按阶段提供补充能力，避免需求、契约、环境、测试、排障、提交和反馈分散在临时对话里。

## 总览

| 阶段       | 主要 skill                                                           | 作用                                               |
| ---------- | -------------------------------------------------------------------- | -------------------------------------------------- |
| 需求进入   | `$ce-workflow`                                                       | 创建 feature 工作区，分析仓库，沉淀需求和 API 契约 |
| 需求澄清   | `superpowers:brainstorming`                                          | 澄清目标、范围、约束和假设                         |
| 工作区隔离 | `superpowers:using-git-worktrees`                                    | 提供 worktree 隔离原则，实际由 harness 脚本执行    |
| 文档审核   | `superpowers:dispatching-parallel-agents`                            | 多视角审核 requirements 和 contracts               |
| 编码计划   | `superpowers:writing-plans`                                          | 将需求和契约转为实施计划                           |
| 编码实现   | `superpowers:test-driven-development`                                | 先写测试再实现关键行为                             |
| 本地环境   | `$ce-env`、`$ce-docker`、`$ce-start-server`                          | 准备 env、数据库、migration、本地前后端服务        |
| 排障修复   | `$ce-debug`、`superpowers:systematic-debugging`                      | 复现问题、定位根因、修复跨仓库契约漂移             |
| API 整理   | `$ce-api`                                                            | 将后端真实接口整理给前端或汇报使用                 |
| 功能审查   | `$ce-review`、`superpowers:requesting-code-review`                   | 从多维度审查功能实现、测试和风险                   |
| 完成验证   | `superpowers:verification-before-completion`                         | 完成前要求 fresh verification                      |
| 提交收尾   | `$ce-commit`、`$ce-pr`、`superpowers:finishing-a-development-branch` | 多仓库提交、推送、创建 MR/PR                       |
| 知识沉淀   | `$ce-km`、`$agentsmd-update`                                         | 沉淀 feature 材料或更新项目指令                    |
| 反馈收集   | `$ce-feedback`                                                       | 将人工反馈写入 GitLab issue                        |

## CE 本地 Skill

### `$ce-workflow`

职责：

- 作为 CE 多仓库 feature 的入口。
- 维护或使用 `repos.json`。
- clone source repo 到 `projects/<repo>`。
- 创建 feature worktree 到 `worktrees/<feature>/<repo>`。
- 分析相关仓库结构、route、API、model、页面、状态和测试入口。
- 生成和维护：
  - `assets/<feature>/requirements.md`
  - `assets/<feature>/contracts_api.md`

边界：

- 默认只做到工作区准备、仓库理解、文档填充和编码前汇报。
- 用户确认需求和契约前，不进入业务代码实现。
- 用户确认后，下一步应进入 `superpowers:writing-plans`。

### `$ce-env`

职责：

- 管理 CE 本地前后端联调的 `.env`。
- 确认 Vite 实际读取 `.env/.env`。
- 避免误用 `pnpm dev:test` 连接共享测试后端。
- 配置 `VITE_API_BASE_URL` 指向本地后端。
- 处理本地登录相关 cookie / Sanctum / session 配置。

典型配置：

```env
VITE_API_BASE_URL=http://localhost:8001
SESSION_SAME_SITE=lax
SESSION_SECURE_COOKIE=false
SANCTUM_STATEFUL_DOMAINS=localhost:8003
ALLOWED_ORIGINS=http://localhost:8003
```

适用场景：

- 本地登录成功后接口 401。
- 前端仍连 `site-test.cecook.cn/api`。
- Cookie 没有更新为新的 `laravel_session`。
- Vite proxy 或 API base URL 不符合本地联调要求。

### `$ce-docker`

职责：

- 启动 `cms-center` 本地依赖，例如 MySQL。
- 等待数据库 ready。
- 对齐 PHP 运行位置和 `.env` 数据库连接。
- 执行 migration 并验证表确实创建。

典型命令：

```bash
docker compose up -d mysql
php artisan migrate
```

关键规则：

- 写了 migration 不等于表已创建。
- 必须在可用数据库上执行 migration 并验证后，才能声明表已创建。

### `$ce-start-server`

职责：

- 一键启动 CE feature 的本地验证环境。
- 串联 `$ce-docker` 和 `$ce-env` 的关键动作。
- 启动后端 Laravel 服务和前端 Vite 服务。
- 输出本地测试地址、端口、日志路径和登录信息。

目标动作：

```bash
docker compose up -d mysql
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8001
pnpm dev
```

输出示例：

```text
Admin: http://localhost:8003/admin
Backend: http://localhost:8001
```

### `$ce-debug`

职责：

- 处理 CE 多仓库 bug 和契约漂移。
- 复现问题、定位根因、建立 producer / consumer 影响矩阵。
- 搜索旧契约和新契约。
- 修复后执行 fresh verification。
- 写入：
  - `assets/<feature>/debug-YYYY-MM-DD-<topic>.md`

适用场景：

- 菜单 `menu_code` 和前端 route name 不一致。
- 后端 endpoint 改了，前端仍调用旧路径。
- migration 已写但数据库未执行。
- 登录、cookie、权限、菜单、API 契约出现跨仓库不一致。

### `$ce-api`

职责：

- 基于 `cms-center` 源码整理真实 API 契约。
- 核实 route、controller、request、response、错误码。
- 输出给前端可直接使用的接口说明。

适用场景：

- 需要把后端接口交给前端。
- 需要确认某个接口真实请求和响应。
- 需要把接口写进 `contracts_api.md` 或汇报材料。

### `$ce-review`

职责：

- 对当前 feature、diff、PR/MR 或 review comments 做审查。
- 默认从以下维度检查：
  - comments
  - tests
  - errors
  - types
  - code
  - simplify

适用场景：

- 功能实现后需要交付前审查。
- 多仓库改动需要确认契约一致。
- 需要检查测试覆盖、错误处理、类型设计和可维护性。

### `$ce-commit`

职责：

- 按 CE 多仓库规则发现独立 Git 仓库。
- 分别检查每个子仓库状态。
- 分别暂存和提交。
- 默认不 push。

关键规则：

- 不能只看 harness 根目录的 `git status`。
- 业务代码改动必须进入对应子仓库处理。

### `$ce-pr`

职责：

- 为相关子仓库推送分支并创建 GitLab MR 或 GitHub PR。
- 汇总每个仓库的评审状态。

适用场景：

- 功能完成后准备发起评审。
- 多仓库需要分别创建 MR/PR。

### `$ce-km`

职责：

- 将材料沉淀到 harness 根目录。
- 所有长期沉淀都必须归入对应的 `assets/<feature>/`。
- 如果材料没有明确 feature 归属，先确认目标 feature，再写入 `assets/<feature>/<topic>.md`。

适用场景：

- 整理会议记录、调试过程、流程复盘、接口说明。
- 将一次对话中的经验转为长期文档。

### `$ce-feedback`

职责：

- 将人工反馈写入 GitLab issue。
- 支持通过环境变量配置 GitLab 地址、token 和项目 ID。

关键配置：

```env
GITLAB_TOKEN=<token>
GITLAB_BASE_URL=https://gitlab.cedemo.cn
CE_FEEDBACK_GITLAB_PROJECT=<project-id>
```

适用场景：

- 通过 `$ce-feedback` 收集 workflow 使用反馈。
- 记录谁提出了什么问题、需求或改进建议。

### `$agentsmd`

职责：

- 审计 AGENTS.md 和相关项目指令。
- 输出质量报告和修改建议。
- 不直接修改文件。

适用场景：

- 检查当前 harness 指令是否清晰、冲突或遗漏。

### `$agentsmd-update`

职责：

- 更新 AGENTS.md、`.codex/infra/*.md` 或项目内 skill 指令。
- 将会话经验沉淀为项目规则。

适用场景：

- 修正 skill 写错位置。
- 将 `.env`、Docker、登录 cookie 等经验写入项目长期规则。

## Superpowers Skill

### `superpowers:brainstorming`

在需求入口阶段使用。

作用：

- 澄清功能目标。
- 明确范围内 / 范围外。
- 识别约束、风险和待确认问题。
- 为 `requirements.md` 和 `contracts_api.md` 提供事实基础。

边界：

- 用户确认需求和契约后，默认不重复进入 brainstorming。
- 如果出现新增范围、关键歧义或方案调整，才回到该阶段。

### `superpowers:using-git-worktrees`

在工作区隔离阶段使用其原则。

作用：

- 保证 feature 开发不污染 source clone。
- 与 harness 的 `scripts/harness.mjs feature` 配合。

实际落地：

```bash
node scripts/harness.mjs feature <feature-slug> <repo-name>...
```

### `superpowers:dispatching-parallel-agents`

在文档审核阶段使用。

作用：

- 并行执行 3-5 个审核视角。
- 审核需求、API、架构、验证和跨仓库集成风险。

对应 reviewer：

- `requirements-reviewer`
- `api-contract-reviewer`
- `architecture-reviewer`
- `verification-reviewer`
- `integration-reviewer`

### `superpowers:writing-plans`

在用户确认需求和契约后使用。

作用：

- 将 `requirements.md` 和 `contracts_api.md` 转为实施计划。
- 输出到：
  - `assets/<feature>/plan-YYYY-MM-DD-<topic>.md`

边界：

- 没有计划，不直接进入实现。

### `superpowers:test-driven-development`

在编码实现阶段使用。

作用：

- 对关键行为先写测试。
- 确认测试失败后再实现。
- 实现后让测试通过。

适用对象：

- 后端 service、controller、request validation。
- 前端工具函数、组件交互、页面关键状态。

### `superpowers:systematic-debugging`

在 bug 或异常阶段使用。

作用：

- 先复现。
- 再收集证据。
- 再定位根因。
- 最后修复和验证。

与 `$ce-debug` 的关系：

- `$ce-debug` 是 CE 多仓库排障流程。
- `systematic-debugging` 是排障方法论。

### `superpowers:verification-before-completion`

在准备声明完成前使用。

作用：

- 要求 fresh verification。
- 不能只凭代码推断完成。
- 必须跑测试、build、API 或浏览器验证。

典型验证：

- 后端 PHPUnit。
- 前端 eslint / vitest / build。
- API curl 冒烟验证。
- 浏览器 e2e 或人工手测路径。

### `superpowers:requesting-code-review`

在交付前复核阶段使用。

作用：

- 检查多仓库契约是否一致。
- 检查测试覆盖和未验证项。
- 检查错误处理、边界场景和实现复杂度。

### `superpowers:finishing-a-development-branch`

在开发分支完成后使用。

作用：

- 判断下一步是提交、开 MR/PR、合并还是清理。
- 仅在实现完成且验证通过后使用。

## 子代理 Reviewer

`$ce-workflow` 在文档阶段需要使用 3-5 个审核角色。当前配置位于：

```text
.agents/skills/ce-workflow/subagents/
```

| Reviewer                | 审核重点                       | 输出                           |
| ----------------------- | ------------------------------ | ------------------------------ |
| `requirements-reviewer` | 需求完整性、验收标准、范围冲突 | 缺失需求、范围问题、待确认项   |
| `api-contract-reviewer` | endpoint、字段、错误码、兼容性 | 契约风险、字段缺口、调用方依赖 |
| `architecture-reviewer` | 仓库事实、模块边界、入口文件   | 文件引用、影响面、架构假设     |
| `verification-reviewer` | 单测、构建、API、e2e 覆盖      | 必跑验证、不可验证项、风险等级 |
| `integration-reviewer`  | 跨仓库数据流、发布顺序、回滚   | 依赖关系、顺序约束、集成风险   |

## 标准组合

### 新功能启动

```text
$ce-workflow
superpowers:brainstorming
superpowers:using-git-worktrees
superpowers:dispatching-parallel-agents
```

产物：

```text
assets/<feature>/requirements.md
assets/<feature>/contracts_api.md
```

### 用户确认后进入实现

```text
superpowers:writing-plans
superpowers:test-driven-development
```

产物：

```text
assets/<feature>/plan-YYYY-MM-DD-<topic>.md
```

### 本地联调

```text
$ce-docker
$ce-env
$ce-start-server
```

产物：

```text
本地后端服务
本地前端服务
已执行 migration
可访问 Admin URL
```

### Bug 排障

```text
$ce-debug
superpowers:systematic-debugging
```

产物：

```text
assets/<feature>/debug-YYYY-MM-DD-<topic>.md
```

### 完成验证

```text
superpowers:verification-before-completion
$ce-review
```

产物：

```text
assets/<feature>/verification.md
```

### 提交和评审

```text
$ce-commit
$ce-pr
superpowers:finishing-a-development-branch
```

产物：

```text
每个业务仓库独立 commit
每个业务仓库独立 MR/PR
```

## 汇报中的推荐表述

可以将 CE workflow 涉及 skill 概括为四类：

| 类型     | Skill                                               | 汇报描述                                     |
| -------- | --------------------------------------------------- | -------------------------------------------- |
| 流程编排 | `$ce-workflow`                                      | 负责 feature 工作区、需求文档和 API 契约     |
| 环境联调 | `$ce-env`、`$ce-docker`、`$ce-start-server`         | 负责本地 env、数据库、migration 和前后端服务 |
| 质量保障 | `$ce-debug`、`$ce-review`、Superpowers 验证类 skill | 负责排障、审查、测试和完成前验证             |
| 交付沉淀 | `$ce-commit`、`$ce-pr`、`$ce-km`、`$ce-feedback`    | 负责提交、评审、知识沉淀和反馈收集           |

## 结论

当前 CE workflow 不是单一命令，而是一组 skill 组成的流程体系：

```text
需求进入
→ $ce-workflow
→ brainstorming
→ requirements / contracts
→ writing-plans
→ TDD 实现
→ ce-env / ce-docker / ce-start-server
→ verification-before-completion
→ ce-review
→ ce-commit / ce-pr
→ ce-km / ce-feedback
```

这套组合的核心价值是将多仓库功能开发拆成可追踪、可验证、可复盘的阶段，降低漏建表、误连测试环境、菜单契约不一致、只改前端或只改后端等问题的概率。
