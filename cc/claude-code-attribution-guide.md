# Claude Code 归属设置（Attribution）指南

## 什么是归属设置

控制 Claude Code 在**创建 git commit 和 PR 时自动附加的署名信息**，用于标识哪些工作有 AI 参与。

## 配置位置

在 `~/.claude/settings.json`（全局）或 `.claude/settings.json`（项目级）中配置：

```json
{
  "attribution": {
    "commit": "提交时附加的文本",
    "pr": "创建 PR 时附加的文本"
  }
}
```

## 两个字段

| 字段 | 作用 | 附加位置 |
|------|------|---------|
| `commit` | commit message 末尾的归属文本 | 每次 git commit |
| `pr` | PR body 末尾的归属文本 | 每次 gh pr create |

## 效果示例

### 配置

```json
{
  "attribution": {
    "commit": "🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
    "pr": "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  }
}
```

### 实际 commit 效果

```
feat: add user authentication

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
```

### 实际 PR 效果

PR body 末尾会附加：

```
🤖 Generated with Claude Code
```

## 自定义方式

| 需求 | 配置 |
|------|------|
| 关闭归属 | `"commit": ""`, `"pr": ""` |
| 仅保留 Co-Authored-By | `"commit": "Co-Authored-By: Claude <noreply@anthropic.com>"` |
| 完全自定义 | 写任意文本 |

## Co-Authored-By 说明

`Co-Authored-By: Claude <noreply@anthropic.com>` 是 GitHub 标准的多作者格式：

- GitHub 会在 commit 页面显示 Claude 作为共同作者
- 便于团队透明度——其他人能一眼看出哪些 commit 有 AI 参与
- 在 `git log` 中也能看到归属信息
