# Turborepo 内置 TUI:左选服务、右看视窗的来源

> 来源:pnpm+turbo 学习会话「模块 5」。起点是一张终端截图:启动多个 dev 服务时,左边能选服务、右边是该服务的实时视窗。

## Trigger Question

> 我如何实现在启动一个服务的时候,左边可以选择服务,右边是这个服务的一个 view 的视窗?这是通过什么实现的?是通过 Turbo 还是什么?

> 如何开启 TUI?

## Key Takeaways

- **那个"左选服务、右看视窗"的界面 = Turborepo 2.0 内置的 Terminal UI (TUI)**,不是 tmux、不是 Next.js、不需要任何额外工具。
- **左侧列的是"正在运行的任务"(不是文件),右侧是当前选中任务的实时 stdout**——这就是"左边选服务、右边看那个服务输出"的本质。
- **TUI 是 Turbo 2.x 的默认行为,无需"开启"**:只要满足三个触发条件,跑起来就自动出现。之前看不到,往往是因为命令在进入 TUI 之前就报错退出了(如 workspace 包名冲突)。
- **识别证据**(一眼认出是 Turbo 干的):左上 `Tasks (/ - Search)`;任务 ID 是 `包名#任务名` 格式(`web#dev`、`@repo/ui#dev`);`cache bypass, force executing`(因 dev 设了 `cache:false`)。
- **dev 为何设 `cache:false`**:长驻服务每次都要真跑、没有"最终产物"可缓存,缓存它没有意义。详见 [[turbo_persistent]]。

## Schema / Field Table

**触发 TUI 的三个条件(必须同时满足)**:

| # | 条件 | 不满足的后果 |
|---|---|---|
| 1 | Turbo **2.x** | 旧版没有 TUI |
| 2 | 任务有 `"persistent": true` | 没有长驻任务就没必要分栏 |
| 3 | 交互式 **TTY**(真实终端) | 管道/CI/无 TTY 会自动退化成 stream 模式 |

**控制方式与优先级(高 → 低)**:

| 控制方式 | 写法 |
|---|---|
| 命令行(最高) | `--ui=tui` / `--ui=stream` |
| 环境变量 | `TURBO_UI=stream` |
| turbo.json 顶层 | `"ui": "tui"` |
| 默认(最低) | tui |

**TUI 操作键**:

| 键 | 作用 |
|---|---|
| ↑/↓ 或 j/k | 在左侧切换不同任务 |
| `/` | 搜索任务(对应 `Tasks (/ - Search)`) |
| `i` | 进入交互模式,向选中的 dev server 直接输入 |
| Ctrl-C | 停止全部任务退出 |

## Code Example

```bash
# 起多个长驻 demo 服务,自动进入 TUI(左侧 demo-a/b/c#dev,右侧各自心跳日志)
pnpm exec turbo run dev --filter='@repo/demo-*'

# 对比旧式滚动日志(多服务日志会混在一起刷屏)
pnpm exec turbo run dev --filter='@repo/demo-*' --ui=stream

# 临时用环境变量覆盖
TURBO_UI=stream pnpm exec turbo run dev --filter='@repo/demo-*'
```

```json
// turbo.json 顶层固定 TUI(项目级)
{
  "$schema": "https://turbo.build/schema.json",
  "ui": "tui",
  "tasks": { "dev": { "cache": false, "persistent": true } }
}
```

## Pitfall / Why

- **看不到 TUI ≠ 没开启**:最常见原因是命令在进 TUI 前就报错退出。例如两个 workspace 包 `name` 重复 → `Failed to add workspace … it already exists` → 任务还没跑就退,自然看不到 TUI。先让命令能成功跑起 persistent 任务,TUI 自己就出来了。
- **非交互式终端会退化成 stream**:把输出用管道重定向(`... | tee`)、在非 TTY 的 IDE 面板、或无 TTY 的 SSH 里跑,TUI 强制不出来(加 `--ui=tui` 也没用),需换真实终端。
- **Next.js 的 `inferred workspace root / multiple lockfiles` 警告与 TUI 无关**:那是 Next/Turbopack 自己发的(在 git worktree 里检测到多个 `pnpm-workspace.yaml`,不确定仓库根),设 `turbopack.root` 指定根目录可消除。别和 Turbo 的 TUI 混为一谈。
- **`包名#任务名` 这个任务 ID 正是 TUI 左侧条目的来源**,也和 [[turbo-dependson-build-order]] 里 build 日志的任务 ID 同源。

## Related

- [[turbo_persistent]] — persistent 任务的概念(常驻/不可缓存/不可被 dependsOn)
- [[turbo-dependson-build-order]] — 任务 ID `包名#任务名`、任务编排
- [[turbo-cache-incremental-build]] — 为何 dev 用 cache:false、缓存机制
