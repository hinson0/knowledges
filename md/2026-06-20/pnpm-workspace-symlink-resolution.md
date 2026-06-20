# pnpm workspace 的"连接"机制:发现 → workspace:* → 软链 → import 解析

> 来源:pnpm+turbo 学习会话「模块 1」。围绕 turborepo_learning 仓库(`apps/web`、`apps/api`、`packages/shared`、`packages/ui`)的真实代码。

## Trigger Question

> (自测 1)怎么一眼判断 `apps/web/node_modules/@repo/ui` 是软链而不是真目录?看哪个字符 + 哪个符号?

> (自测 2)为什么 `apps/api/node_modules/@repo/` 里只会有 `shared`、不会有 `ui`?

> (背景)monorepo 里 `apps/web` 写 `import { Button } from "@repo/ui"`,但 `@repo/ui` 从未发布到 npm,它是怎么被找到的?

## Key Takeaways

- monorepo 跨包 import 的本质 = **文件系统级的符号链接(软链)**,不是网络下载、不是复制。
- 一次"连接"建立的完整链路:
  1. `pnpm-workspace.yaml` 里 `apps/*`、`packages/*` 通配符 → `pnpm install` 扫描出所有本地包,建「包名 → 目录」表;
  2. 某包 `package.json` 写 `"@repo/ui": "workspace:*"` → pnpm 看到 `workspace:` 暗号,**不联网**;
  3. 在该包的 `node_modules/@repo/ui` 建一条软链,指回 `packages/ui` 真实目录;
  4. 代码里的 `import "@repo/ui"` 顺着软链落到 `packages/ui` 源码。
- **判断软链的两个铁证**:`ls -l` 行首类型字符是 `l`(link);且输出带 `->` 箭头指向真身。看到箭头即软链,比数权限位更快。
- **"谁声明谁才有"**:一个包的 `node_modules` 里只出现它自己 `package.json` 声明过的依赖。`apps/api` 只声明了 `@repo/shared`,所以它的 `node_modules` 里没有 `@repo/ui`。
- **现代 pnpm 默认严格隔离**:根 `node_modules` 里没有 `@repo/*`(本次实测 `ls node_modules/@repo/` 报 No such file or directory,属正常),工作区包的软链只出现在"声明了它的那个子包"里。

## Schema / Field Table

`ls -la apps/web/node_modules/@repo/` 输出逐字段解读:

| 字段示例 | 含义 |
|---|---|
| `lrwxr-xr-x` 行首的 **`l`** | 文件类型 = symbolic link(软链)。对比:`-` 普通文件、`d` 目录 |
| `shared` / `ui` | `apps/web` 眼中的包名 `@repo/shared` / `@repo/ui` |
| `-> ../../../../packages/shared` | 软链指向的真身(相对路径)。**只有软链才有这个 `->`** |
| `../../../../` 数四层 | 从 `apps/web/node_modules/@repo/shared` 逐级上爬到仓库根,再进 `packages/shared` |

## Code Example

```bash
# ① 安装/同步所有工作区依赖,并建立软链
pnpm install

# ② 看某个包里的 @repo 软链(关键证据:行首 l + 箭头)
ls -la apps/web/node_modules/@repo/
# lrwxr-xr-x ... shared -> ../../../../packages/shared
# lrwxr-xr-x ... ui     -> ../../../../packages/ui

# ③ 验证“谁声明谁才有”:api 只声明了 shared,所以这里没有 ui
ls -la apps/api/node_modules/@repo/

# 调试软链指向的两个利器
readlink apps/web/node_modules/@repo/ui   # 直接打印箭头目标
ls -lL apps/web/node_modules/@repo/ui     # 大写 L:穿过软链显示目标信息
```

## Pitfall / Why

- **为什么根 `node_modules` 没有 `@repo`,不是 bug**:pnpm 默认不把工作区包"提升(hoist)"到根目录,目的是防 **幽灵依赖(phantom dependency)**——即"我没在 package.json 声明某包,却因为别人装了它而能 import 到",一旦那个别人移除依赖,代码就神秘崩溃。pnpm 的规矩:你的 `node_modules` 里只出现你自己声明过的东西。
- **所以 api 想用 `@repo/ui` 必须自己显式加一行**(`pnpm -F @repo/api add @repo/ui --workspace`),这正好预告"加依赖"操作。
- **`workspace:*` 是关键暗号**:没有它(写成普通版本号),pnpm 会尝试去 npm 下载同名包而非链本地;有它才走"本地软链"路径。
- **包名(`name` 字段)才是主键,目录名只是给人看的**:import / `--filter` / `workspace:*` 解析全靠 `name`。两个包 `name` 重复会导致 workspace 解析直接失败(`Failed to add workspace … it already exists`)。

## Related

- [[turbo_persistent]] — Turbo 任务编排与 persistent(dev/TUI)
- [[pnpm-allowbuilds-ignored-builds]] — pnpm 安装期的 build 脚本审批
