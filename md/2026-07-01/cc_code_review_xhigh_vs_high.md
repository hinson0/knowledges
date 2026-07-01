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
