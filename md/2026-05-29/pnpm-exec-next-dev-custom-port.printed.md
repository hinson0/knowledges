# 用自定义端口启动 Next dev(不改 package.json)

## Trigger Question

> 端口 8123 被占(EADDRINUSE),如何在 8124 启动,不要手动改配置?
>
> pnpm exec next dev --port 8124 这行命令怎么理解?

## Key Takeaways

- `pnpm dev` 实际执行 package.json 脚本 `next dev --port 8123`(端口写死),且经 turbo 拉起所有包(web 8123 + docs 3001),端口被占就全挂。
- 不改文件、临时换端口、且只跑 web 一个包:`cd apps/web && pnpm exec next dev --port 8124`。这是 **运行时覆盖**,package.json 一字不改。
- `pnpm exec` = 运行项目本地装的 CLI(在 `node_modules/.bin/`,不在全局 PATH);`next` 是 Next.js 自带工具,`dev` 是启动开发服务器子命令,`--port 8124` 指定监听端口。

## Code Example

```bash
cd apps/web
pnpm exec next dev --port 8124
# 一行版(从仓库根,不用 cd):
pnpm --filter web exec next dev --port 8124
# 远程访问 localhost 连不上时绑定:
pnpm exec next dev --port 8124 -H 0.0.0.0
```

| 片段          | 作用                                                       |
| ------------- | ---------------------------------------------------------- |
| `pnpm exec`   | 运行项目本地装的 CLI(在 `node_modules/.bin/`,不在全局 PATH) |
| `next`        | Next.js 自带命令行工具(`node_modules/.bin/next`)         |
| `dev`         | 子命令:启动开发服务器(热更新)                           |
| `--port 8124` | 传给 next dev 的监听端口                                    |

## Pitfall / Why

- 直接敲 `next` 会 command-not-found —— 它没装全局;`pnpm exec` 负责去 node_modules 找它跑。
- `PORT=8124 pnpm dev` 不管用:脚本里硬编码的 `--port 8123` 会盖过 PORT 环境变量。
- 占着 8123 的多半是别的分支 / 主仓库的实例,留着不动,新实例用 8124 即可。
- 类比:`pnpm dev` = 按套餐点单;`pnpm exec next dev --port 8124` = 绕过套餐直接点这道菜并指定做法。

## Related

- [[reference-image-upload-flow]] — 起服务后浏览器手动验证上传/关键字
