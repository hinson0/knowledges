# AGENTS.md

这个仓库是一个多仓库 AI coding harness。它是控制面，不是 monorepo。

## 语言偏好

- 文档、说明、规则、需求、契约和面向人的叙述内容默认使用中文。
- 英文技术词汇、文件名、目录名、命令名、代码标识、API 字段名和行业通用术语应保留英文。
- 不要为了中文化而强行翻译会降低准确性的技术词汇，例如 `worktree`、`source clone`、`harness`、`feature branch`、`AGENTS.md`、`repos.json`、`scripts/harness.mjs`。

## 目录结构与职责边界

这个仓库是 CE 多仓库 AI coding harness 的控制面，不是业务 monorepo。根目录只保存 registry、脚本、项目指令、feature 资产、汇报材料和临时运行产物；业务代码在 `projects/` 和 `worktrees/` 下以独立 Git 仓库存在。

```text
ce-harness-cms/
├── AGENTS.md                         # 项目指令入口；harness 仓库追踪
├── README.md                         # 面向人的 harness 说明；harness 仓库追踪
├── repos.json                        # 子仓库 registry；harness 仓库追踪
├── scripts/                          # harness 脚本；harness 仓库追踪
│   ├── harness.mjs                   # Node 入口：repos/bootstrap/feature/status/search/clean-worktree
│   ├── harness.ps1                   # Windows wrapper
│   └── harness.sh                    # Linux/macOS wrapper
├── .agents/                          # 项目内 agent/skill 指令；harness 仓库追踪
│   └── skills/
│       └── <skill>/
│           ├── SKILL.md              # skill 唯一入口
│           ├── scripts/              # skill 脚本
│           ├── templates/            # skill 模板
│           ├── references/           # skill 参考资料
│           └── subagents/            # skill 子代理配置
├── .codex/                           # Codex hooks/rules 等配置；提交前确认是否应共享
│   ├── config.toml
│   ├── hooks/
│   └── rules/
├── .githooks/                        # 仓库 Git hooks；harness 仓库追踪
│   └── pre-commit
├── projects/                         # 长期 source clone；目录被 harness 忽略
│   └── <repo>/                       # 子仓库自己的 Git
├── worktrees/                        # feature worktree；目录被 harness 忽略
│   └── <feature>/
│       └── <repo>/                   # 子仓库自己的 Git，业务代码在这里改
├── assets/                           # feature 长期工程资产；harness 仓库追踪
│   ├── README.md                     # assets 目录说明
│   └── <feature>/
│       ├── requirements.md           # feature 需求事实来源
│       ├── contracts_api.md          # feature API/契约事实来源
│       ├── spec-YYYY-MM-DD-<topic>.md
│       ├── plan-YYYY-MM-DD-<topic>.md
│       ├── debug-YYYY-MM-DD-<topic>.md
│       ├── verification.md
│       └── <topic>.md                # 该 feature 下的其它资产文档
├── weeks/                            # 周报、report、截图、GIF、演示材料
│   └── <YYYY-MM-DD>/
├── .tmp/                             # 临时运行产物；通常不提交
│   └── <tool>/
│       └── <feature>/
├── output/                           # 验证附件；按需提交
│   └── playwright/
└── tests/                            # harness 控制面自测，不是业务仓库测试
```

### Registry 和 worktree 规则

- `repos.json` 可以是空对象 `{}`，表示当前没有绑定业务仓库。
- `$ce-workflow` 只有在用户提供 repo source、仓库 URL 或明确要求补齐仓库时才更新 `repos.json`；如果用户没有指明 repo source，就以根目录现有 `repos.json` 配置为准。
- feature 完成或清理后不需要把 `repos.json` 恢复为空；它保留已登记的 source repo，供后续 feature 复用。
- `projects/<repo>` 是长期 source clone，不是 feature 开发目录；不要在这里直接做 feature 业务改动。
- `worktrees/<feature>/<repo>` 是 feature 开发目录；修改业务代码时必须进入这个子仓库，并以该子仓库自己的 Git 状态为准。
- `projects/*` 和 `worktrees/*` 会被 harness `.gitignore` 忽略，但它们仍然是有效的业务代码根目录，不要把它们当成不可见目录。

### Assets 资产规则

- `assets/<feature>/` 存放某个 feature 的长期资产，包括 `requirements.md`、`contracts_api.md`、`spec-YYYY-MM-DD-<topic>.md`、`plan-YYYY-MM-DD-<topic>.md`、`debug-YYYY-MM-DD-<topic>.md` 和 `verification.md`。
- 所有长期知识文档、流程复盘和主题沉淀都必须归入某个明确的 `assets/<feature>/` 目录；不要创建第二套 assets 一级目录结构。
- `worktrees/<feature>/` 只存放临时业务 worktree；长期文档、需求、契约、验证和调试沉淀不要写在这里。
- Superpowers 的 spec / plan 默认写入当前 feature 资产目录，文件名分别使用 `spec-YYYY-MM-DD-<topic>.md` 和 `plan-YYYY-MM-DD-<topic>.md`。
- debug 结束时必须把排障知识沉淀到 `assets/<feature>/debug-YYYY-MM-DD-<topic>.md`，记录现象、根因、修复、验证和跨仓库契约影响。
- `verification.md` 记录完成前 fresh verification，包括后端测试、前端测试、API 冒烟、浏览器验证、未验证项和已知问题。

### 文档和汇报材料规则

- 长期知识文档、流程复盘和主题沉淀写入对应的 `assets/<feature>/`。
- `weeks/<YYYY-MM-DD>/` 用于对外或阶段性 report、周报、演示材料、截图和 GIF；这类材料不要混入 `assets/<feature>/`。
- `assets/<feature>/` 放某个 feature 的工程资产；通用 workflow 汇报、skill 清单和流程复盘也必须先确认归属 feature，再写入对应 `assets/<feature>/`；周报和演示图片应放到 `weeks/<YYYY-MM-DD>/`。

### 项目内 skill 位置

- 仓库内 skill 必须位于 `.agents/skills/<skill>/SKILL.md`。
- 不要把项目 skill 写到根目录 `skills/`。
- 如果 `.agents` 在当前运行环境为只读挂载，必须明确报告阻塞并等待写权限恢复。
- skill 的脚本、模板、参考资料和子代理配置应放在该 skill 目录下的 `scripts/`、`templates/`、`references/`、`subagents/` 中。

## 仓库内技能

| 技能               | 触发场景                                                                                                                                                                                                          | 职责                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `$ce-workflow`     | 用户提到 `$ce-workflow`，或要求根据功能目标和仓库 URL 自动准备多仓库 feature 工作区。                                                                                                                             | 按用户提供的 repo source 补齐 `repos.json`，或在未提供 repo source 时使用根目录现有配置；clone 缺失的 source clone、创建 feature worktree、深入理解相关仓库，并自动填充 `assets/<feature>/requirements.md` 和 `assets/<feature>/contracts_api.md`。                                                                                                                                |
| `$ce-review`       | 用户提到 `$ce-review`，或要求审查当前 CE feature、Git diff、PR、review comments、测试覆盖、错误处理、类型设计、注释或代码简化。                                                                                   | 按 comments/tests/errors/types/code/simplify 六个维度审查，并按 CE harness 的多仓库 worktree 规则聚合 findings 和行动建议。                                                                                                                                                                                                                                                        |
| `$ce-debug`        | 用户提到 `$ce-debug`，或报告 CE 多仓库 bug、契约不一致、修复一个仓库可能遗漏其它消费者。                                                                                                                          | 复现 bug、定位根因、建立 producer/consumer 影响矩阵、跨仓库搜索 old/new contract、同步相关仓库、验证旧契约残留和必要 e2e。                                                                                                                                                                                                                                                         |
| `$ce-api`          | 用户要求把 `cms-center` 已实现接口整理给前端调用。                                                                                                                                                                | 基于后端源码核实真实 route/controller/request/response，并输出前端可复制的简洁 HTTP API 契约；新 feature 的 proposed API 仍由 `$ce-workflow` 写入 `assets/<feature>/contracts_api.md`。                                                                                                                                                                                            |
| `$ce-env`          | 需要本地联调 CE 前后端、配置 `ce-site-backend/.env/.env`、确认 Vite 实际 env、对齐 `VITE_API_BASE_URL`、排查登录后接口 401、`laravel_session`、Sanctum 或 SameSite/Secure cookie 问题，或避免误连 test/prod API。 | 在 `ce-site-backend/.env/.env` 准备本地环境；先核实 `cms-center` route prefix，再把 `VITE_API_BASE_URL` 指向本地后端，例如本地 route 是 `/admin/...` 且 Vite proxy 只剥离 `/vite-proxy` 时使用 `http://localhost:8001`；本地 HTTP 下对齐 `SESSION_SAME_SITE=lax`、`SESSION_SECURE_COOKIE=false`、`SANCTUM_STATEFUL_DOMAINS` 和 `ALLOWED_ORIGINS`；确认 Vite 实际加载的是本地 API。 |
| `$ce-docker`       | `cms-center` 本地开发、迁移、测试或 `php artisan serve` 需要 MySQL/Redis 等 compose 依赖，或遇到数据库连接失败、connection refused、表不存在、migration 未执行等问题。                                            | 在 `cms-center` worktree 主动检查并运行 `docker compose up -d mysql` 或 `mysql-test` 等依赖；等待服务 ready；按 PHP 运行位置对齐 `.env` 数据库连接；执行 migration 并验证后，才能声明表已创建。                                                                                                                                                                                    |
| `$ce-start-server` | 用户要求启动 CE feature 本地测试服务、本地联调环境、后端 `cms-center`、前端 `ce-site-backend`、MySQL、migration、Laravel 或 Vite，并希望无需逐个手动开服务。                                                      | 使用 `.agents/skills/ce-start-server/scripts/start_ce_servers.py` 在 feature worktree 中一键准备前端 env、启动 MySQL、执行 migration、后台启动 Laravel 和 Vite，输出 URL、pid 与日志路径；启动失败时再按 `$ce-docker` / `$ce-env` 分段排障。                                                                                                                                       |
| `$ce-commit`       | 用户要求提交 CE 工作区改动。                                                                                                                                                                                      | 按 CE 多仓库规则发现独立 Git 仓库，逐仓检查、暂存和提交，不自动 push。                                                                                                                                                                                                                                                                                                             |
| `$ce-pr`           | 用户要求创建 PR/MR、推送分支或通过 PR/MR 发起评审。                                                                                                                                                               | 逐仓检查干净状态、推送 feature 分支，并创建 GitHub PR 或 GitLab MR。                                                                                                                                                                                                                                                                                                               |
| `$ce-km`           | 用户要求把材料沉淀到当前 feature 资产。                                                                                                                                                                         | 整理用户提供的文本、接口说明、会议记录或排障过程；所有长期沉淀都必须写入对应的 `assets/<feature>/`。                                                                                                                                                                                                                                                                               |
| `$ce-feedback`     | 用户手动触发 `$ce-feedback` 或 `ce:feedback`，并提供需求、反馈、建议、问题记录或改进点，需要发布到 GitLab 以便网页追踪。                                                                                          | 整理反馈标题和正文，确认 GitLab project id/path，使用 `.agents/skills/ce-feedback/scripts/create_gitlab_issue.py` 创建 GitLab issue，并把 issue 链接返回给用户；不得在缺少明确触发或目标项目时自动发布。                                                                                                                                                                           |
| `$agentsmd`        | 用户要求审计 Codex 项目指令。                                                                                                                                                                                     | 审计 `AGENTS.md` 和相关 Codex 指令文件，只输出质量报告和修改建议。                                                                                                                                                                                                                                                                                                                 |
| `$agentsmd-update` | 用户要求更新、修复或沉淀 Codex 项目指令。                                                                                                                                                                         | 实际更新 `AGENTS.md`、`.codex/infra/*.md` 或项目内 Codex skill 指令。                                                                                                                                                                                                                                                                                                              |

## Agent 规则

- 不要把被 ignore 的子仓库目录当成不可见目录。
- 修改业务代码时，必须进入对应子仓库目录，并以该子仓库自己的 Git 状态为准。
- 不要只依赖 harness 根目录的 `git status` 判断业务代码是否有改动。
- 不要只依赖 harness 根目录的默认搜索，因为搜索工具可能跳过被 ignore 的目录。
- 使用 `scripts/harness.mjs status <feature>` 检查 feature 工作区。
- 使用 `scripts/harness.mjs search <feature> <pattern>` 做跨子仓库搜索。
- `$ce-workflow` 进入实现或验证阶段、需要本地前后端联调时，优先使用 `$ce-start-server` 一键启动 MySQL、migration、Laravel 和 Vite；如果启动失败，再按 `$ce-docker` / `$ce-env` 分段排障。不要用 `pnpm dev:test` 误连共享测试后端。
- 写了 migration 不等于表已创建；必须在可用数据库上运行对应 `php artisan migrate` 并验证后，才能说表已经创建。
- 涉及多个子仓库时，尽量使用同一个 feature 分支名：`feature/<feature-name>`。
