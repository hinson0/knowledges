# CLAUDE.md `@import` 语法与加载机制

## 触发提问

> 按照 Cloud Code,它对 `@.claude/rules` 应该是自动加载,那我需要在 Cloud CMD 里面去,at 这种方式去引用它吗?

## 关键结论

- **`@path/to/file.md` 是 CLAUDE.md 的 import 语法**,而非"声明文件存在"。本质是**纯文本展开拼接** —— 被引用文件内容会原样替换到 `@` 行,在 session 启动时进入上下文。
- **递归深度上限 5 跳**(imports 可以 import 别的 imports)。
- **路径解析以"包含 import 的文件"为基准**,不是 cwd。相对/绝对路径都支持。
- **首次遇到外部 import 会弹批准对话框**;拒绝后该 import 永久禁用且不再弹。
- **CLAUDE.md vs `.claude/rules/` 是两个独立机制**,但都在启动时把内容塞进上下文。`.claude/rules/` 是约定目录自动扫描,CLAUDE.md 是显式 import。
- **用户消息里的 `@filename` 和 CLAUDE.md 里的 `@import` 是不同特性**:前者是 file mention(本轮一次性附件),后者是 CLAUDE.md import 语法(每次启动常驻)。
- **`@import` 用 imports 拆分内容并不能节省上下文** —— 文件依然全量加载。要节省上下文,用 `paths` 限定的 `.claude/rules/`,而不是 `@import`。

## Schema / 字段表

### CLAUDE.md 在文件系统的查找规则

Claude Code 从 cwd 向上**遍历目录树**,每层都找 `CLAUDE.md` 和 `CLAUDE.local.md`,全部拼接进上下文。

| 位置 | Scope | 加载时机 |
|------|-------|---------|
| `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS) | Managed policy | 启动 |
| `/etc/claude-code/CLAUDE.md` (Linux/WSL) | Managed policy | 启动 |
| `C:\Program Files\ClaudeCode\CLAUDE.md` (Windows) | Managed policy | 启动 |
| `~/.claude/CLAUDE.md` | User instructions | 启动 |
| `./CLAUDE.md` 或 `./.claude/CLAUDE.md` | Project instructions | 启动 |
| `./CLAUDE.local.md` | Local instructions(gitignored) | 启动 |
| 子目录里的 `CLAUDE.md` | Subdirectory | **懒加载**:Claude 读子目录文件时才载入 |

加载顺序: **filesystem root → cwd**(广义 → 具体)。同目录内 `CLAUDE.local.md` 排在 `CLAUDE.md` 之后。

### `@import` 与 `.claude/rules/` 对比

| 维度 | `@import` (in CLAUDE.md) | `.claude/rules/*.md` |
|------|--------------------------|----------------------|
| 触发方式 | 显式声明(写 `@path`) | 约定目录自动扫描 |
| 加载时机 | 启动时展开 | 启动时加载(无 `paths`) |
| 路径解析基准 | 包含 import 的文件 | `.claude/rules/` 固定 |
| 子目录递归 | 通过链式 `@import` 实现 | 原生递归扫描 |
| 条件加载 | 不支持 | 支持(`paths` frontmatter) |
| 节省上下文 | ❌(全量展开) | ✅(`paths` 限定时按需) |
| 适用场景 | 引用 README/AGENTS.md 等外部文件 | 项目内规则模块化 |

### 用户消息里的 `@filename` vs CLAUDE.md 的 `@import`

| 维度 | 消息中的 `@file` (file mention) | CLAUDE.md 中的 `@file` (import) |
|------|--------------------------------|--------------------------------|
| 生效范围 | 本轮一次性 | 每次 session 启动常驻 |
| 谁读取 | CLI 把文件作为附件塞进当前消息 | CLAUDE.md 加载时纯文本展开 |
| 路径基准 | cwd | 包含 import 的文件 |

## 代码示例

### 基本 `@import`

```markdown
See @README for project overview and @package.json for available npm commands.

# Additional Instructions
- git workflow @docs/git-instructions.md
```

### 引用 AGENTS.md(兼容其他 coding agent 生态)

```markdown
@AGENTS.md

## Claude Code

Use plan mode for changes under `src/billing/`.
```

或符号链接(非 Windows):

```bash
ln -s AGENTS.md CLAUDE.md
```

### 跨 worktree 共享个人偏好

`CLAUDE.local.md` 是 gitignored 的本地文件,**不会跨 worktree 同步**。若要跨 worktree 共享个人偏好,改用 home 目录 import:

```markdown
# Individual Preferences
- @~/.claude/my-project-instructions.md
```

### 加载额外目录的 CLAUDE.md

```bash
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir ../shared-config
```

这会同时加载 `../shared-config/` 下的 `CLAUDE.md`、`.claude/CLAUDE.md`、`.claude/rules/*.md`、`CLAUDE.local.md`。

### Monorepo 排除其它团队的 CLAUDE.md

`.claude/settings.local.json`:

```json
{
  "claudeMdExcludes": [
    "**/monorepo/CLAUDE.md",
    "/home/user/monorepo/other-team/.claude/rules/**"
  ]
}
```

Glob 匹配的是**绝对路径**。Managed policy CLAUDE.md 无法被排除。

### 给维护者的隐藏注释

```markdown
<!-- maintainer notes: 这段对 Claude 不可见,只给人看 -->
```

块级 HTML 注释会在注入上下文前被剥离,**节省 token**。代码块内的注释保留。

## 坑 / Why

### 坑 1: 以为 `@import` 能节省上下文

`@import` **不节省 token** —— 被引用文件全量展开进上下文。它只用来"组织文件结构",不是性能优化。

要真正按需加载,用:
- **`.claude/rules/` + `paths` frontmatter** —— 路径条件加载
- **`.claude/skills/`** —— 按需触发(用户调用 `/skill-name` 或 Claude 判断相关时才加载)
- **`/memory` 中的 topic files** —— `MEMORY.md` 是索引,详细 topic md 按需 Read

### 坑 2: 相对路径基准搞错

`@docs/git-instructions.md` 在 `./CLAUDE.md` 里是 `./docs/git-instructions.md`,放进 `./.claude/CLAUDE.md` 就变成 `./.claude/docs/git-instructions.md`。

**相对路径基准是包含 import 的文件**,不是 cwd。迁移 CLAUDE.md 位置时检查所有 `@` 路径。

### 坑 3: `/init` 在已有 AGENTS.md / .cursorrules 时的行为

`/init` 会**读取**已有的 AGENTS.md、`.cursorrules`、`.windsurfrules`,把相关部分**摘要合并**进新生成的 CLAUDE.md。**不会原样复制**。如果原文重要,事后核对。

### 坑 4: `/compact` 后嵌套 CLAUDE.md 丢失

- ✅ 项目根 `CLAUDE.md` —— compact 后从磁盘重读,自动重新注入
- ❌ 子目录 `CLAUDE.md` —— 不会自动重新注入,下次 Claude 读该子目录文件时才重新加载
- ❌ 会话里临时给的指令 —— 完全丢失,要么写进 CLAUDE.md,要么让 auto memory 落盘

### Why: 为什么 import 不能解决大文件问题?

CLAUDE.md 是**作为 user message** 在 system prompt 之后注入的(不是 system prompt 本身)。`@import` 只是文本展开,展开后总量没变,Claude 注意力被稀释 → 长 CLAUDE.md adherence 下降。

正确解法:
1. 拆到 `.claude/rules/` 用 `paths` 限定
2. 拆到 `.claude/skills/` 按需触发
3. 删掉过时/低价值规则

## 关联

- [[claude-code-rules-directory]] —— `.claude/rules/` 约定目录的完整机制(本主题反复对比的对象)
- [[subagent-answer-verification]] —— 求证 `@import` 行为的过程暴露了 subagent 凭印象答错的陷阱
