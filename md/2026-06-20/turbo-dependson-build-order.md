# Turbo 任务编排:dependsOn 的 ^ 与 build 执行顺序

> 来源:pnpm+turbo 学习会话「模块 3 · Turbo 任务编排:看见顺序」。基于 turborepo_learning 仓库(7 个工作区包:shared/ui/web/api + demo-a/b/c)。

## Trigger Question

> 我把 `turbo.json` 里 `build` 的 `dependsOn` 从 `["^build"]` 改成 `["build"]`(去掉了 `^`),运行 `turbo run build` 报错 `× @repo/demo-b#build depends on itself`,我没搞懂。

> 为什么 `Running build in 7 packages` 但结尾 `Tasks: 4 total`?差的 3 个是谁?

> `@repo/web#build` 这个写法里 `#` 前后分别是什么?

## Key Takeaways

- **执行顺序是 Turbo 自动推导出来的,不是手写的**:你只在各 `package.json` 里声明依赖(`"@repo/shared": "workspace:*"`),Turbo 据此把"依赖关系"翻译成"执行顺序"(拓扑序)。`build` 时 ui/shared 永远排在 web/api 之前;互不依赖的 ui 与 shared 之间顺序自由(可并行)。
- **`dependsOn` 里 `^` 决定指向谁**:`"^build"` = "先跑**我依赖的那些包(上游)**的 build";去掉 `^` 写成 `"build"` = "先跑**本包自己**的 build"。
- **把 `"build"` 写进 build 任务的 dependsOn = 自环**:等于"我的 build 要先等我的 build 跑完",自己依赖自己 → Turbo 在建任务图时直接拒绝:`depends on itself`。
- **任务 ID 格式 = `包名#任务名`**:如 `@repo/web#build`(在 web 包里跑 build)。这正是最初 TUI 左侧 `web#dev`、`@repo/ui#dev` 的来源——那不是文件名,是 Turbo 的任务 ID。
- **scope(7)≠ tasks(4)**:Turbo 通过 pnpm-workspace 发现 7 个包(含 demo-a/b/c),但 demo 包没有 `build` 脚本,Turbo 只对"真定义了该任务的包"执行,其余静默跳过,故实际只跑 shared/ui/api/web 共 4 个。

## Schema / Field Table

`dependsOn` 四种写法对照(以 `build` 任务为例):

| 写法 | 含义 | 写进 build 里是否合法 |
|---|---|---|
| `"^build"` | 先跑**我依赖的包(上游)**的 build | ✅ 正确用法(web 等 ui/shared) |
| `"build"` | 先跑**本包**的 build | ❌ 自环(自己依赖自己) |
| `"lint"` | 先跑**本包**的另一个(不同名)任务 | ✅ 合法(如 build 前先 lint) |
| `"@repo/shared#build"` | 先跑**指定某个包**的 build(精确点名) | ✅ 合法 |

记忆点:**`^` 在 = 看别的(上游)包;`^` 不在 = 看本包**;无 `^` 不是没用,而是要指向不同名任务,指向同名才自环。

## Code Example

正确的 `turbo.json` 片段:

```json
{
  "tasks": {
    "build": {
      "dependsOn": ["^build"],   // ← 关键:^ 表示先 build 上游依赖
      "outputs": ["dist/**"],
      "env": ["NODE_ENV"]
    }
  }
}
```

`turbo run build` 关键日志(节选):

```text
• Packages in scope: @repo/api, @repo/demo-a, @repo/demo-b, @repo/demo-c, @repo/shared, @repo/ui, @repo/web
• Running build in 7 packages
┌─ @repo/ui#build ──        # ui / shared 先
┌─ @repo/shared#build ──
┌─ @repo/api#build ──       # api / web 后(依赖在前)
┌─ @repo/web#build ──       # web 最后,日志含 vite build
 Tasks:    4 successful, 4 total   # 7 个包里只有 4 个有 build 脚本
```

去掉 `^` 后的报错:

```text
× @repo/demo-b#build depends on itself
```

## Pitfall / Why

- **自环报错的根因**:`dependsOn: ["build"]` 让每个包的 build 依赖自己同名的 build,形成环。Turbo 是**先按 turbo.json 规则给所有包建任务图并做合法性校验,再去看哪个包真有脚本**,所以自环在校验阶段就炸了。
- **为什么偏偏报 demo-b**:具体报哪个包带随机性(取决于 Turbo 内部遍历到的第一个触发环的节点),与"demo-b 有没有 build 脚本"无关——根因是**所有包都中招的自环**,demo-b 只是第一个被喊出来的。
- **scope vs tasks 的差**:`Packages in scope` 是 Turbo 发现的全部包数;`Tasks: N total` 是实际执行的任务数。没定义该任务脚本的包被静默跳过,不报错。
- 缓存命中(`FULL TURBO` / replaying logs)属于另一主题,详见模块 4(增量缓存)。

## Related

- [[turbo_persistent]] — Turbo persistent / dev / TUI
- [[pnpm-filter-selection-syntax]] — --filter 选包语法(在 Turbo 里原样复用)
- [[pnpm-workspace-symlink-resolution]] — workspace 软链与"谁声明谁才有"(依赖图来源)
