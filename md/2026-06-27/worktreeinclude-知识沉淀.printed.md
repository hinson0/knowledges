# `.worktreeinclude` 知识沉淀

## 一句话定义

`.worktreeinclude` 是一个放在**项目根目录**的约定文件，作用类似「反向的 `.gitignore`」：它列出那些被 Git 忽略、但在创建新 worktree 时**仍需要复制过去**的本地文件。

---

## 解决的问题

Git worktree 在创建新工作目录时，**只复制被 Git 跟踪（tracked）的文件**。

像下面这些被 `.gitignore` 忽略的本地文件不会自动带过去：

- `.env` / `.env.local` 等环境变量文件
- `config/master.key`、密钥、证书
- `.vscode/settings.json` 等本地 IDE 配置

结果就是：新 worktree 里的程序经常因为缺少这些配置而**跑不起来或静默失败**。`.worktreeinclude` 就是用来把这些本地文件自动补齐到每个新 worktree。

---

## 谁在用：Git 还是工具？

**是上层工具用的，不是 Git 用的。**

| 角色 | 职责 |
|------|------|
| **Git** | 负责 worktree 的底层机制（`git worktree add` 等命令），**完全不认识** `.worktreeinclude`，也不会读取它 |
| **工具**（Claude Code、worktrunk、Roo Code、CodeBuddy 等） | 在创建 worktree 时，**自己去读** `.worktreeinclude`，按规则把文件复制到新 worktree |

> 关键结论：纯用 `git worktree` 命令时，`.worktreeinclude` **不生效**。只有通过支持该约定的工具创建 worktree 才有效。它只是**借用了 `.gitignore` 的语法**，并不是 Git 的原生功能。

---

## 文件位置与语法

- **位置**：项目根目录
- **语法**：与 `.gitignore` 完全相同
- **建议**：把它**提交到 Git**，让团队所有成员都能受益

```gitignore
# .worktreeinclude
.env
.env.local
config/master.key
.vscode/settings.json
```

---

## 核心规则：双重条件（重要安全限制）

一个文件被复制，必须**同时满足两个条件**：

1. 匹配 `.worktreeinclude` 里的某个模式
2. 被 `.gitignore` 忽略

> 也就是说：**被 Git 跟踪的文件永远不会被复制**。这避免了不小心把版本控制中的文件在 worktree 之间乱同步。

部分实现还有额外保护：如果目标位置已存在同名但内容不同的文件，**默认不覆盖**（某些工具需显式加 `--force` 才覆盖）。

---

## 路径行为：镜像目录，保留相对路径

文件会被复制到**与源文件相同的相对路径**，而不是塞到根目录。工具会自动创建中间目录。嵌套文件同样支持。

**示例：** 源文件在 `apps/web/.env.local`

- ✅ 复制到 → 新 worktree 的 `apps/web/.env.local`
- ❌ 不会复制到 → 新 worktree 根目录的 `.env.local`

两种写法都能命中该文件：

```gitignore
# 写法一：精确路径（推荐，控制精准）
apps/web/.env.local

# 写法二：只写文件名（gitignore 语法中不带斜杠会匹配任意层级）
.env.local
```

> 注意写法二的副作用：若项目里多处都有 `.env.local`（如 `apps/web/` 和 `apps/api/`），所有被忽略的 `.env.local` 都会各自复制到对应位置。需要精确控制时用写法一。

---

## 适用范围与例外（以 Claude Code 为例）

**生效场景：**

- 通过 `--worktree` / `-w` 创建的 worktree
- 子 agent（subagent）的 worktree
- 桌面应用中的并行会话

**例外（不生效）：**

如果配置了 `WorktreeCreate` / `WorktreeRemove` 钩子（用于 SVN、Perforce、Mercurial 等非 Git 系统），由于钩子会**替代**默认的 git 行为，此时 `.worktreeinclude` **不会被处理**。需要在钩子脚本里自行复制本地配置文件。

---

## 落地 Checklist

- [ ] `.worktreeinclude` 放在**项目根目录**
- [ ] 确认要复制的文件**确实在 `.gitignore` 中**（否则双重条件不满足，不会复制）
- [ ] 需要精确控制位置时，写**完整相对路径**而非裸文件名
- [ ] 把 `.worktreeinclude` 文件本身**提交到 Git**，让团队共享
- [ ] 若使用非 Git VCS 的 hook，记得在 hook 脚本里**手动处理**文件复制
