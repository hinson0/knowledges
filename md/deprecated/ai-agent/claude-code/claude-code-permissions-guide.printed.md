# Claude Code 权限系统指南

## 1. 权限配置文件层级

Claude Code 使用多层配置体系，优先级从高到低：

| 层级 | 位置 | 提交到 Git？ | 影响范围 |
|------|------|:-----------:|---------|
| **Enterprise/Managed** | 系统级 `managed-settings.json` | — | 机器上所有用户（IT 部署，无法覆盖） |
| **User（全局）** | `~/.claude/settings.json` | — | 你在所有项目中 |
| **Project（项目共享）** | `.claude/settings.json` | **是** | 项目所有协作者 |
| **Local（项目私有）** | `.claude/settings.local.json` | **否** | 仅你，仅此项目 |
| **CLI 参数** | `--allowedTools`, `--disallowedTools` | — | 当前会话 |

### 关键规则

- **高层级的 deny 无法被低层级覆盖**：Enterprise 禁止的操作，User/Project 无法放行
- **同一层级内**：`Deny > Allow`，deny 永远优先
- **低层级可以细化高层级的 allow**：例如全局允许 `Bash(*)`，项目级可以 deny 掉 `Bash(rm -rf *)`

---

## 2. 三个配置文件的用途

### `~/.claude/settings.json`（全局配置）

你的个人全局偏好，适用于所有项目。

**适合配置：**
- 你日常开发通用的权限（如 `Read(*)`、`Edit(*)`）
- `defaultMode` 设置
- 插件启用列表
- 语言、主题等个人偏好

### `.claude/settings.json`（项目共享配置）

**会提交到 git**，影响所有克隆此项目的协作者。

**适合配置：**
- 项目的安全基线（团队统一遵守的权限策略）
- 项目特有的工具权限（如允许 `pnpm`、`npx expo` 等）
- 禁止危险操作的 deny 规则

**不适合配置：**
- `Bash(*)` 这样的通配符（会让所有协作者都无限制）
- 包含个人路径的命令

### `.claude/settings.local.json`（项目私有配置）

**不提交到 git**（自动 gitignore），仅对你生效。

**特点：**
- 每次你在对话中点"允许并记住"时，权限自动写入此文件
- 随着开发过程逐渐累积具体命令
- 可以定期清理不再需要的条目

---

## 3. 通配符 vs 细粒度权限

### `Bash(*)` — 通配符权限

```json
{ "permissions": { "allow": ["Bash(*)"] } }
```

**含义：** 允许执行任何 Bash 命令，无需确认。

**风险：**
- 可执行 `rm -rf /`、`rm -rf ~` 等破坏性命令
- 可执行 `curl`、`ssh` 向外部发送数据
- 容易被 prompt injection 攻击利用
- 在项目 settings.json 中使用会影响所有协作者

**适用场景：** 仅在完全隔离的容器/VM 中，或你完全信任环境时使用。

### 细粒度权限 — 明确指定

```json
{
  "permissions": {
    "allow": [
      "Bash(pnpm test)",
      "Bash(pnpm lint)",
      "Bash(git commit -m *)",
      "Bash(npx expo start)"
    ]
  }
}
```

**含义：** 只允许列出的命令，其他命令需要确认。

**优势：**
- 默认拒绝，只允许必需的操作
- 即使被 prompt injection，也只能执行预列出的命令
- 权限历史记录清晰，可审计

### 通配符的合理用法

`*` 可以用在命令的参数部分，限制命令本身：

```json
"allow": [
  "Bash(pnpm *)",       // 允许所有 pnpm 子命令
  "Bash(git commit *)",  // 允许 git commit 的各种参数
  "Bash(cd * && pnpm *)" // 允许在任意目录下运行 pnpm
]
```

这比 `Bash(*)` 安全得多——限制了命令的前缀，只开放参数部分。

---

## 4. Allow 和 Deny 的交互

### 评估优先级

```
Deny > Allow
```

deny 规则**永远优先**于 allow，即使 allow 中有更精确的匹配。

### 示例

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)",
      "Bash(curl * > *)"
    ],
    "allow": [
      "Bash(pnpm *)",
      "Bash(git *)",
      "Bash(npx *)"
    ]
  }
}
```

**评估流程示例：**

| Claude 尝试执行 | 检查 deny | 检查 allow | 结果 |
|-----------------|----------|-----------|------|
| `pnpm test` | 不匹配 | 匹配 `pnpm *` | ✅ 自动执行 |
| `rm -rf ./dist` | 匹配 `rm -rf *` | — | ❌ 拒绝 |
| `sudo apt install` | 匹配 `sudo *` | — | ❌ 拒绝 |
| `python script.py` | 不匹配 | 不匹配 | ⚠️ 提示用户确认 |

### "先开放，再收紧" 模式

这是推荐的配置策略：
1. 用 allow 通配符覆盖日常开发场景
2. 用 deny 精确禁止危险操作
3. 未匹配的命令会提示用户确认（默认行为）

---

## 5. defaultMode 权限模式

`defaultMode` 控制 Claude Code **会话启动时**进入的权限模式，也决定了未匹配到 allow/deny 规则时的默认行为。

### 配置位置

字段嵌套在 `permissions` 对象下，与 `allow`、`deny` 平级（**容易写错成顶级字段**）：

```json
{
  "permissions": {
    "defaultMode": "plan"
  }
}
```

### 支持的所有值

| Mode                 | 行为                                                    | 适用场景                                             |
| -------------------- | ------------------------------------------------------- | ---------------------------------------------------- |
| `default`            | 提示用户确认，可选择"允许并记住"                        | 日常开发（系统默认）                                 |
| `acceptEdits`        | 自动接受文件编辑，其他操作仍提示                        | 已信任 Claude 做代码改动、只想管住 Bash              |
| `plan`               | 只读模式——可读取但不能修改文件或执行命令；产出 plan      | 代码审查、重构前规划、不想让它乱动手的场景           |
| `auto`               | 接近 `acceptEdits`，但更宽松                            | 已深度验证过的重复性任务                             |
| `dontAsk`            | 不再弹出确认提示，按 allow/deny 静默处理                | 已完整配置好权限列表、嫌提示烦                       |
| `bypassPermissions`  | 跳过所有权限检查，自动允许一切                          | **仅限隔离环境（容器/VM），极度危险**                |

### 优先级（由高到低）

```
CLI 参数 (--permission-mode plan)
  > 项目级 .claude/settings.json
    > 全局 ~/.claude/settings.json
      > 系统默认 (default)
```

**实用推论：**
- 项目级需要特殊策略时，可以覆盖全局的 `defaultMode`
- CLI 参数永远是最终兜底——单次会话想临时进入 plan 模式不用改配置：`claude --permission-mode plan`

### 默认启用 Plan 模式

想让每次启动 Claude Code 自动进入 Plan 模式（先出计划再动手），在 `~/.claude/settings.json` 中把 `permissions.defaultMode` 改成 `plan`：

```diff
  "permissions": {
    "allow": [...],
-   "defaultMode": "default"
+   "defaultMode": "plan"
  }
```

**Plan 模式的适用判断：**

| 场景                                     | 是否适合 Plan 默认              |
| ---------------------------------------- | ------------------------------- |
| 复杂任务（需先梳理思路再动手）           | ✅ 适合                         |
| 希望在 AI 动手前先看到"它打算怎么做"      | ✅ 适合                         |
| 琐碎小改动、一句话能说清的任务             | ❌ 不适合（每次都要先 plan 拖慢节奏）|

**折中方案**：全局保持 `default`，只在需要长流程的项目里用项目级 settings 覆盖为 `plan`。

### 相关官方文档

- [Settings documentation](https://code.claude.com/docs/en/settings.md)
- [Permission modes](https://code.claude.com/docs/en/permission-modes.md)

---

## 6. 最佳实践

### 项目 settings.json 推荐模板

```json
{
  "permissions": {
    "allow": [
      "Read(*)",
      "Edit(*)",
      "Write(*)",
      "Bash(pnpm *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(git *)",
      "Bash(ls *)",
      "Bash(cd * && pnpm *)",
      "Bash(cd * && npx *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)"
    ]
  }
}
```

### 安全原则

1. **项目 settings.json 中避免 `Bash(*)`** — 它会影响所有协作者
2. **全局 settings.json 中的 `Bash(*)` 要谨慎** — 仅在你充分理解风险时使用
3. **用 deny 列表作为安全护栏** — 禁止已知的危险操作
4. **定期清理 settings.local.json** — 删除不再需要的临时权限
5. **Read/Edit/Write 的通配符相对安全** — 它们不涉及系统命令执行

### 常见反模式

| 反模式 | 问题 | 改进 |
|--------|------|------|
| 项目 settings.json 中 `Bash(*)` | 所有协作者无限制执行命令 | 改用 `Bash(pnpm *)` 等限定前缀 |
| `Bash(curl *)` 在 allow 中 | 可以访问任意 URL | 不要 allow，让它触发确认 |
| settings.local.json 积累过多条目 | 难以维护和审查 | 定期清理，常用命令提升到 settings.json |
| 没有 deny 规则 | 缺少安全护栏 | 至少禁止 `rm -rf *` 和 `sudo *` |
