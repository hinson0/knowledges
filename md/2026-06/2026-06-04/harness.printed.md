你要做的东西可以叫：

**AI Coding Agent Harness / Agent Infra / Agent Governance Layer**

它不是某个工具的配置，而是一套**跨 Claude Code、Codex、Cursor、Copilot Agent 的通用约束体系**。

核心思路：

> **规则只写一套，工具各自接入。**
> 不要让 `CLAUDE.md`、`AGENTS.md`、`.cursor/rules` 各自维护不同逻辑。

---

## 1. 先定义你的 Harness 分层

建议分成这 5 层：

```txt
company-global-rules     公司级通用规则
project-rules            项目级规则
agent-adapters           不同工具适配入口
workflow-guards          Git / Worktree / Branch / PR 约束
automation-checks        脚本、Hook、CI 强制校验
```

其中最重要的是：

```txt
真正的规则放在 .agent/rules/
各工具入口只负责引用这些规则
```

例如：

```txt
repo/
  AGENTS.md
  CLAUDE.md
  .cursor/
    rules/
      agent-harness.mdc

  .agent/
    README.md
    project.md
    commands.md
    rules/
      00-principles.md
      10-coding.md
      20-testing.md
      30-git-workflow.md
      40-security.md
      50-review.md
      60-agent-behavior.md
    scripts/
      agent-check.sh
      guard-branch.sh
      guard-worktree.sh
```

`AGENTS.md` 是 Codex 常见入口，OpenAI 官方文档也明确说明 Codex 会读取 `AGENTS.md` 作为项目指令；`AGENTS.md` 社区规范也把它定位成“给 coding agents 看的 README”。([OpenAI开发者][1])
Cursor 官方也支持 Project Rules、Team Rules、User Rules 以及 AGENTS.md。([Cursor][2])

---

## 2. 不同工具入口只做 Adapter

### AGENTS.md

```md
# AGENTS.md

This repository uses the shared AI Agent Harness.

Before making changes, read:

1. `.agent/project.md`
2. `.agent/commands.md`
3. `.agent/rules/00-principles.md`
4. `.agent/rules/10-coding.md`
5. `.agent/rules/20-testing.md`
6. `.agent/rules/30-git-workflow.md`
7. `.agent/rules/40-security.md`
8. `.agent/rules/50-review.md`
9. `.agent/rules/60-agent-behavior.md`

Do not treat this file as the source of truth.
The source of truth is `.agent/`.
```

### CLAUDE.md

```md
# CLAUDE.md

This repository uses the shared AI Agent Harness.

Read and follow:

- `.agent/project.md`
- `.agent/commands.md`
- `.agent/rules/00-principles.md`
- `.agent/rules/10-coding.md`
- `.agent/rules/20-testing.md`
- `.agent/rules/30-git-workflow.md`
- `.agent/rules/40-security.md`
- `.agent/rules/50-review.md`
- `.agent/rules/60-agent-behavior.md`

If instructions conflict:

1. User instruction wins.
2. Project-specific `.agent/project.md` wins over shared rules.
3. More specific rule wins over general rule.
4. Safety/security rules cannot be weakened.
```

### Cursor Rule

```md
---
description: Shared AI Agent Harness
alwaysApply: true
---

Follow the shared repository rules in:

- `.agent/project.md`
- `.agent/commands.md`
- `.agent/rules/00-principles.md`
- `.agent/rules/10-coding.md`
- `.agent/rules/20-testing.md`
- `.agent/rules/30-git-workflow.md`
- `.agent/rules/40-security.md`
- `.agent/rules/50-review.md`
- `.agent/rules/60-agent-behavior.md`
```

这样 Claude、Codex、Cursor 都不是各写一套规则，而是都指向 `.agent/`。

---

## 3. 规则应该怎么写

不要写成“道德口号”，要写成**可执行约束**。

差的规则：

```md
Write good code.
Be careful.
Don't break things.
```

好的规则：

```md
Before modifying code:

1. Identify the smallest relevant scope.
2. Read the existing implementation.
3. Check tests and commands in `.agent/commands.md`.
4. Explain the intended change briefly.
5. Modify only files required for the task.
```

---

## 4. 通用 coding 约束

`.agent/rules/10-coding.md` 可以这样写：

```md
# Coding Rules

## Scope Control

- Do not modify unrelated files.
- Do not perform broad refactors unless explicitly requested.
- Prefer minimal, focused changes.
- Preserve existing public APIs unless the task requires changing them.
- Do not rename files, functions, or modules without a clear reason.

## Existing Style

- Follow the existing style of the surrounding code.
- Prefer project conventions over generic best practices.
- Do not introduce a new framework, library, formatter, or architecture without approval.

## Dependency Rules

- Do not add dependencies unless necessary.
- If adding a dependency, explain:
  - why it is needed
  - why existing dependencies are insufficient
  - impact on build/runtime/security

## Error Handling

- Do not swallow errors silently.
- Preserve meaningful logs.
- Avoid over-broad catch blocks.
- For backend code, return structured errors where existing patterns exist.

## Compatibility

- Avoid breaking existing interfaces.
- If breaking change is unavoidable, document migration steps.
```

---

## 5. 测试约束

`.agent/rules/20-testing.md`：

```md
# Testing Rules

## Before Changing

- Locate existing tests related to the changed code.
- If no tests exist, identify the closest verification command.

## After Changing

Run the smallest relevant verification first.

Examples:

- Single unit test
- Package-level test
- Lint for touched package
- Typecheck for touched package

## Required Output

Every final response must include:

- Changed files
- Summary of changes
- Verification commands run
- Whether verification passed or failed

## Do Not Fake Verification

- Never claim tests passed if they were not run.
- If tests cannot run, explain why.
- If tests fail, report the failure honestly.
```

这个非常重要。Agent 最大的问题之一就是“看起来像做完了”，但其实没验证。

---

## 6. Git / Worktree 约束

这是你提到的重点。

`.agent/rules/30-git-workflow.md`：

````md
# Git Workflow Rules

## Branch Safety

- Never commit directly to `main`, `master`, `develop`, or release branches.
- Never create work directly on protected branches.
- Always work on a feature branch.

Protected branches:

- main
- master
- develop
- staging
- production
- release/\*

## Branch Naming

Use:

- `agent/<ticket-id>-<short-description>`
- `fix/<ticket-id>-<short-description>`
- `feature/<ticket-id>-<short-description>`
- `chore/<ticket-id>-<short-description>`

Examples:

- `agent/JIRA-123-fix-login-timeout`
- `fix/BUG-88-handle-null-user`

## Worktree Rules

When using AI coding agents:

- Prefer one worktree per task.
- Do not run multiple agents in the same worktree.
- Do not let different agents edit the same branch concurrently.
- Each worktree must map to exactly one task or ticket.
- Delete stale worktrees after merge or abandonment.

## Worktree Layout

Recommended local layout:

```txt
~/work/
  project/
    main/                 canonical clean checkout
    worktrees/
      JIRA-123-login/
      JIRA-124-billing/
      BUG-88-null-user/
```
````

## Required Preflight

Before editing, check:

```bash
git status
git branch --show-current
git rev-parse --show-toplevel
git worktree list
```

If current branch is protected, stop and create a new branch/worktree.

## Commit Rules

- Do not commit unless explicitly asked.
- If asked to commit, use conventional commits.
- Do not include unrelated changes.
- Do not amend or rebase shared branches unless explicitly requested.

````

Git worktree 本身就是 Git 官方支持的能力，用来让同一个仓库有多个工作目录，非常适合多任务/多 Agent 并行开发。:contentReference[oaicite:2]{index=2}

---

## 7. 用脚本强制约束，不要只靠提示词

提示词只能“提醒”，不能“强制”。

所以你需要 `guard` 脚本。

### `.agent/scripts/guard-branch.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

branch="$(git branch --show-current)"

protected_regex='^(main|master|develop|staging|production)$|^release/'

if [[ "$branch" =~ $protected_regex ]]; then
  echo "ERROR: You are on protected branch: $branch"
  echo "Create a feature branch or worktree before making changes."
  exit 1
fi

echo "OK: branch is safe: $branch"
````

### `.agent/scripts/agent-check.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "== Agent Preflight Check =="

git status --short
echo

.agent/scripts/guard-branch.sh

echo
echo "Current branch:"
git branch --show-current

echo
echo "Worktrees:"
git worktree list

echo
echo "OK: agent preflight passed."
```

然后在规则里要求：

````md
Before editing code, run:

```bash
.agent/scripts/agent-check.sh
```
````

````

---

## 8. 用 Git Hooks 进一步约束

可以加：

```txt
.githooks/
  pre-commit
  pre-push
````

### `.githooks/pre-commit`

```bash
#!/usr/bin/env bash
set -euo pipefail

.agent/scripts/guard-branch.sh
```

启用：

```bash
git config core.hooksPath .githooks
```

这样即使 Agent 忘了规则，提交时也会被拦。

---

## 9. CI 也要兜底

GitHub Actions / GitLab CI 里做保护：

```yaml
name: Agent Guard

on:
  pull_request:

jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check forbidden files
        run: |
          echo "Run project checks here"
      - name: Check branch
        run: |
          echo "PR branch: ${{ github.head_ref }}"
```

CI 应该检查：

```txt
是否改了禁止改的文件
是否缺测试
是否格式化失败
是否绕过 lockfile
是否包含密钥
是否从 protected branch 直接提交
```

---

## 10. Agent 行为约束

`.agent/rules/60-agent-behavior.md`：

```md
# Agent Behavior Rules

## Planning

For non-trivial tasks, first provide:

- understanding of the task
- files likely to inspect
- intended approach
- risks or assumptions

## Editing

- Read before writing.
- Prefer patches over rewriting whole files.
- Do not replace large files wholesale.
- Do not remove comments unless they are wrong or obsolete.
- Do not change formatting-only unless requested.

## Communication

Before final response, include:

- what changed
- why it changed
- files touched
- verification performed
- remaining risks

## When Unsure

- Prefer asking one focused question.
- If the task is still actionable, make a conservative best-effort change.
- Do not invent project behavior.
```

---

## 11. 安全约束

`.agent/rules/40-security.md`：

````md
# Security Rules

## Secrets

- Never print secrets.
- Never commit `.env`, private keys, tokens, credentials, or local config.
- If a secret appears in output, stop and warn the user.

## Dangerous Commands

Do not run destructive commands unless explicitly requested.

Forbidden by default:

```bash
rm -rf
git reset --hard
git clean -fd
docker system prune
DROP DATABASE
kubectl delete
terraform destroy
```
````

## Data Safety

- Do not modify production data.
- Do not run migrations against production.
- Do not disable auth, validation, rate limits, or permission checks to make tests pass.

````

---

## 12. Review / PR 输出规范

`.agent/rules/50-review.md`：

```md
# Review Rules

## Final Response Format

Use this format:

```md
## Summary

- ...

## Changed Files

- `path/to/file`: reason

## Verification

- `pnpm test`: passed
- `pnpm lint`: passed

## Risks

- ...
````

## Pull Request Description

When asked to create a PR description, include:

- Problem
- Solution
- Test plan
- Screenshots/logs if relevant
- Rollback notes if risky

````

---

## 13. 项目级文件怎么写

`.agent/project.md`：

```md
# Project Context

## Project Type

- Frontend: Next.js
- Backend: NestJS
- Database: PostgreSQL
- Package manager: pnpm

## Architecture

- `apps/web`: frontend
- `apps/api`: backend
- `packages/ui`: shared UI
- `packages/config`: shared config

## Important Constraints

- Do not bypass auth middleware.
- Do not access database directly from frontend.
- Use existing service layer.
- Use existing error handling pattern.
````

`.agent/commands.md`：

````md
# Commands

## Install

```bash
pnpm install
```
````

## Development

```bash
pnpm dev
```

## Test

```bash
pnpm test
```

## Lint

```bash
pnpm lint
```

## Typecheck

```bash
pnpm typecheck
```

## Database

```bash
pnpm db:migrate
pnpm db:generate
```

````

每个项目只需要改这两个文件。通用规则不用变。

---

## 14. 多项目复用方式

你可以建一个独立仓库：

```txt
ai-agent-harness/
  templates/
    default/
      AGENTS.md
      CLAUDE.md
      .cursor/rules/agent-harness.mdc
      .agent/
        rules/
        scripts/
  bin/
    init-agent-harness
    update-agent-harness
````

项目 A/B/C 接入：

```bash
npx your-agent-harness init
```

或者用 Git submodule：

```txt
repo/
  .agent/shared/    -> submodule 指向统一 harness 仓库
  .agent/project.md
  .agent/commands.md
```

但我更建议早期直接复制模板，成熟后再做同步工具。

---

## 15. 规则优先级一定要写清楚

否则以后必冲突。

建议统一写：

```md
# Instruction Priority

If instructions conflict, follow this order:

1. Direct user instruction in current task
2. Security and safety rules
3. Project-specific rules in `.agent/project.md`
4. Shared rules in `.agent/rules/`
5. Tool-specific adapter files such as `CLAUDE.md`, `AGENTS.md`, `.cursor/rules`
6. General model knowledge

Tool-specific files must not redefine core behavior.
They should only point to the shared harness.
```

重点是这句：

> **CLAUDE.md / AGENTS.md / Cursor Rules 不拥有业务规则，只是入口。**

---

## 16. 推荐你的最终目录

```txt
project/
  AGENTS.md
  CLAUDE.md

  .cursor/
    rules/
      agent-harness.mdc

  .agent/
    project.md
    commands.md

    rules/
      00-principles.md
      10-coding.md
      20-testing.md
      30-git-workflow.md
      40-security.md
      50-review.md
      60-agent-behavior.md

    scripts/
      agent-check.sh
      guard-branch.sh
      guard-worktree.sh

  .githooks/
    pre-commit
    pre-push
```

---

## 17. 最小可落地版本

你第一版不用搞太复杂。

先做这 6 个文件就够了：

```txt
AGENTS.md
CLAUDE.md
.agent/project.md
.agent/commands.md
.agent/rules/coding.md
.agent/rules/git-workflow.md
```

然后慢慢加：

```txt
testing.md
security.md
review.md
agent-behavior.md
scripts/
hooks/
ci/
```

---

## 18. 一句话原则

你要做的不是“给 Claude 写规则”或者“给 Codex 写规则”。

你要做的是：

**给团队定义一套 AI 参与开发的工程制度，然后让 Claude Code、Codex、Cursor 都接入这套制度。**

最重要的设计原则：

```txt
单一事实源：.agent/
工具入口：AGENTS.md / CLAUDE.md / Cursor Rules
强制约束：scripts + hooks + CI
项目差异：project.md / commands.md
```

[1]: https://developers.openai.com/codex/guides/agents-md?utm_source=chatgpt.com "Custom instructions with AGENTS.md – Codex"
[2]: https://cursor.com/docs/rules?utm_source=chatgpt.com "Rules | Cursor Docs"
