# pnpm --filter 选包语法:... 上下游 + 必须跟动作

> 来源:pnpm+turbo 学习会话「模块 2」。基于 turborepo_learning 仓库依赖图 `shared ← ui`(ui 依赖 shared?实测否)、`shared ← api`、`shared/ui ← web`。

## Trigger Question

> `pnpm -F '...@repo/shared'` 报错 `ERROR Unknown option: 'recursive'`,为什么?

> 我单独执行 `pnpm -F "...@repo/shared"` 会怎样?

> `pnpm -F '...@repo/shared' exec pwd` 输出了 shared / api / web 三个路径,解释下。

## Key Takeaways

- **`--filter`(`-F`)是"定语"不是"谓语"**:它只回答"对**哪些**包",不回答"**做什么**"。完整命令必须是 `pnpm [选哪些包] [做什么]`。光写 `-F "..."` 不跟动作 → 报误导性的 `Unknown option: 'recursive'`(且退出码诡异地为 0)。
- **`...` 的位置 = 沿依赖图走的方向**:
  - 点在**右**(`@repo/web...`)= web **+ 它依赖的下游**(我需要的东西)
  - 点在**左**(`...@repo/shared`)= shared **+ 依赖它的上游使用者**(谁需要我)
- **实战杀手锏**:改动某个基础包前,先用 `-F "...@repo/shared"` 列出"爆炸半径"(谁会受影响),再决定要重新构建/测试谁。
- **输出按拓扑序**:被依赖的包排在前(shared 在最前),与 Turbo 构建顺序逻辑同源。
- **`exec` 的动作 `pwd` 和 `node` 都合法**:`exec pwd` 能跑通(shell 内置命令照样执行),`exec node -e "..."` 也行,二者等价。之前"必须用 node 不能用 pwd"是过度归因——真正决定成败的是**有没有跟动作**,不是用哪个命令。

## Schema / Field Table

以依赖图为例,`--filter` 各写法选中谁:

| 写法 | 选中谁 | 典型场景 |
|---|---|---|
| `-F @repo/web` | 只有 web | 只动 web 自己 |
| `-F "@repo/web..."` | web + 它依赖的(ui、shared) | 构建 web 需要的全部 |
| `-F "...@repo/shared"` | shared + 依赖它的(api、web) | 改 shared,谁受影响全带上 |
| `-F "...@repo/shared..."` | shared + 上游 + 下游 | 地基包,牵连最广 |

## Code Example

```bash
# 可视化“filter 到底选中了哪些包”:在每个选中包目录里打印路径
pnpm -F "...@repo/shared" exec pwd
# /Users/.../packages/shared      ← shared 自己
# /Users/.../apps/api             ← 依赖 shared 的下游
# /Users/.../apps/web             ← 依赖 shared 的下游

# 等价写法(node 也是合法动作)
pnpm -F "...@repo/shared" exec node -e "console.log(process.cwd())"

# 真正干活:给受影响的包跑 build / test
pnpm -F "...@repo/shared" build
```

## Pitfall / Why

- **`Unknown option: 'recursive'` 的真相**:不是 filter 语法错,而是 filter 后面**没跟任何动作**。pnpm 退化成"对这些包递归执行空命令",冒出关于递归模式的误导性报错。看到这个错先检查"是不是忘了跟 build/add/exec 等动作"。
- **`...` 写法务必加引号**:`"...@repo/shared"`,否则 shell 可能把 `...` 或 `@` 乱解析。
- **ui 为何不在 `...@repo/shared` 结果里**:因为 `packages/ui` 没有声明依赖 shared(只有 react 的 peerDependency)。`...` 只沿"真正声明了的依赖关系"走 —— 呼应 [[pnpm-workspace-symlink-resolution]] 的"谁声明谁才有"。

## Related

- [[pnpm-workspace-symlink-resolution]] — workspace 软链与"谁声明谁才有"
- [[pnpm-add-workspace-vs-version]] — add 加依赖与 workspace:* vs ^版本
