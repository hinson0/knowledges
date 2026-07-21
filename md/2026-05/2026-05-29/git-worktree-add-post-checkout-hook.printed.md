# 用 post-checkout hook 在 git worktree add 时自动携带本地配置

## Trigger Question

> 请手动引导我 如何创建一个 git hook 当用户执行 git worktree add 时 我还是想用钩子 不想用 xxx.sh 脚本

> 我已经在项目里面把所有的关于 graphify 功能全部删掉了,现在你只要引导我如何去创建这个 git worktree 的 hook 就可以了

## Key Takeaways

- `git worktree add` 在建好目录后会做一次**初始 checkout**,会触发 `post-checkout` hook —— 这就是"手敲 `git worktree add` 也能自动携带文件"的挂载点。
- **区分"新建 worktree" vs "普通切分支"**:`post-checkout` 收到三个参数 `$1`=切换前 OID、`$2`=切换后 OID、`$3`=分支标志(1=切分支,0=切文件)。新建 worktree 的初始 checkout 签名是 **`$1` 全零 OID 且 `$3=1`**;进入 worktree 后普通 `git checkout` 时 `$1` 是真实 OID。靠这点保证只在新建时携带一次,不覆盖你后来改过的 `.env.local`。
- **拷贝源是主工作目录**,用 `dirname $(git rev-parse --path-format=absolute --git-common-dir)` 定位(详见 [[git-worktree-internals]])。
- **选取要携带的文件复用 git 语义**:`git ls-files -o -i -X <清单>` = 未跟踪(`-o`)+ 被忽略(`-i`)+ 匹配清单模式(`-X`),正好筛出"被 gitignore 且在清单里"的文件;`cp -p` 按相对路径镜像,子目录归子目录。
- hook 不随仓库走:把脚本提交进版本管理的 `.githooks/`,再各自 `cp` 到 `.git/hooks/` 激活(每个 clone 一次,全 worktree 共享)。

## Code Example

`.githooks/post-checkout`(POSIX sh,独立完整 hook):

```sh
#!/bin/sh
# 新建 worktree 时,按 .worktreeinclude 把主工作目录的本地配置携带过来。
prev="$1"; flag="$3"
[ "$flag" = "1" ] || exit 0
case "$prev" in "" | *[!0]*) exit 0 ;; esac   # prev 非全零 → 非新建 → 退出

common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
src="$(dirname "$common")"                                       # 主工作目录(拷贝源)
dest="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0    # 新 worktree(目标)
[ -n "$dest" ] && [ "$src" != "$dest" ] || exit 0
[ -f "$src/.worktreeinclude" ] || exit 0

git -C "$src" ls-files -o -i -X "$src/.worktreeinclude" | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$src/$rel" ] || continue
  mkdir -p "$dest/$(dirname "$rel")"
  cp -p "$src/$rel" "$dest/$rel" && echo "[worktree-include] 携带 $rel"
done
exit 0
```

安装与测试:

```sh
# 安装(每个 clone 一次;在 worktree 内也能正确指到主仓 hooks)
cp .githooks/post-checkout "$(git rev-parse --git-common-dir)/hooks/post-checkout"
chmod +x "$(git rev-parse --git-common-dir)/hooks/post-checkout"
sh -n .githooks/post-checkout && echo "语法 OK"

# 测试:建临时 worktree,期望打印 [worktree-include] 携带 apps/web/.env.local
git worktree add .claude/worktrees/hooktest -b test/hook
diff apps/web/.env.local .claude/worktrees/hooktest/apps/web/.env.local && echo OK
git worktree remove --force .claude/worktrees/hooktest && git branch -D test/hook
```

`.worktreeinclude`(仓库根,语法同 .gitignore;同一份清单 EnterWorktree 与 hook 共用):

```gitignore
.env
.env.local
.env.*.local
```

## Pitfall / Why

- **为什么用"全零 OID"判新建**:`git worktree add` 的工作树此前不存在,初始 checkout 的"切换前"就是全零。若不加这个判断,hook 会在每次切分支时都重拷,**覆盖你在 worktree 里改过的 `.env.local`**。
- **必须用 `--git-common-dir` 而非 `--git-dir`**:worktree 内 `--git-dir` 指向 `.git/worktrees/<name>`(私有),其父目录不是主工作目录;只有 `--git-common-dir` 才指向主 `.git`。
- **E2E 实测覆盖四场景**:① 新建携带逐字节一致 ② worktree 内改后切分支不覆盖 ③ worktree 路径含空格仍正确 ④ 仓库无 `.worktreeinclude` 时静默 `exit 0` 不报错。
- 历史背景:本仓库曾用包装脚本 `scripts/git-wt.sh` 实现同一目的,但需记得改用包装命令;改用 hook 后原生 `git worktree add` 即生效,故删除该脚本。早期还担心与 graphify 的 `post-checkout` 共存(需前置注入),graphify 移除后 hook 可独立完整使用。

## Related

- [[git-worktree-internals]]
