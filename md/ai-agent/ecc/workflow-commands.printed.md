# ECC 工作流命令速查

ECC（Everything Claude Code）通过斜杠命令驱动开发工作流，覆盖从需求到 PR 的完整生命周期。

## 核心命令

| 命令           | 用途                                                   | 典型场景           |
| -------------- | ------------------------------------------------------ | ------------------ |
| `/plan`        | 快速对齐需求，生成实现计划（等确认后才动手）           | 普通 feature、重构 |
| `/tdd`         | 测试驱动开发：RED → GREEN → REFACTOR，强制 80%+ 覆盖率 | 所有编码任务       |
| `/code-review` | 代码审查（本地 diff 或 GitHub PR 模式）                | 写完代码后         |
| `/build-fix`   | 增量修复构建/类型错误，每次修一个                      | 构建失败           |
| `/feature-dev` | 引导式 feature 开发（发现→探索→设计→实现→审查）        | 中型功能           |

## PRP 工作流（大型功能：PRD → PR）

PRP = Plan → Review → PR，为高风险/大型功能设计的严格端到端流程。

```text
/prp-prd        交互式生成产品需求文档（问题驱动）
    ↓
/prp-plan       深度代码库分析（8 个维度） + 生成自包含实现计划
                输出: .claude/PRPs/plans/{name}.plan.md
    ↓
/prp-implement  按计划逐步执行，每步验证（类型检查、lint、测试、构建）
                黄金法则：验证失败立即修，不积累破损状态
    ↓
/code-review    审查代码
    ↓
/prp-commit     用自然语言描述提交内容
    ↓
/prp-pr         创建 PR（自动发现模板、分析 commits）
```

## 三种典型场景

### 普通 feature

```
/plan → /tdd → -> /simplify → /prp-commit → /prp-pr
```

### Bug 修复

```
/tdd（先写复现 bug 的失败测试 → 修复 → 重构） → /simplify → /prp-commit → /prp-pr
```

核心理念：用测试锁定 bug，防止回归。

### 大功能（PRD 到 PR）

```
/prp-prd → /prp-plan → /prp-implement → /simplify → /prp-commit → /prp-pr
```

## 关键设计原则

- **研究先行**：编码前先 `gh search code`、查库文档、搜包注册表
- **规划先行**：`/plan` 或 `/prp-plan` 输出计划，确认后才写代码
- **测试先行**：TDD 强制 RED → GREEN → REFACTOR 循环
- **审查必做**：`/code-review` 在提交前执行，CRITICAL/HIGH 问题必须修复
- **约定式提交**：feat:、fix:、refactor:、docs:、test:、chore:、perf:、ci:
