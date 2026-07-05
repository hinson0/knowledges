---
name: vite-dev-esm-hmr-turbo
description: Vite 开发不打包的原理、HMR 状态保留机制,以及在 turbo monorepo 中依赖 dist 产物的编排
date: 2026-07-02
tags: [vite, esm, hmr, esbuild, react-fast-refresh, turborepo, monorepo]
source: session
---

# Vite 学习:开发不打包、HMR 与 turbo monorepo 集成

## TL;DR

Vite 开发时**不打包**,靠浏览器原生 ESM 按需请求 + 即时转译,第三方依赖用 esbuild 预构建并强缓存;HMR 靠注入的 `import.meta.hot` + React Fast Refresh **只换单个模块并保留组件 state**;在 monorepo 里 web 引用的是依赖包 **build 后的 dist 产物**,靠 turbo 的 `dependsOn: ["^build"]` 拓扑排序保证上游先就绪。

## Key Points

- **开发不打包**:Network 面板是"一小堆分开的模块请求",而非一个 bundle.js——浏览器原生 ESM 要哪个模块才请求哪个。
- **依赖预构建**:react 等第三方库启动时被 esbuild 打包进 `node_modules/.vite/deps/`,URL 带 `?v=hash` → 强缓存;而 `/src/*.tsx` 源码按需即时转译、不缓存。
- **改写裸导入**:`import "react"` / `"@repo/ui"` 会被改写成真实 URL(`.vite/deps/...` 或 `/@fs/...`),因为浏览器原生 ESM 不认识"裸包名"。
- **HMR ≠ 整页刷新**:改代码保存触发 HMR = 只换一块砖、保留 state;手动按 F5 = 整页重启、state 清零。
- **React Fast Refresh**:Vite + `@vitejs/plugin-react` 自动注入 `import.meta.hot`、`$RefreshReg$`/`$RefreshSig$`,让组件热替换时保留 `useState`。
- **编辑器必须真落盘**:WebStorm 惰性保存,需 `Cmd+S`(Save All)强制写盘,否则 Vite 文件监听收不到变更。
- **monorepo 依赖的是产物**:web 通过依赖包 `package.json` 的 `exports` 解析到 `@repo/ui` 的 `dist/index.js`;依赖包没 `build` 就报错。
- **turbo 拓扑排序**:`dependsOn: ["^build"]` 的 `^` = 上游依赖包;turbo 靠 `Dependencies`/`Dependents` 连成 DAG,无依赖的先跑(可并行),下游最后跑。

## Details

### 模块① 核心原理:为什么不打包、为什么快

**观察一(Network)**:开发服务器跑起来后,加载的是几十个**各自独立的小文件**(每个模块一个请求),不是一个大 bundle——这是 Vite 不打包的铁证。

> 坑:Network 面板若选了 `Fetch/XHR` 过滤器,只显示 JS 里 `fetch()`/XHR 主动发的请求;模块请求走原生 ESM,归在 `JS`/`文档` 分类,要点 **「全部」** 才看得到。

**观察二(两类 URL = 依赖预构建 vs 源码按需)**:

| | `react`(第三方依赖) | `App.tsx`(自己的源码) |
|---|---|---|
| URL | `/node_modules/.vite/deps/react.js?v=96a9aa3a` | `/src/App.tsx` |
| 谁编译、何时 | esbuild **启动时打包一次** | **每次请求即时转译** |
| 缓存 | `?v=hash` 强缓存 | 不缓存,随时重编译 |
| 为什么 | 别人的、不变、量大 → 打包+缓存 | 自己的、常改 → 每次拿最新 |

**观察三(App.tsx 编译产物 response 的 4 个变化)**:

```js
// ④ Vite 注入的 HMR / Fast Refresh(源码里一个字没写)
import.meta.hot = __vite__createHotContext("/src/App.tsx");
window.$RefreshReg$ = ...  window.$RefreshSig$ = ...
// ② 裸导入被改写成真实 URL
import { Button, Card } from "/@fs/Users/.../packages/ui/dist/index.js";
// ③ CJS 依赖被包装成 ESM
import __vite__cjsImport4_react from "/node_modules/.vite/deps/react.js?v=96a9aa3a";
const useState = __vite__cjsImport4_react["useState"];
// ① 类型抹除:源码 fetchUsers(): Promise<User[]>  →  产物 fetchUsers()
```

- ① **类型抹除**:浏览器不认 TS,即时转译剥掉类型。
- ② **改写裸导入**:`/@fs/` 是 Vite 访问项目目录外真实文件系统的前缀(workspace 包软链在 `packages/`)。
- ③ **CJS→ESM interop**:react 是 CommonJS,预构建时 esbuild 转成 ESM 再解构。
- ④ **HMR 注入**:`$RefreshReg$`/`$RefreshSig$` 就是让组件热更新保留 state 的机关。

### 模块② 动手:HMR 状态保留 vs 整页刷新

**实验**:在 `App.tsx` 加 `const [count,setCount]=useState(0)` + 一个 `<button onClick={()=>setCount(count+1)}>`,点到 5,再改一行代码保存。

- **数字保留 = 5** → HMR 生效:页面没重启、组件没销毁,只热替换了 `App` 模块。
- 若数字归 **0** → 那是**整页刷新**(手动 F5),整个 React 树重建。
- 一句话:**手动刷新 = 砸了重盖;HMR = 只换一块砖。**

**完整因果链**:`Cmd+S` 落盘 → Vite 文件监听(chokidar)收到变更 → 只重编译该模块 → 经 `import.meta.hot`(WebSocket)推给浏览器 → React Fast Refresh 用新代码替换组件但保留 `useState`。

> **WebStorm 踩坑**:IntelliJ 系默认惰性保存(切焦点/运行/空闲才写盘),敲完字磁盘可能还是旧的 → Vite 收不到变更 → "改了没反应"。养成改完立刻 **`Cmd+S`(Save All)** 的习惯。

### 模块③ 与 turbo monorepo 的接缝:为什么依赖包要先 build

**报错三步因果链**(以"`@repo/ui` 没 build、直接启动 web"为例):

1. **软链**:`apps/web/package.json` 里 `"@repo/ui": "workspace:*"` → pnpm 把 `node_modules/@repo/ui` 软链到 `packages/ui`。
2. **入口 = dist**:解析器读 `packages/ui/package.json` 的 `"exports": { ".": "./dist/index.js" }` → 解析到 `packages/ui/dist/index.js`(**产物,不是 src**)。
3. **产物缺失就报错**:ui 源码是 TS,`build` 脚本 `tsc` 把 src 编进 dist。没 build → `dist/` 不存在 → 请求 `.../dist/index.js` 失败 → **模块解析报错**。

**turbo 的解法**(`turbo.json`):

```json
"dev":   { "dependsOn": ["^build"] },
"build": { "dependsOn": ["^build"], "outputs": ["dist/**"] }
```

- `^` = **上游依赖包**。`dependsOn: ["^build"]` = 跑本包 dev/build 前,先把依赖包(ui、shared)的 `build` 跑完。(不带 `^` 的指同包其它任务。)
- 验证(只读):`npx turbo run build --filter=@repo/web --dry` → `Tasks to Run` 里 `@repo/shared#build` 的 `Dependencies=(空)`、`Dependents=@repo/web#build`。
- turbo 靠这两个字段连成 **DAG 拓扑排序**:

```
@repo/shared ─┐
              ├──→ @repo/web   (依赖两者,最后跑)
@repo/ui ─────┘
（无依赖,先跑,可并行）
```

**分工闭环**:Vite 负责编译 web 这一个应用,turbo 负责保证 shared/ui 提前就绪。

## References

- 项目文件:`apps/web/{index.html, vite.config.ts, src/App.tsx, package.json}`、`packages/ui/package.json`(exports 指向 dist)、`turbo.json`(dependsOn `^build`)
- 关键命令:`pnpm --filter @repo/web dev`;`npx turbo run build --filter=@repo/web --dry`
- 前置知识:pnpm + turbo 基础(见 `~/knowledges/md/2026-06-20/`)
- 同目录相关:`hmr.md`(HMR 概念通用讲解)
- 可深挖:`vite build` 生产打包(切回 Rollup)、Vite 插件机制
