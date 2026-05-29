# git worktree 内部机制(.git 文件、hooks 归属、定位主目录)

## Trigger Question

> 另外你老提到 .git/hooks 这个是在 main 上才存在的 在 worktree 是没有的是吗

> 所有的操作都在 worktree 不要在 main(引出"hook 到底属于谁"的澄清)

## Key Takeaways

- **worktree 里的 `.git` 是一个文件,不是目录**。内容只有一行 `gitdir: /…/主仓/.git/worktrees/<name>`,指回主仓库。所以 worktree **没有自己的 `.git/hooks/`**。
- **git hooks 属于"仓库",不属于分支、也不属于某个 worktree**。所有 worktree 通过 `--git-common-dir` 共享主仓库那一份 `.git/hooks/`。推论:hook 在主仓装一次,全部 worktree 自动共享;但 hook 不进版本控制,换机器 / 重新 clone 要重装。
- **从 worktree 内定位"主工作目录"**:用 `--git-common-dir`(指向主 `.git`),不要用 `--git-dir`(指向 `.git/worktrees/<name>`,是该 worktree 私有的)。主工作目录 = `dirname(主 .git)`。
- **`git worktree list --porcelain` 的顺序是目录读取序(近似字母序),不是创建顺序**。所以"取最后一个 = 最新建的"是错的;要定位"刚新建的 worktree"应取 add 前后的**集合差**。
- 一个分支已被某个 worktree 占用时,别的地方 `git checkout` / `git worktree add` 同名分支会 `fatal: '<branch>' is already used by worktree at …`。

## Schema / Field Table

worktree 内 `git rev-parse` 各项的指向(实测):

| 命令 | 指向 | 用途 |
| --- | --- | --- |
| `git rev-parse --absolute-git-dir` | `主仓/.git/worktrees/<name>` | 该 worktree **私有**的 git 目录 |
| `git rev-parse --path-format=absolute --git-common-dir` | `主仓/.git` | **全仓共享**的主 .git;其父目录即主工作目录 |
| `git rev-parse --git-path hooks` | `主仓/.git/hooks` | hooks 实际解析位置(worktree 内也指主仓) |
| `git rev-parse --show-toplevel` | 当前 worktree 根 | 当前工作树根目录 |

## Code Example

```sh
# 在任意 worktree 内,稳健地拿到"主工作目录"和"当前 worktree 根"
common="$(git rev-parse --path-format=absolute --git-common-dir)"  # → 主仓/.git
main_root="$(dirname "$common")"                                   # → 主工作目录
here="$(git rev-parse --show-toplevel)"                            # → 当前 worktree

# 把 hook 安装到"全仓共享"的 hooks 目录(在 worktree 内也能正确指到主仓)
cp .githooks/post-checkout "$(git rev-parse --git-common-dir)/hooks/post-checkout"
chmod +x "$(git rev-parse --git-common-dir)/hooks/post-checkout"
```

```sh
# 定位"刚新建的 worktree":用集合差,而非"取最后一个"
wt_list() { git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print}'; }
before="$(wt_list)"
git worktree add "$@"
after="$(wt_list)"
new_wt="$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort))"
```

```sh
# 清理 worktree 与分支
git worktree remove --force <path>   # 移除 worktree(有未跟踪/改动时需 --force)
git worktree prune                   # 清理失效登记
git branch -D <branch>               # 删除对应分支
```

## Pitfall / Why

- **误区:"hooks 只在 main 分支才有"**。准确说法是 hooks 属于**仓库**,不绑定分支或 worktree。worktree 的 `.git` 只是个指回主仓的文件,自然没有独立 hooks;大家共享主仓 `.git/hooks/`。
- **`awk '$2'` 取 worktree 路径会在第一个空格处截断**:`worktree list --porcelain` 行格式是 `worktree <path>`,若 path 含空格,`$2` 只拿到第一段。应 `sub(/^worktree /,"")` 取整行剩余部分。
- **"取 `worktree list` 最后一个当作新建的那个"是 bug**:顺序是目录读取序,不是创建序。反例:先建 `zzz` 再建 `aaa`,最后一个会是 `zzz`(字母序),导致定位到错误的 worktree。用 add 前后集合差才正确,且天然兼容空格路径。

## Related

- [[git-worktree-add-post-checkout-hook]]
