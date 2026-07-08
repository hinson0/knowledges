这个命令是用来检查：

```bash
feature/config-ssot
```

这个本地分支上，有没有 `master` 没有的提交。

```bash
git log --oneline master..feature/config-ssot
```

可以理解成：

```text
列出：在 feature/config-ssot 上，但不在 master 上的 commit
```

结果判断：

如果有输出，比如：

```text
abc1234 修改了某某
def5678 新增了某某
```

说明 `feature/config-ssot` 有自己的提交。你如果直接删这个分支，可能会丢掉这些提交。

如果没有任何输出，说明 `feature/config-ssot` 相比 `master` 没有独有提交，删掉它风险小很多。

你这里是想判断“能不能安全删本地 feature 分支”，所以才用这个命令。正常重新跑 `$ce-clone-repos` 不需要删分支。

---

## 清除本地可以清除的worktree(分支被删除了,但worktree还在本地留存的这种)

- `git worktree list` 先看本地是否有prunable的状态的worktree
- `git worktree prune` 清除

## git中强制回到某个远端分支的代码

- `git reset --hard origin/master` 把本地所有的变更丢弃 同步远端origin/master的内容

## git中强制删除最近一个commit的代码

- `git reset --hard HEAD~1`
