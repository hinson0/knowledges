# pnpm add 给指定包加依赖:workspace:* vs ^版本号 + 隔离性

> 来源:pnpm+turbo 学习会话「模块 2」。在 turborepo_learning 仓库给 `apps/web` 单独加 zod 验证。

## Trigger Question

> `pnpm -F @repo/web add zod` 之后,哪个 package.json 会变?api 会变吗?zod 会出现在 web 的 node_modules 里吗?

## Key Takeaways

- **`pnpm -F @repo/web add zod` 只动 web**:只有 `apps/web/package.json` 多出 `"zod"`,`apps/api` 的依赖树纹丝不动 —— 这就是"谁声明谁才有"的隔离性。
- **同一个 `dependencies` 块里,前缀决定 pnpm 的行为**:
  - `"@repo/shared": "workspace:*"` → `workspace:` 前缀 = 链**本地工作区**包(软链)
  - `"zod": "^4.4.3"` → 语义化版本号 = 去 **npm 下载**
- **第三方包全局只存一份**:zod 的真身放在仓库的 `node_modules/.pnpm/zod@4.4.3/...`(content-addressable store),`apps/web/node_modules/zod` 只是软链过去。即使多个包都装 zod,磁盘上也只有一份 —— pnpm 比 npm/yarn 省空间的根本原因。
- **隔离性的工程价值**:给前端加重型库,后端的安装体积/构建产物/启动速度完全不受影响 —— monorepo "共享代码但不共享垃圾"。

## Schema / Field Table

`pnpm add` 的常用变体:

| 目的 | 命令 | 进入哪个字段 |
|---|---|---|
| 加运行时依赖 | `pnpm -F @repo/web add zod` | `dependencies` |
| 加开发期工具 | `pnpm -F @repo/web add -D vitest` | `devDependencies` |
| 加 monorepo 内部包 | `pnpm -F @repo/api add @repo/ui --workspace` | `dependencies`(自动写成 `workspace:*`) |

## Code Example

```bash
# 给单个包加依赖
pnpm -F @repo/web add zod

# 验证只有 web 变,api 不变
grep -A5 '"dependencies"' apps/web/package.json   # 出现 "zod": "^4.4.3"
ls -la apps/api/node_modules/ | grep zod || echo "(api 里没有 zod —— 符合预期)"

# 验证 zod 是软链且指向中央 store
ls -la apps/web/node_modules/ | grep zod
# zod -> .pnpm/zod@4.4.3/node_modules/zod
```

## Pitfall / Why

- **`-F` 后面写包名(`name` 字段)最稳**:`-F @repo/web` 用全名无歧义;也支持 `-F ./apps/web`(路径)或 `-F web`(目录名模糊匹),但全名最不易错 —— 呼应"包名才是主键"。
- **`add` 默认进 `dependencies`**:开发工具记得加 `-D` 放到 `devDependencies`,否则会污染生产依赖。
- **`^4.4.3` 的 `^` 是 npm 语义化版本规则**(允许 4.x.x 内更新),不是 pnpm 特有;与 `workspace:*` 的本地含义无关。

## Related

- [[pnpm-workspace-symlink-resolution]] — workspace 软链与"谁声明谁才有"
- [[pnpm-filter-selection-syntax]] — --filter 选包语法(... 上下游)
