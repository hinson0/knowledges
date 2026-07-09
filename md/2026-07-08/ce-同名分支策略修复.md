# CE 同名分支与 upstream 策略修复

> 日期:2026-07-08 · 项目:ce-workflow · 状态:实现完成,200/200 测试通过,可合并

## 一句话

把散落在多个 skill/脚本里的一条 Git 分支不变量,沉淀成一个共享 helper + CLI,经六轮评审打磨设计、codex 实现,最终 200/200 测试真跑绿。

## 背景 / 问题

`$ce-clone-repos` / `pnpm setup` 为 feature 准备同名分支 `feature/<slug>` 时,业务仓 `repos/*` 会 `git push -u origin HEAD:feature/<slug>` 绑定远端同名分支,但 harness 根仓 `ce-workflow` 只建了本地分支,没有远端分支、没有 upstream。`$ce-commit`/`$ce-pr`/`$ce-tmp-pr` 各自维护类似规则,散落易漂移。

## 核心不变量

任何进入提交 / 推送 / PR 的工作分支 `<branch>`,都必须对应远端同名分支 `origin/<branch>`,且 upstream 精确绑定到它。不同 skill 只决定自己是「检查 / 确保 / 推送」。

## 六个关键设计决策

1. **helper 暴露 CLI(去漂移的关键)** — `git-same-name-branch.mjs` 导出 `checkSameNameBranch` / `ensureSameNameUpstream` / `pushSameNameBranch`,并有 `check/ensure/push` CLI 薄包装(零逻辑重复)。markdown+bash 的 `$ce-commit`/`$ce-pr` 无法 import `.mjs`,必须 `if ! node "$CE_HARNESS_ROOT/scripts/harness/git-same-name-branch.mjs" check|push …; then … exit 1` shell-out,用退出码做门禁。
2. **`pnpm setup` 严格失败** — 无 origin / 离线 / 认证失败不静默降级;根仓先于业务仓处理,失败即止,不对业务仓产生副作用。
3. **`--no-track`(硬约束)** — tmp worktree `git worktree add --no-track …`。否则默认 `branch.autoSetupMerge=true` 会把 tmp 分支 upstream 预绑到 `origin/<target>`(不同名),撞 `pushSameNameBranch` 的 wrong-upstream 保护而阻断。
4. **`pnpm sb` 最小改动** — 只 prepend harness 根仓 + 把字符串启发式换成 helper 检查;发现逻辑不重写。原启发式盲点:分支绑到不同名远端且同步时误标 ✅,检测不到 wrong upstream。
5. **术语收紧** — source repo branch(`feature/foo`,基于 master)vs tmp integration branch(`dev_feature/foo` = `<target>_<sourceRepoBranch>`);MR 从 `dev_feature/foo` → `dev`。
6. **dry-run 双语义(最易实现错)** — direct(CLI/分支已就位)做严格只读校验 + `ls-remote` reachability,no-origin/wrong-upstream 立即抛错,不降级成 `planned`;编排层(`$ce-clone-repos`/`$ce-tmp-pr`)dry-run 不调 helper(前置未执行,校验真实 cwd 会假失败),自己打纯计划日志,但 `$ce-clone-repos` 仍做不依赖分支状态的 `git remote get-url origin` preflight。`pnpm setup` 无 dry-run。

## 实现要点(codex 落地,均已 grep + 测试核实)

- 孪生 targeted fetch:`setup_workspace.mjs` 与 `prepare_ce_clone_repos.mjs` 两入口都 `fetchRemoteBranchForTracking → if "exists" switch --track, else switch -c`,都不回退 stale tracking ref(无 `|| hasRemoteBranch`)。
- `sb` 容错:harness root seeded、per-repo try/catch(`check-failed`/`git-status-failed` 继续扫)、`return hadUnhealthy`,`harness.mjs` 据此 `process.exitCode = 1`。
- 错误不吞:git 失败经 `gitFailureDetail(result)` 抛错带 cwd/stderr;`currentBranch` 区分 detached 与真失败;`upstreamBranch` 不把未知失败当「无 upstream」。
- codex 比 plan 更严两处:① 用独立 `CE_HARNESS_ROOT`(定位 helper)+ 向上查找,修正 plan 隐患(ce-pr 里 `CE_WORKSPACE_ROOT` 是「仓库扫描根」可能指向业务仓,拼 helper 路径会失效);② 加 `verifyLocalSameNameBranchBeforeSwitch` diverged 保护。

## 流程

设计评审 → 拍板 → 写进 spec+plan → codex 5 轮 review(逐条验证+修复,问题从架构级 → 契约边界 → 二阶效应 → 孪生遗漏 → 测试盲区逐轮收敛)→ codex 实现(自跑 3 轮 review)→ fork 独立验收。

## 验收

- `pnpm test`:**200 / 200 通过,0 失败**。
- 全部不变量逐条 grep + 测试核实守住。
- 「测试被改宽以求绿」未发生:守不变量的测试反而是加强的。

## 两个教训

1. **纸面推不出运行时真相** — 多次「残留为 0」被后续 review 证伪;真正的验收是 200/200,不是「应该对」。
2. **多方独立 review 各补盲区** — codex 修掉我漏的 bash 路径隐患;dry-run 双语义冲突是我上一轮修复引入的二阶 bug,由下一轮 review 抓出。

## 关联文件

- spec: `docs/superpowers/specs/2026-07-07-ce-workflow-upstream-design.md`
- plan: `docs/superpowers/plans/2026-07-08-same-name-branch-policy.md`
- helper: `scripts/harness/git-same-name-branch.mjs`
