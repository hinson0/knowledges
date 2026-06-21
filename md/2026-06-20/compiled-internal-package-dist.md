# 编译型内部包:消费方读 dist 不读 src,改了必须 build

> 来源:pnpm+turbo 学习会话「模块 6」。基于 turborepo_learning 仓库的 `packages/shared`(被 web/api 消费)。

## Trigger Question

> 给 `User` 接口加了 `age` 字段,web 能直接 import 用上吗?要不要 build?

> 我改了 `src/types.ts` 加了 age,为什么 web 的 `tsc --noEmit` 报 `Property 'age' does not exist on type 'User'`?

> 为什么 `turbo run build --filter=@repo/shared` 显示 `cache hit / FULL TURBO`,我明明改了 src?

## Key Takeaways

- **内部包的入口指向编译产物**:`packages/shared`、`packages/ui` 的 package.json 写 `"main": "./dist/index.js"`、`"types": "./dist/index.d.ts"` —— 指向 **dist,不是 src**。
- **消费方读 dist,不看你编辑的 src**:web/api `import ... from "@repo/shared"` 时,Node/TS 顺着 package.json 的 main/types 读 `dist/`。所以 **改了 src 不 build,消费方看到的还是旧 dist**。
- 这是 monorepo "我明明改了怎么没生效" 的**头号原因**(90% 是忘了 build 或没开 watch)。
- **`cache hit` 不是"什么都没干"**:它会把缓存里的 `outputs`(dist/**)**还原到磁盘** + 回放日志。所以即使 `FULL TURBO` 没真跑 tsc,dist 也会被刷新成缓存里对应那份源码的产物。
- **为什么 turbo.json 连 `dev`/`lint` 都挂 `dependsOn: ["^build"]`**:正因内部包是编译型,消费方运行/检查前必须先把上游 build 出 dist。

## Schema / Field Table

实验三阶段对照(给 User 加 age):

| 阶段 | 操作 | dist 状态 | web `tsc --noEmit` |
|---|---|---|---|
| ① | 改 src 加 age,未 build | 旧的(无 age) | ❌ `TS2339: Property 'age' does not exist` |
| ② | `turbo run build --filter=@repo/shared` | 被缓存还原成带 age 版(`cache hit / FULL TURBO`) | —— |
| ③ | 再次检查 | 新的(有 age) | ✅ 通过 |

编译型 vs JIT 内部包:

| 流派 | main 指向 | 改了要不要 build | 取舍 |
|---|---|---|---|
| 编译型(本项目) | `./dist/index.js` | **要**(或开 watch) | 产物边界清晰、显式;需 `^build` 编排 |
| JIT/即时 | `./src/index.ts` | 不要,改了即生效 | 免 build;要求消费方打包器(vite/tsx)能现场编译 TS |

## Code Example

```jsonc
// packages/shared/package.json —— 入口指向 dist(编译型的标志)
{
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts"
}
```

```bash
# 复现“改了 src 不 build 就不生效”
# 1) 给 packages/shared/src/types.ts 的 User 加 age: number; (先别 build)
pnpm -F @repo/web exec tsc --noEmit   # ❌ TS2339: Property 'age' does not exist

# 2) build shared —— 把 age 编译进 dist(或缓存命中还原带 age 的 dist)
pnpm exec turbo run build --filter=@repo/shared

# 3) 再检查 —— 通过
pnpm -F @repo/web exec tsc --noEmit   # ✅ 无输出
```

## Pitfall / Why

- **核心因果**:同一行 `{u.age}`,dist 没刷新时报错、dist 刷新后通过。中间隔的那道墙就是 `tsc` 编译(无论真跑 cache miss,还是缓存还原 cache hit)。src 改动必须经过一次 build 落到 dist,消费方才看得见。
- **cache hit 为何还能让 dist 变新**:缓存键认的是"源码内容哈希",不是"你改没改过"。之前用"带 age 的 src"真构建过一次(产物按哈希存进缓存),这次 src 内容回到同一状态 → 哈希命中 → 直接还原那份带 age 的 dist。把 [[turbo-cache-incremental-build]](缓存按源码内容算哈希)和本主题(web 读 dist)打通了。
- **排错口诀**:monorepo 里改了内部包没生效,先检查"上游 build 了吗 / watch 开了吗",再怀疑别的。

## Related

- [[turbo-cache-incremental-build]] — 缓存指纹与 cache hit/miss
- [[turbo-dependson-build-order]] — 为什么 dev/lint 也挂 ^build
- [[pnpm-workspace-symlink-resolution]] — import 怎么软链解析到 packages/x
- [[monorepo-end-to-end-type-sharing]] — 前后端共享同一份类型
