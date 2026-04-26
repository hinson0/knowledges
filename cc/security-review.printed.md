# `/security-review` 命令来源与机制

## 定位结论

`security-review` **内置在 Claude Code CLI 的二进制里**(`~/.local/share/claude/versions/<version>`,Mach-O 可执行文件),不是任何第三方插件或用户自定义命令。

## 证据(二进制反编译片段)

```js
{
  name: "security-review",
  description: "Complete a security review of the pending changes on the current branch",
  progressMessage: "analyzing code changes for security risks",
  pluginName: "security-review",
  pluginCommand: "security-review",
  async getPromptWhileMarketplaceIsPrivate(H, _) { ... }
}
```

提取方式:

```bash
strings /Users/<user>/.local/share/claude/versions/<version> | grep -i "security-review"
```

## 关键观察

| 特征 | 说明 |
|------|------|
| **无插件前缀** | slash 命令列表里显示为 `security-review`,不是 `xxx:security-review` |
| **未在 `~/.claude/plugins/` 中** | 插件缓存目录只有同名但完全不同的 `security-guidance`(仅含 hook,不含 command) |
| **未在 `~/.claude/commands/` 中** | 用户自定义命令目录为空 |
| **prompt 硬编码进二进制** | `getPromptWhileMarketplaceIsPrivate` 表明 prompt 直接嵌在 CLI 里,marketplace 公开后可能迁出 |

## 同族内置命令

`security-review` 与以下命令同属 **Anthropic 官方内置 slash command**,prompt 编译进 CLI 可执行文件:

- `/init`
- `/review`
- `/code-review`
- `/security-review`

Marketplace 开放分发后才会迁到插件形式。

## 与第三方插件的区别

| 项 | `/security-review`(内置) | `pr-review-toolkit:*`(插件) |
|----|-------------------------|-------------------------------|
| 分发 | cc CLI 二进制 | `~/.claude/plugins/cache/pr-review-toolkit/` |
| 命名 | 无前缀 | 带 `pr-review-toolkit:` 前缀 |
| 覆盖面 | 单聚焦(只跑安全) | 套件(code/comment/type/silent-failure/test) |
| 可改 | ❌ 不可直接改 | ✅ 可以本地改 markdown |

## 覆盖/自定义方式

想改内置命令的 prompt 不可行(二进制只读),但可以**用同名 user command 覆盖**:

```bash
# 新建同名文件即可覆盖内置
mkdir -p ~/.claude/commands
touch ~/.claude/commands/security-review.md
```

cc 会优先读取 `~/.claude/commands/` 下的同名 markdown,不再使用二进制内置 prompt。

## 关键信号:`getPromptWhileMarketplaceIsPrivate`

这个函数名是强信号 — Anthropic 正在把内置命令逐步迁移到公开 marketplace,当前属于**过渡期内置兜底**状态。未来 CLI 升级后,这些命令可能从二进制中移除,改为默认安装的官方插件。

## 实际命令工作流

`/security-review` 执行时会做 3 步:

1. **子任务 1**:探索代码库,分析 PR 变更识别漏洞
2. **并行子任务**:对每个识别到的漏洞并行启动过滤子任务,排除 false positive
3. **过滤**:置信度 < 8 的全部丢弃

输出为纯 markdown 报告,严格按 `# Vuln N: <类别>: <文件:行号>` 格式。

## 内置的 False Positive 排除规则(摘要)

排除以下类型,避免噪音:

- DoS / 资源耗尽
- 磁盘上的机密(由其他流程处理)
- 速率限制问题
- 内存安全问题(Rust/内存安全语言)
- 日志欺骗 / 日志未脱敏
- 仅控制 path 的 SSRF
- AI prompt 注入(用户内容进 system prompt 不算漏洞)
- 正则注入 / ReDoS
- **文档文件中的问题**(markdown 等)
- 审计日志缺失
- React/Angular 的 XSS(除非用了 `dangerouslySetInnerHTML` 等)
- Shell 脚本中的命令注入(除非有明确外部输入路径)
