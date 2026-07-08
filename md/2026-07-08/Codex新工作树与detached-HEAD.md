# Codex 新工作树与 detached HEAD

## 一句话结论

在 Codex composer 里选择 `新工作树` + 某个分支时，新 worktree 通常是从这个分支当时的 `HEAD commit` 创建出来的。它的起点来自该分支，但默认处于 `detached HEAD`，也就是直接停在某个 commit 上，而不是 checkout 在这个分支名上。

## 基本模型

假设 `feature/operation-log` 当前最新提交是 `aaa`：

```text
feature/operation-log -> aaa
```

此时在 Codex 里选择：

```text
新工作树 + feature/operation-log
```

得到的新 worktree 可以理解成：

```text
HEAD -> aaa
feature/operation-log -> aaa
```

注意这里不是：

```text
HEAD -> feature/operation-log
```

所以它是 `detached HEAD`：`HEAD` 直接指向 commit `aaa`，而不是通过分支名间接指向 commit。

## 为什么 prompt 会显示 commit hash

如果 shell prompt 显示类似：

```text
on git:76094fd
```

而不是：

```text
on git:feature/operation-log
```

这通常说明当前 checkout 不是某个分支，而是直接停在 commit `76094fd` 上，也就是 detached 状态。

可以用这些命令确认：

```bash
git status -sb
git branch --show-current
git rev-parse --abbrev-ref HEAD
```

典型 detached 输出：

```text
## HEAD (no branch)
```

或者：

```text
HEAD
```

如果 `git branch --show-current` 没有输出，也通常表示当前没有 checkout 在任何分支上。

## 未提交改动属于 worktree，不属于 branch

这是最容易混淆的点。

分支只指向 commit。比如：

```text
feature/operation-log -> 76094fd
```

如果某个 worktree checkout 在 `feature/operation-log` 上，并且 `.gitignore` 有未提交改动，这个改动并不属于 `feature/operation-log` 这个分支对象。它只是存在于那个具体 worktree 的工作区里。

例如：

```text
/Users/a114514/.codex/worktrees/f514/ce-workflow
  branch: feature/operation-log
  modified: .gitignore

/Users/a114514/.codex/worktrees/5dab/ce-workflow
  detached HEAD at 76094fd
  working tree clean
```

这表示 `f514` 里的 `.gitignore` 未提交改动没有进入 `5dab`。即使两个 worktree 起点 commit 一样，未提交改动也不会因为“同一个分支名”自动复制过去。

检查另一个 worktree 的未提交改动：

```bash
git -C /Users/a114514/.codex/worktrees/f514/ce-workflow status -sb
git -C /Users/a114514/.codex/worktrees/f514/ce-workflow diff --stat
git -C /Users/a114514/.codex/worktrees/f514/ce-workflow diff
```

检查当前 session 有没有带到改动：

```bash
git status -sb
git diff --stat
git diff --name-status
```

如果当前 session 是 clean，就说明这些未提交改动没有在当前 worktree 里。

## 从 detached HEAD 创建分支

可以直接在当前 detached worktree 上创建分支：

```bash
git switch -c codex/operation-log-fix
```

创建前：

```text
feature/operation-log -> 76094fd
HEAD -> 76094fd
```

创建后：

```text
feature/operation-log -> 76094fd
codex/operation-log-fix -> 76094fd
HEAD -> codex/operation-log-fix
```

此时新分支和原来的 `feature/operation-log` 共享历史起点，但已经是两个独立的分支引用：

- `feature/operation-log` 后续提交，新分支不会自动跟随。
- 新分支后续提交，`feature/operation-log` 不会自动变化。
- 两者后续可以 merge、rebase 或 cherry-pick，但不会自动同步。

也可以在 Codex App 的 thread 顶部使用 `Create branch here`，本质也是把当前 detached worktree 挂到一个真实分支名上。

## 正确心智模型

```text
branch = 指向某个 commit 的可移动标签
worktree = 某个 checkout 目录
detached HEAD = 当前 checkout 直接指向 commit，而不是指向 branch
未提交改动 = 某个 worktree 工作区里的本地状态，不属于 branch
```

因此，Codex 新工作树的准确理解是：

> 从所选分支当时的 commit 创建一个独立 checkout。它起点来自这个分支，但默认不占用这个分支名；另一个 worktree 里的未提交改动不会因为选择了同一个分支名就自动带过来。
