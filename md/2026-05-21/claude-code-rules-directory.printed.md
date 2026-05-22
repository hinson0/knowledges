# Claude Code `.claude/rules/` 约定目录自动加载机制

## 触发提问

> 按照 Cloud Code,它对 `@.claude/rules` 应该是自动加载,那我需要在 Cloud CMD 里面去,at 这种方式去引用它吗?

## 关键结论

- **`.claude/rules/` 是 Claude Code 的原生约定目录**,不是用户自建的普通目录。该目录下所有 `.md` 文件会被**递归扫描并在 session 启动时自动加载**进上下文。
- **无 `paths` frontmatter 的 rule 文件 = 无条件加载**,优先级与 `.claude/CLAUDE.md` 相同。
- **带 `paths` frontmatter = 路径条件加载**,只在 Claude 读到匹配 glob 的文件时才注入。
- **CLAUDE.md 里再写 `@.claude/rules/foo.md` 是冗余的** —— 同一份内容会通过两个机制各加载一次。
- 推荐:**删掉 CLAUDE.md 里指向 `.claude/rules/` 的 `@import` 行**,让自动加载机制独家负责;CLAUDE.md 控制在 ≤200 行(官方建议)。
- 用户级 rules: **`~/.claude/rules/`** 跨所有项目自动加载,优先级低于项目级 rules。
- 验证手段: **`/memory` 命令**列出当前 session 所有已加载的 CLAUDE.md / rules 文件。
- 调试手段: **`InstructionsLoaded` hook** 可输出哪些规则文件被加载、何时加载、为什么。

## Schema / 字段表

### `.claude/rules/` 目录布局

```text
your-project/
├── .claude/
│   ├── CLAUDE.md           # 主项目说明
│   └── rules/
│       ├── code-style.md   # 无 paths → 全局加载
│       ├── testing.md      # 无 paths → 全局加载
│       ├── api-design.md   # 有 paths → 条件加载
│       └── backend/        # 支持子目录,递归扫描
│           └── db.md
```

### Rule 文件的 YAML frontmatter

| 字段 | 类型 | 含义 |
|------|------|------|
| `paths` | `list[str]` 或不存在 | 不存在 → 无条件加载;存在 → 仅 Claude 读匹配 glob 的文件时注入 |

### `paths` glob 模式示例

| Pattern | 匹配 |
|---------|------|
| `**/*.ts` | 所有 TS 文件 |
| `src/**/*` | `src/` 下全部 |
| `*.md` | 项目根 md |
| `src/components/*.tsx` | 特定目录组件 |
| `src/**/*.{ts,tsx}` | 多扩展名(brace expansion) |

## 代码示例

### 条件加载的 rule 文件

```markdown
---
paths:
  - "src/api/**/*.ts"
---

# API Development Rules

- All API endpoints must include input validation
- Use the standard error response format
- Include OpenAPI documentation comments
```

### 跨项目共享 rules(符号链接)

```bash
ln -s ~/shared-claude-rules .claude/rules/shared
ln -s ~/company-standards/security.md .claude/rules/security.md
```

### 用户级 rules

```text
~/.claude/rules/
├── preferences.md    # 全局编码偏好
└── workflows.md      # 全局工作流
```

## 坑 / Why

### 坑 1: 以为 `.claude/rules/` 不是约定目录

很容易把它当成"用户自建的子目录,得用 `@import` 才能加载"。**错**。它是 Claude Code 的原生约定目录,与 `.claude/commands/`、`.claude/agents/`、`.claude/skills/` 同级。

> 官方原文(`code.claude.com/docs/en/memory`):
> "Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`."

### 坑 2: 既自动加载又 `@import` → 内容进上下文两次

CLAUDE.md 里写:

```markdown
@.claude/rules/repo-structure.md   ← @import 展开一次
```

同时 `.claude/rules/repo-structure.md` 文件也会被自动加载机制扫到 → 再注入一次。

虽然实际效果上 Claude 不会"反复执行规则",但**白白消耗 token 预算**,且让维护者困惑"到底哪个机制在生效"。

### 坑 3: CLAUDE.md 主项目说明可以放在两个位置

| 位置 | 等价? |
|------|------|
| `./CLAUDE.md` | ✅ |
| `./.claude/CLAUDE.md` | ✅ |

两者**任选其一**即可,不要同时放(否则一份内容被加载两次)。

### Why: 为什么 Anthropic 设计两套机制?

- **CLAUDE.md** —— 单文件、给"项目门面级"的核心说明
- **`.claude/rules/`** —— 多文件、按主题拆分,适合大项目把规则模块化(testing / security / api-design 各一个文件)
- **`paths` frontmatter** —— 进一步把"只跟某些目录相关的规则"按需加载,节省全局上下文

如果项目只有少量规则,只用 CLAUDE.md;规则多了再迁到 `.claude/rules/`。**不要混着用同一份内容**。

## 关联

- [[claude-md-import-syntax]] —— CLAUDE.md 的 `@import` 语法机制(展开规则、递归深度、与 rules 的区别)
- [[subagent-answer-verification]] —— 本主题的发现过程暴露了 subagent 凭印象答错的陷阱,必须 WebFetch 实锤
