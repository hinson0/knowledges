# pnpm + Turborepo 学习计划(已完成)

> 来源:2026-06-20 pnpm+turbo 学习会话的学习计划。原始计划文件:~/.claude/plans/fluttering-stirring-cerf.md
> 完成状态:模块 1–6 全部通关(模块 5 dev/TUI 已提前体验)。各模块详细知识已分别归档为同目录下的独立文件,见文末「配套知识文件」。

---

## Context(为什么是这份计划)

你想系统学会 **pnpm workspace + Turborepo** 这一套 monorepo 工具链。校准后的目标:

- **深度**:能自信地日常使用 —— 看懂日志、会用 `--filter`、理解缓存、能自己加包/加依赖、能排掉常见报错。底层原理(符号链接细节、哈希算法)只做"指路",不深挖。
- **范围**:核心是 pnpm + turbo 的"组装机制";**顺带**讲清楚你项目里 `web`(vite+react)和 `api`(hono+drizzle)是怎么接进 monorepo 的。

学习方式遵循你的偏好:**你在终端动手敲,我当向导 + 逐行翻译日志**。整份计划全部基于你这个真实仓库,不引入玩具例子。你已经完成的前置:三个 `demo-a/b/c` 服务已建好、Turbo TUI 已能正常显示。

仓库现状速记:
- 5+3 个工作区包:`packages/shared`(纯 TS:types+utils)、`packages/ui`(React:Button/Card)、`apps/web`(vite+react)、`apps/api`(hono+drizzle+sqlite)、`apps/android|ios`(占位)、`apps/demo-a|b|c`(你刚建的 TUI 演示)
- 依赖图:`shared ← ui ← web`、`shared ← api`
- `turbo.json`:`build`(`dependsOn: ^build`, `outputs: dist/**`)、`dev`(`persistent`, `cache:false`)、`lint`
- 内部包 `shared`/`ui` 的 `main` 指向 `dist/`(**编译型内部包**,改源码需重新 build 才生效)

---

## 心智模型(一句话锚点,贯穿全程)

> **pnpm 管"空间"(谁连到谁),Turbo 管"时间"(谁先谁后、谁能跳过)。**

| | pnpm | Turborepo |
|---|---|---|
| 关键词 | `workspace:*`、符号链接、`--filter` | `dependsOn`、`outputs`、缓存、`--filter` |
| 你仓库里的体现 | `pnpm-workspace.yaml` + 各 `package.json` 的 `"@repo/x": "workspace:*"` | `turbo.json` 的 `tasks` |

---

## 模块化课程(6 个模块,循序渐进)

每个模块统一结构:**学什么 → 动手命令 → 预期观察 → 啊哈点**。命令都在仓库根目录 `/Users/a114514/turborepo_learning` 执行;你敲,我翻译。

### 模块 1 · pnpm workspace:看见"连接"
- **学什么**:`pnpm-workspace.yaml` 如何用 `apps/*`、`packages/*` 通配符发现包;`workspace:*` 协议;`pnpm install` 干了什么;`node_modules/@repo/` 里的符号链接。
- **动手**:
  1. `pnpm install`
  2. `ls -la node_modules/@repo/`(看到指向 `../../packages/...` 的符号链接)
  3. `pnpm -F @repo/web why @repo/ui`(看 web 为什么有 ui)
- **预期观察**:`@repo/shared`、`@repo/ui` 等是软链而非真实复制目录。
- **啊哈点**:`@repo/x` 不是从 npm 下载的,是 pnpm 把本地目录"挂"进了 node_modules —— 这就是 monorepo 能跨包直接 import 的根本原因。

### 模块 2 · pnpm 的过滤与加包/加依赖(日常高频操作)
- **学什么**:`pnpm --filter <pkg> <cmd>` 选包执行;给某个包加依赖;新建一个 workspace 包的标准流程(呼应你刚踩的"包名冲突"坑)。
- **动手**:
  1. `pnpm -F @repo/web add zod`(给单个 app 加依赖,观察只有 web 的 package.json 变)
  2. `pnpm -F @repo/api exec tsx --version`(在指定包里跑命令)
  3. 复盘:新建包时 `package.json` 的 `name` 是"主键",目录名只是给人看的 —— 重名会导致 workspace 解析直接失败。
- **啊哈点**:`name` 字段决定一切寻址(import / filter / workspace:*),目录名无关紧要。

### 模块 3 · Turbo 任务编排:看见"顺序"
- **学什么**:`turbo run <task>`;`dependsOn: ["^build"]` 里 `^` 的含义(先构建上游依赖);任务图如何从依赖图自动推导;`包名#任务名` 这个任务 ID。
- **动手**:
  1. `pnpm exec turbo run build`(观察 `shared`/`ui` 永远排在 `web`/`api` 前)
  2. `pnpm exec turbo run build --graph`(可选,看任务依赖图)
  3. `pnpm exec turbo run build --filter=@repo/web`(只构建 web 及其上游)
- **啊哈点**:你从没手写过构建顺序,顺序是 Turbo 读依赖图 + `^` 语义推出来的。`^build` = "先 build 我依赖的包",去掉 `^` = "先 build 我自己的其他任务"。

### 模块 4 · Turbo 缓存:看见"跳过"(Turbo 最大价值)
- **学什么**:`outputs: ["dist/**"]` 告诉 Turbo 缓存什么;`FULL TURBO`;改一个包后的增量重建;为什么 `dev` 设 `cache:false`。
- **动手**:
  1. `pnpm exec turbo run build`,紧接着**再跑一次** → 看 `>>> FULL TURBO`(毫秒级)
  2. 改一行 `packages/shared/src/utils.ts`,再 build → 只有 `shared` 及下游重建,`ui` 不动
  3. `pnpm exec turbo run build --force`(强制忽略缓存,对比耗时)
- **啊哈点**:缓存键由"源码 + 依赖 + 任务配置"哈希得出;没变就直接回放上次输出。这是 monorepo 在大规模下仍然快的核心。

### 模块 5 · dev 与 TUI:看见"多服务并行"(你已体验,这里巩固 + 串原理)
- **学什么**:`persistent: true` 为何触发 TUI;`--ui=tui|stream`;TUI 左右分栏 = 多个长驻任务各自独立的输出流;TUI 操作键。
- **动手**:
  1. `pnpm exec turbo run dev --filter='@repo/demo-*'`(回到你建的三个 demo)
  2. 对比 `--ui=stream`,体会 TUI 解决的"多服务日志混在一起"痛点
  3. TUI 里用 `↑/↓`、`/` 搜索、`Ctrl-C` 退出;浏览器开 4001/4002/4003
- **啊哈点**:左边列的是"正在运行的任务"不是文件;右边是选中任务的实时 stdout。这正是你最初截图里"左选服务、右看视窗"的来源。

### 模块 6 · 应用层如何融入 monorepo(顺带,串起全局)
- **学什么**:
  - `web`:`apps/web/src/App.tsx` 直接 `import { Button, Card } from "@repo/ui"` 和 `@repo/shared` 的类型 —— 应用消费内部包。
  - `api`:`apps/api` 用 hono 起服务、drizzle+sqlite 存数据,共享 `@repo/shared` 的类型,实现"前后端类型一致"。
  - **编译型内部包的取舍**:`shared`/`ui` 的 `main` 指向 `dist/`,所以改了源码不 build,web 看到的是旧产物 —— 这正是 `dev`/`lint` 也挂 `dependsOn:["^build"]` 的原因。
  - 环境变量:`turbo.json` 的 `globalEnv`(PORT/DATABASE_URL/CORS_ORIGIN)与 `build` 任务的 `env: ["NODE_ENV"]` 的区别。
- **动手**:
  1. 读 `apps/web/src/App.tsx` 第 1–2 行,对照模块 1 的符号链接,理解 import 是怎么解析到的
  2. 改 `packages/shared` 一个导出值但**不 build**,启动 web 看是否拿到旧值 → 亲历"编译型内部包"的取舍
  3. `pnpm exec turbo run dev --filter=@repo/api`,用浏览器/curl 打 api 路由
- **啊哈点**:monorepo 拆包的目的是"复用 + 类型贯通";代价是"内部包改动需要重建链路",Turbo 的依赖图 + 缓存正是用来把这个代价降到最低。

---

## 日常工作流速查(学完即用)

| 想做的事 | 命令 |
|---|---|
| 装/同步所有依赖 | `pnpm install` |
| 给某个包加依赖 | `pnpm -F @repo/web add <pkg>` |
| 只构建某个包及其上游 | `pnpm exec turbo run build --filter=@repo/web` |
| 构建全部(带缓存) | `pnpm exec turbo run build` |
| 只起某些 dev 服务 | `pnpm exec turbo run dev --filter='@repo/demo-*'` |
| 忽略缓存强制重跑 | `pnpm exec turbo run build --force` |
| 切换 TUI/滚动日志 | 命令尾加 `--ui=tui` 或 `--ui=stream` |

## 常见报错速查(含你已踩过的)
- **`Failed to add workspace … it already exists`** → 两个包 `name` 重复(目录名无所谓,改 `package.json` 的 `name`)。
- **改了内部包但 app 没生效** → 编译型内部包,需重新 `turbo run build`(或起 watch)。
- **`--filter='@repo/*'` 没生效/被 shell 展开** → 通配符要加引号。
- **看不到 TUI** → 非交互式终端(管道/CI/无 TTY)会退化成 stream;在真实终端跑,或显式 `--ui=tui`。
- **`Unknown option: 'recursive'`** → `--filter` 后面没跟动作(光选包不干活),或 `dependsOn` 写成自环;补上 build/add/exec 等动作。

---

## 验证 / 自测(怎么算"学会了")

按模块设的小检查点,你能独立做到即视为掌握:
1. 用一句话解释 pnpm 和 Turbo 各负责什么,并能在仓库里各指出一个证据文件。
2. 不看笔记,说出 `dependsOn:["^build"]` 里 `^` 的含义,并预测 `turbo run build` 的执行顺序。
3. 制造一次 `FULL TURBO`,再制造一次"只有部分包重建",并解释为什么。
4. 独立新建第 4 个 demo 包(`demo-d`/端口 4004)并让它出现在 TUI 里 —— 不出现就能自己定位原因。
5. 解释 `apps/web/src/App.tsx` 的 `@repo/ui` import 是怎么一步步解析到 `packages/ui/dist` 的。

## 执行节奏建议
- 一次一个模块,你敲命令、贴输出,我逐行翻译并补原理;每模块结束做对应自测点。
- 模块 1→6 顺序进行(1–2 是 pnpm,3–5 是 turbo,6 收口到应用层),预计每模块 10–20 分钟。
- 全程不替你落盘代码;需要你改文件时,我给代码 + 步骤,你来动手。

---

## 配套知识文件(本会话同目录已归档的详细笔记)

- [[pnpm-workspace-symlink-resolution]] — 模块1 workspace 软链与"谁声明谁才有"
- [[pnpm-filter-selection-syntax]] — 模块2 `--filter` 选包语法(`...` 上下游)
- [[pnpm-add-workspace-vs-version]] — 模块2 `add` 加依赖、`workspace:*` vs `^版本`
- [[turbo-dependson-build-order]] — 模块3 任务编排 `^build` 与构建顺序
- [[turbo-cache-incremental-build]] — 模块4 缓存指纹与增量构建
- [[turbo_persistent]] — 模块5 dev/TUI(或 [[turbo-tui-dev-mode]])
- [[compiled-internal-package-dist]] — 模块6 编译型内部包(src vs dist)
- [[monorepo-end-to-end-type-sharing]] — 模块6 前后端类型贯通
