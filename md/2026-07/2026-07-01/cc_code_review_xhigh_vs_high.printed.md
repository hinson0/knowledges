`/code-review high` 和 `/code-review xhigh` 的核心区别：**不是两个不同的 review 命令，而是同一个 Claude Code 自带 `code-review` 命令，使用不同的 effort / 推理强度。**

Claude Code 文档里说明，slash commands 可包含内置命令和 bundled skills，例如 `code-review`、`verify` 等。([Claude][1]) Anthropic 对 effort 的定义是：`high` 适合复杂推理、代码和 agentic 任务；`xhigh` 用于更难的代码任务、复杂 agentic 工作、需要更长探索、多次工具调用或详细搜索的场景。([克劳德平台][2])

### 简单理解

| 参数                 | 含义              | 适合场景                                                                    |
| -------------------- | ----------------- | --------------------------------------------------------------------------- |
| `/code-review high`  | 标准高强度 review | 小 PR、中等改动、CRUD、局部 bug、常规安全/质量检查                          |
| `/code-review xhigh` | 更高强度 review   | 大 PR、跨文件调用链、权限/安全/并发/事务/数据一致性、架构影响、历史代码复杂 |

### 实际差别

`high` 更像是：

> 认真看，但不会过度展开。

它通常会检查明显 bug、类型问题、边界条件、错误处理、风格问题、测试缺失等。

`xhigh` 更像是：

> 更愿意多想、多查、多沿着调用链追。

它更可能去看相关文件、上下文、配置、测试、迁移、权限、中间件、副作用。Anthropic 文档也明确说，较高 effort 可能会产生更多工具调用、更详细计划和更完整总结。([克劳德平台][2])

### 代价

`xhigh` 不等于绝对更好。它的代价是：

- 更慢；
- 消耗更多 token；
- review 可能更长；
- 有时会更“挑刺”，误报概率不一定更低；
- 对简单改动可能属于浪费。

Anthropic 文档也提到，`xhigh` 会比 `high` 有明显更高的 token 使用量。([克劳德平台][2])

### 我的建议

日常用：

```bash
/code-review high
```

这些情况再用：

```bash
/code-review xhigh
```

- 改了认证、权限、支付、订单、日志、导入导出；
- 改了数据库迁移、事务、队列、缓存；
- 改动跨多个模块；
- PR 很大；
- 你怀疑有隐藏 bug；
- 准备合并到 `master` / `main` / `release`。

一句话：**high 是常规认真 review；xhigh 是更深、更慢、更贵的 review。不是越高越应该默认用，复杂代码才值得用。**

[1]: https://code.claude.com/docs/en/agent-sdk/slash-commands "Slash Commands in the SDK - Claude Code Docs"
[2]: https://platform.claude.com/docs/en/build-with-claude/effort "Effort - Claude Platform Docs"

---

你这里有一个点要先纠正：**官方命令参数里我看到的是 `--fix` 和 `--comment`，不是 `--commit`**。Claude Code 文档里的格式是：

```bash
/code-review [low|medium|high|xhigh|max|ultra] [--fix] [--comment] [target]
```

官方说明：`--fix` 是把 review 发现的问题应用到你的 working tree；`--comment` 是把发现的问题作为 GitHub PR inline comments 发出去。([Claude][1])

## 1. 不加 `--fix` / `--comment`

例如：

```bash
/code-review high
```

效果是：**只 review，不改代码，不发 PR 评论，不提交 commit。**

它会检查当前 diff。默认范围一般是：

- 当前分支相对 upstream 多出来的 commits；
- 以及当前 working tree 里未提交的改动。

然后在 Claude Code 终端里告诉你发现了什么问题。官方也说，本地 `/code-review` 默认是 review diff；可以传文件路径、PR 编号、分支名、ref range 来改变 review 目标。([Claude][2])

可以理解成：

```text
只看问题 → 给你报告 → 你自己决定改不改
```

适合日常最安全用法。

---

## 2. 加 `--fix`

例如：

```bash
/code-review high --fix
```

效果是：**review 完之后，Claude 会尝试把发现的问题直接改到你的工作区。**

注意：它是改你的文件，不是只给建议。官方原文含义就是：`--fix` 会把 findings 应用到 working tree。([Claude][1])

可以理解成：

```text
先 review → 找到问题 → 自动修改本地文件
```

但它通常不会等同于自动 commit。你还是应该自己检查：

```bash
git diff
git status
```

然后再跑测试：

```bash
pnpm test
# 或
composer test
# 或
php artisan test
```

确认没问题后你再手动 commit。

我的建议：**`--fix` 不要无脑加。**
适合小范围、低风险改动，比如命名、重复代码、简单逻辑问题。涉及数据库、权限、认证、订单、支付、日志审计这种，先不加 `--fix`，看完报告再决定。

---

## 3. 加 `--comment`

例如：

```bash
/code-review high --comment
```

效果是：**把 review 发现的问题发到 GitHub PR 的 inline comments。**

官方说明：`--comment` 用来把 findings 作为 GitHub PR inline comments 发出去。([Claude][2])

可以理解成：

```text
先 review → 找到问题 → 发到 PR 评论里
```

这个适合你想让团队成员在 PR 页面看到 review 结果。

但你自己本地先自查时，不建议默认加 `--comment`，否则容易把不成熟的 AI review 噪音发到 PR 上。

---

## 4. 关于你说的 `--commit`

我在当前官方文档里没有看到 `/code-review --commit` 这个参数。官方列的是：

```bash
--fix
--comment
```

不是：

```bash
--commit
```

所以你这里大概率是把 `--comment` 记成了 `--commit`。

如果你的 Claude Code 版本里真的显示了 `--commit`，那要以你本地帮助为准：

```bash
/code-review --help
```

但按官方文档，`/code-review` 本身不是“自动提交代码”的命令。自动提交通常应该是你单独确认后再执行 `git commit`。

---

## 推荐用法

日常安全 review：

```bash
/code-review high
```

想让它直接修：

```bash
/code-review high --fix
```

大改动深度 review：

```bash
/code-review xhigh
```

大改动但想自动修，谨慎用：

```bash
/code-review xhigh --fix
```

PR 上发评论：

```bash
/code-review high --comment
```

一句话：**不加参数 = 只看不动；加 `--fix` = 会改你本地文件；加 `--comment` = 会发 GitHub PR 评论；`--commit` 不是官方文档里的 code-review 参数。**

[1]: https://code.claude.com/docs/en/commands "Commands - Claude Code Docs"
[2]: https://code.claude.com/docs/en/code-review "Code Review - Claude Code Docs"
