# pnpm + Turborepo 进阶学习计划(第 2 份)

> 来源:2026-06-20 pnpm+turbo 学习会话。第 1 份基础计划见 [[pnpm-turbo-learning-plan]](模块 1–6 已全部通关)。
> 定位:在"能自信日常使用"基础上,走向"能独立搭/维护生产级 monorepo"。同样以 turborepo_learning 仓库为练习场,你动手、我翻译。
> 状态:待开始(下次会话从这里接上)。

## Context

第 1 份计划解决了"组装机制"(workspace 软链、filter、任务编排、缓存、TUI、编译型内部包)。这份解决"工程化与规模化":开发体验(watch)、团队/CI 提速(remote cache、按影响范围构建)、版本发布(changesets)、配置复用、环境变量治理。每个模块仍是「学什么 → 动手 → 预期 → 啊哈点」。

## 进阶模块

### 进阶 1 · watch 开发流:告别手动 build
- 学什么:给库包加 `"dev": "tsc --watch --preserveWatchOutput"`,`turbo run dev` 一键起全部 watch(库 tsc -w + app vite/tsx watch),全在 TUI 里;以及 `cache:false` 为何对 watch 必要。
- 动手:给 `packages/shared`、`packages/ui` 加 dev 脚本 → `pnpm exec turbo run dev` → 改 shared 源码看 web 是否自动热更。
- 啊哈点:编译型内部包 + tsc --watch = 改 src 自动刷 dist 自动热更;链路全自动。

### 进阶 2 · workspace 协议全集 + 内部包的两种形态
- 学什么:`workspace:*` / `~` / `^` / 固定版本 / 别名 的发布期差异;**编译型(main→dist)vs JIT(main→src)**内部包的彻底取舍(构建边界 vs 免 build)。
- 动手:把 `packages/shared` 临时改成 JIT(`main→src/index.ts`),验证改 src 不 build 也能在 web 生效;再改回编译型。
- 啊哈点:`*/~/^` 只在发包时有意义;private 包用 `*` 即可。

### 进阶 3 · Remote Cache 远程缓存:全团队/CI 只构建一次
- 学什么:Turbo 把本地缓存(模块4 的哈希产物)上传到远端,同事和 CI 直接复用;Vercel Remote Cache vs 自建。
- 动手:`turbo login` / `turbo link`(或配置自建 endpoint),观察第二台"机器"(可模拟)直接 cache hit。
- 啊哈点:缓存键是内容哈希 → 跨机器可共享 → "全公司只构建一次"。

### 进阶 4 · 只构建受影响的包:CI 提速核心
- 学什么:`turbo run build --filter=[origin/main]`(只构建相对某 git 范围有改动的包及其下游);`turbo prune`(为 Docker 裁剪子集);把 turbo 接进 GitHub Actions。
- 动手:改一个包后用 `--filter=[HEAD^1]` 看只构建受影响子集;`turbo run build --dry=json` 预览将执行什么。
- 啊哈点:依赖图 + git diff = 精确的"爆炸半径",CI 只跑必要的活。

### 进阶 5 · changesets:内部包版本管理与发布
- 学什么:`@changesets/cli` 记录变更、生成 changelog、按依赖关系联动 bump 版本;monorepo 发包标准流程。
- 动手:`pnpm add -Dw @changesets/cli` → `changeset init` → `changeset` 记一次变更 → `changeset version` 看版本联动。
- 啊哈点:改了 shared,依赖它的 web/api 版本如何自动跟着 bump。

### 进阶 6 · 共享配置:tsconfig / eslint / prettier 提取成包
- 学什么:把 `tsconfig.base.json` 升级为 `@repo/tsconfig` 包用 `extends` 复用;共享 eslint/prettier 配置包;TS project references。
- 动手:新建 `packages/tsconfig`,让各包 `extends: "@repo/tsconfig/base.json"`。
- 啊哈点:配置也是"内部包",同样靠 workspace 复用。

### 进阶 7 · 环境变量治理
- 学什么:`globalEnv` vs 任务级 `env` vs `passThroughEnv` 的区别;为什么 env 会进缓存哈希;strict env mode 防"漏声明导致缓存错误命中"。
- 动手:给 build 任务加一个 env 变量,改它的值看缓存是否失效。
- 啊哈点:env 是缓存指纹的一部分,漏声明会导致"换了环境却命中旧缓存"的隐蔽 bug。

## 自测 / 出师标准
1. 不手动 build,改 shared 能让 web 自动热更。
2. 解释 remote cache 为什么能跨机器复用(缓存键是什么)。
3. 用 `--filter=[git范围]` 让 CI 只构建受影响的包。
4. 用 changesets 完成一次"改 shared → 联动 bump web/api 版本"。
5. 说清 `env`/`globalEnv`/`passThroughEnv` 与缓存命中的关系。

## 配套基础笔记
[[pnpm-turbo-learning-plan]] · [[pnpm-workspace-symlink-resolution]] · [[pnpm-filter-selection-syntax]] · [[turbo-dependson-build-order]] · [[turbo-cache-incremental-build]] · [[turbo-tui-dev-mode]] · [[compiled-internal-package-dist]] · [[monorepo-end-to-end-type-sharing]]
