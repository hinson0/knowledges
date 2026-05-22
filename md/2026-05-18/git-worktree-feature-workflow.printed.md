# git worktree · feature 隔离开发 + merge --no-ff + 冲突解决

> 来源:week3/day3_workspace · EnterWorktree / ExitWorktree / merge 全流程
> 落盘日期:2026-05-18

## 触发提问

- `This background session hasn't isolated its changes yet. Call EnterWorktree first` 这个错怎么解决?
- worktree merge 时撞 conflict 怎么办?
- merge 用 `--no-ff` 还是默认 fast-forward?
- worktree 退出后分支要不要保留?

## 关键结论

- **git worktree** = 同一 repo 多个工作目录(共享 .git),适合"feature 隔离 + 不打断主 checkout"
- **EnterWorktree** 自动从 `origin/<default-branch>` 或 HEAD 起新分支,**不带主 checkout 的未提交改动**
- **ExitWorktree --action keep** = 退出但保留分支(buy insurance,可回滚窗口)
- **merge --no-ff** = 强制产生 merge commit,**保留 feature 边界**(`git log --graph` 能看到 feature 边界)
- 冲突解决:**`git checkout --ours / --theirs` 二选一**(`--ours` = 当前分支即 main,`--theirs` = 被合入分支)
- `.gitignore` 取舍:runtime artifact(含绝对路径)默认排除,**学习项目可保留**(主动覆盖默认)

## Schema · git worktree 跟 branch 的关系

```text
.git/                                    ← 物理 repo,所有 worktree 共享
├── refs/heads/
│   ├── main
│   └── worktree-day3-dependency-graph   ← worktree 分支,跟普通 branch 同等
└── worktrees/
    └── day3-dependency-graph/
        ├── HEAD
        └── ...

主 checkout                              ← 默认工作目录(week3/main 分支)
.claude/worktrees/day3-dependency-graph/ ← worktree 工作目录(独立 checkout)
```

**两个目录共享 .git 元数据**,但**工作树是完全独立的两份文件**。

## 工作流 · 完整 feature 开发流程

### Step 1 — 进 worktree(开始 feature)

```python
EnterWorktree(name="day3-dependency-graph")
# 自动:
#   git worktree add .claude/worktrees/day3-dependency-graph \
#       --no-track -b worktree-day3-dependency-graph origin/main
# 然后:cd .claude/worktrees/day3-dependency-graph
```

**重要细节**:`EnterWorktree` 默认从 `origin/<default-branch>`(fresh ref)起,**主 checkout 的未提交改动不会跟过来**。如果想从当前 HEAD 起,改 `worktree.baseRef` 配置为 `head`。

### Step 2 — 在 worktree 里完整开发

```bash
cd .claude/worktrees/day3-dependency-graph
# 写代码、跑测试、commit
git add ...
git commit -m "feat: ..."
```

### Step 3 — 退出 worktree(保留分支)

```python
ExitWorktree(action="keep")
# 自动:
#   cd 回主 checkout(/Users/.../ai_agent_learning)
#   worktree 目录 + 分支留在原地
```

**为什么 `action="keep"`**:**万一 merge 后发现 main 上代码有问题,可以 `git checkout worktree-day3-dependency-graph` 立刻回到那个干净状态**。一周后再 `git branch -d` 清理也不迟。

`action="remove"`:删 worktree + branch。**适合"work in progress 但要废弃"** 的 case。

### Step 4 — 切回 main,merge

```bash
# 已自动 cd 回主 checkout
git branch --show-current     # → main

git merge worktree-day3-dependency-graph --no-ff -m "Merge feat: ..."
```

### Step 5 — 处理 conflict(如果有)

```bash
# 撞 conflict 时:
git status   # 看哪些文件冲突
git checkout --ours <file>    # 保留 main 版本
# 或
git checkout --theirs <file>  # 保留 worktree 版本
# 或手动编辑

git add <file>
git commit --no-edit          # 完成 merge commit
```

## 代码示例 · 完整流程(本次 day3 实际跑的)

```bash
# Step 1:进 worktree
# (Claude 自动调 EnterWorktree)

# Step 2:在 worktree 里建 infra + day3 + 跑真实压测
mkdir -p week3/infra week3/day3_workspace
# ... 写代码 ...
git add week3/infra/ week3/day3_workspace/
git commit -m "feat(week3/day3): codebase 依赖图建模 + 循环检测 + infra 抽取"

# Step 3:加 runtime artifact 入库(本来 .gitignore 排除的)
# 用户决定:学习资产保留
sed -i '' '/week3.*\.json/d' .gitignore   # 移除 ignore 规则
git add .gitignore week3/day3_workspace/index.json week3/day3_workspace/dependency_graph.json
git commit -m "chore: 保留 index.json + dependency_graph.json 作为学习资产"

# Step 4:退出 worktree
# (Claude 自动调 ExitWorktree --action keep)

# Step 5:merge
git merge worktree-day3-dependency-graph --no-ff -m "Merge day3 into main"
# ⚠ 撞 conflict on week3/infra/parser.py(主 checkout 有更详细 docstring 版本)
git checkout --ours week3/infra/parser.py
git add week3/infra/parser.py
git commit --no-edit

# Step 6:验证
git log --oneline -3
# 0af6d94 Merge branch 'worktree-day3-dependency-graph' into main
# 0084b5a chore: 保留 index.json + dependency_graph.json
# 1ae47f3 feat: day3 依赖图 + infra 抽取
```

## 字段表 · `--ours` vs `--theirs` 含义

| 选项 | 保留谁 | 何时用 |
|---|---|---|
| `--ours` | **当前所在分支**(merge 时是 main) | 主分支版本更对 / 更详细 / 更近期 |
| `--theirs` | **被合入分支**(merge 时是 feature) | feature 分支是最新工作版 |

**记忆**:`ours` = "我们家的"(当前分支),`theirs` = "他们的"(外来的 feature)。

## 字段表 · merge 几种姿势

| 姿势 | 命令 | 何时用 |
|---|---|---|
| **fast-forward**(默认) | `git merge feature` | feature 是 main 的直接后继时,把 main 指针往前挪 = 摊平历史 |
| **no fast-forward**(推荐) | `git merge --no-ff feature` | 强制产生 merge commit,**保留 feature 边界** |
| **squash** | `git merge --squash feature; git commit` | 把 feature 所有 commits 压成一个,主线更干净但失去 commit 粒度 |
| **rebase + merge** | `git rebase main; git merge feature` | feature 不基于最新 main 时,先 rebase 让历史线性 |

**day3 选 `--no-ff`**:`git log --graph` 看就能看出"这一坨 commits 属于 day3 feature",**多 feature 并行时这条习惯救命**(可以方便地"reset 掉整个 day3 feature")。

## 坑 / Why

### worktree 的 fresh ref 不带主 checkout 改动

**Why**:`EnterWorktree` 默认从 `origin/main` 起(`worktree.baseRef = "fresh"`),**主 checkout 的未提交改动不会跟过来**。这次 day3 撞到这个 case —— 我在主 checkout 写好的 `infra/parser.py` 进 worktree 后不见了,只好重写一遍。

**How to apply**:
- 进 worktree 前,**先把主 checkout 的有用改动 commit / stash**
- 或改配置 `worktree.baseRef = "head"`,让 worktree 从当前 HEAD 起
- 或干脆**不开 worktree,直接在主分支开 feature branch**(传统 git flow,适合不需要并行多个 feature 时)

### `--no-ff` 制造的 merge commit 是 "feature 边界标记"

**Why**:`--ff`(fast-forward)会把 commits 摊平在 main 上,**未来看 git log 完全看不出"哪些 commits 属于哪个 feature"**;`--no-ff` 强制产生一个 merge commit。

**How to apply**:
- `git log --graph --oneline` 看就能看出 feature 边界
- production 团队的 release flow 都用 `--no-ff`
- 唯一不用 `--no-ff` 的场景:hotfix 单 commit 直接 merge 进 main(简洁优先)

### `ExitWorktree --action keep` 是 "buy insurance"

**Why**:保留 worktree branch = 保留 feature 完整快照的可回滚窗口。万一 main 上 merge 后发现 bug,可以立刻 `git checkout worktree-xxx` 回到干净状态。

**How to apply**:
- 默认 `--action keep`
- 一周后(或下个 release 后)再 `git branch -d worktree-xxx` 清理
- `--action remove` 只用于"work in progress 但要废弃"的 case

### `git checkout --ours/--theirs` 不要盲选

**Why**:**永远要 `git diff` 看一眼再决定**。这次 day3 撞 parser.py 冲突,我选 `--ours`(main 详细 docstring 版),是因为我**先 diff 对比过两个版本**确认 main 版更完整。LLM/agent 可能在某边写了更好的 docstring,**不能盲信哪边新就用哪边**。

**How to apply**:
- 撞冲突先 `git diff :1:<file> :2:<file>`(base vs HEAD)+ `git diff :1:<file> :3:<file>`(base vs theirs)对比
- 简单场景(纯文本差异)用 `--ours/--theirs` 二选一
- 复杂场景(逻辑差异)手动编辑文件,vim conflict markers,确认无冲突再 `git add`

### `.gitignore` 取舍:runtime artifact 默认排除,学习项目可保留

**Why**:`index.json` / `dependency_graph.json` 含绝对路径 `/Users/a114514/...`,**跨机器消费者拿到也用不了**。production 项目默认应该排除。

**How to apply**:
- production 项目:**默认 `.gitignore` 排除所有运行时产物**(index.json / .cache / .tmp / *.log)
- 学习项目 / demo 项目:**主动覆盖 .gitignore 决策**保留作为学习资产
- 用 commit message 解释"为什么破例" —— 给未来的自己/同事讲清楚

## 关联

- `~/knowledges/md/2026-05-13/codebase-indexer-design-patterns.md` — `.as_posix()` + 跨机器可移植设计(为什么 absolute path 不该入库)
- `week3/day3_workspace/` — 本次 worktree 产物
- `.gitignore` — 本次 worktree 流程修改了的文件
