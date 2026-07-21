你提供的 GitHub 链接对应的 `code-review` 插件的翻译如下，内容无删减：

---

## 代码审查插件

**文件路径**: `claude-plugins-official/plugins/code-review`

**描述**: 通过多个专用智能体并使用基于置信度的评分来过滤误报，对拉取请求进行自动化代码审查。

## 概述

代码审查插件通过并行启动多个智能体，从不同角度独立审计代码变更，以实现拉取请求审查的自动化。它利用置信度评分来过滤误报，确保只发布高质量、可执行的反馈。

## 命令

### `/code-review`

使用多个专用智能体对拉取请求执行自动化代码审查。

**它做什么：**

1.  检查是否需要审查（跳过已关闭、草稿、琐碎或已审查过的 PR）。
2.  从代码仓库收集相关的 `CLAUDE.md` 指导文件。
3.  总结拉取请求的变更。
4.  启动 4 个并行智能体进行独立审查：
    - **智能体 #1 和 #2**: 审计 `CLAUDE.md` 的合规性。
    - **智能体 #3**: 扫描变更中明显的 Bug。
    - **智能体 #4**: 分析 git blame/历史记录，以发现基于上下文的问题。
5.  为每个问题评定 0-100 的置信度分数。
6.  过滤掉低于 80 分置信度阈值的问题。
7.  仅发布包含高置信度问题的审查评论。

**用法:**

```
/code-review
```

**示例工作流:**

```bash
# 在 PR 分支上，运行:
/code-review

# Claude 将:
# - 并行启动 4 个审查智能体
# - 为每个问题评定置信度分数
# - 发布包含置信度≥80 的问题的评论
# - 如果没有发现高置信度问题，则跳过发布
```

**特性:**

- 多个独立智能体进行全面审查。
- 基于置信度的评分减少误报（阈值：80）。
- 通过明确的指南验证进行 `CLAUDE.md` 合规性检查。
- Bug 检测专注于变更（而非已存在的问题）。
- 通过 git blame 进行历史上下文分析。
- 自动跳过已关闭、草稿或已审查过的 PR。
- 使用完整的 SHA 和行范围直接链接到代码。

**审查评论格式:**

```
## Code review
Found 3 issues:

1. Missing error handling for OAuth callback (CLAUDE.md says "Always handle OAuth errors")
   https://github.com/owner/repo/blob/abc123.../src/auth.ts#L67-L72

2. Memory leak: OAuth state not cleaned up (bug due to missing cleanup in finally block)
   https://github.com/owner/repo/blob/abc123.../src/auth.ts#L88-L95

3. Inconsistent naming pattern (src/conventions/CLAUDE.md says "Use camelCase for functions")
   https://github.com/owner/repo/blob/abc123.../src/utils.ts#L23-L28
```

**置信度评分:**

- **0**: 不确信，是误报。
- **25**: 有些确信，可能是真实问题。
- **50**: 中度确信，是真实但次要的问题。
- **75**: 高度确信，是真实且重要的问题。
- **100**: 绝对肯定，肯定是真实问题。

**已过滤的误报:**

- 非 PR 引入的已存在问题。
- 看起来像 Bug 但实际不是的代码。
- 学究式的吹毛求疵。
- Linter 能捕获的问题。
- 一般质量问题（除非在 `CLAUDE.md` 中说明）。
- 带有 lint 忽略注释的问题。

## 安装

此插件包含在 Claude Code 仓库中。使用 Claude Code 时，该命令会自动可用。

## 最佳实践

### 使用 `/code-review`

- 维护清晰的 `CLAUDE.md` 文件，以便更好地进行合规性检查。
- 信任 80+ 的置信度阈值——误报已被过滤。
- 对所有非琐碎的拉取请求运行此命令。
- 将智能体的发现作为人工审查的起点。
- 根据重复出现的审查模式更新 `CLAUDE.md`。

### 何时使用

- 所有有意义的变更的拉取请求。
- 触及关键代码路径的 PR。
- 来自多位贡献者的 PR。
- 指南合规性很重要的 PR。

### 何时不使用

- 已关闭或草稿的 PR（无论如何都会被自动跳过）。
- 琐碎的自动化 PR（会被自动跳过）。

---

### `/code-review` 命令定义

**文件路径**: `plugins/code-review/commands/code-review.md`

**允许的工具**: `Bash(gh issue view:*)`, `Bash(gh search:*)`, `Bash(gh issue list:*)`, `Bash(gh pr comment:*)`, `Bash(gh pr diff:*)`, `Bash(gh pr view:*)`, `Bash(gh pr list:*)`

**描述**: 代码审查一个拉取请求。

**禁用模型调用**: `false`

**流程描述**:
为给定的拉取请求提供代码审查。为此，请严格遵循以下步骤：

- 使用一个 Haiku 智能体检查拉取请求是否 (a) 已关闭，(b) 是草稿，(c) 不需要代码审查（例如，因为是自动化拉取请求，或非常简单且明显没问题），或 (d) 已经有过代码审查。如果是，则不再继续。
- 使用另一个 Haiku 智能体提供代码库中所有相关 `CLAUDE.md` 文件的路径列表（但不包含文件内容）：根目录下的 `CLAUDE.md` 文件（如果存在），以及拉取请求所修改文件所在目录下的所有 `CLAUDE.md` 文件。
- 使用一个 Haiku 智能体查看拉取请求，并要求该智能体返回变更的摘要。
- 然后，启动 5 个并行的 Sonnet 智能体来独立审查代码变更。这些智能体应执行以下操作，然后返回问题列表以及每个问题被标记的原因（例如，`CLAUDE.md` 合规性、Bug、历史 git 上下文等）：
  a. **智能体 #1**: 审计变更，确保其符合 `CLAUDE.md` 的要求。请注意，`CLAUDE.md` 是 Claude 编写代码时的指导，并非所有指令在代码审查期间都适用。
  b. **智能体 #2**: 阅读拉取请求中的文件变更，然后进行浅层扫描以查找明显的 Bug。避免阅读变更之外的额外上下文，仅关注变更本身。重点关注大型 Bug，避免小问题和吹毛求疵。忽略可能的误报。
  c. **智能体 #3**: 阅读被修改代码的 git blame 和历史记录，以识别基于该历史上下文的任何 Bug。
  d. **智能体 #4**: 阅读之前触及这些文件的拉取请求，并检查这些拉取请求中是否有任何可能同样适用于当前拉取请求的评论。
  e. **智能体 #5**: 阅读已修改文件中的代码注释，并确保拉取请求中的变更符合注释中的任何指导。
- 对于步骤 4 中发现的每个问题，启动一个并行的 Haiku 智能体，该智能体会接收 PR、问题描述以及（来自步骤 2 的）`CLAUDE.md` 文件列表，并返回一个分数，以指示该智能体对问题是否为真实问题或误报的置信度。为此，该智能体应按照 0-100 的等级为每个问题评分，表明其置信度水平。对于因 `CLAUDE.md` 指令而被标记的问题，该智能体应仔细检查 `CLAUDE.md` 是否确实明确指出了该问题。评分标准如下（逐字提供给智能体）：
  a. **0**: 完全不确信。这是一个经不起推敲的误报，或者是已存在的问题。
  b. **25**: 有些确信。这可能是一个真实问题，但也可能是误报。该智能体无法验证其为真实问题。如果是风格问题，则是一个未被明确提出来的问题。

### `code-review` 插件配置

**文件路径**: `plugins/code-review/.claude-plugin/plugin.json`

```json
{
  "name": "code-review",
  "description": "Automated code review for pull requests using multiple specialized agents with confidence-based scoring",
  "author": {
    "name": "Anthropic",
    "email": "support@anthropic.com"
  }
}
```
