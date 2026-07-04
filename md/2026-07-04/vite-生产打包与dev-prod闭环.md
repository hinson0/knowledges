# Vite 生产打包 与 dev↔prod 闭环

> 学习模块 1 · 2026-07-04 · 基于本仓库 `apps/web`(Vite + React + Turborepo)真实产物验证

---

## 0. 一句话总纲(先记这个)

- **dev = 为写代码优化**:可读 + 热更新(HMR) + 按需实时编译,**不打包**。
- **build / preview / production = 为用户优化**:小 + 快 + 单个包 + 长缓存,**打包**。
- **preview 和 production 是同一份成品(dist/),只差"本机 vs 真实服务器"。**

---

## 1. 核心区分:dev 不打包,build 才打包

| | `vite`(开发) | `vite build`(生产) |
|---|---|---|
| 何时用 | 天天写代码时 | 上线前跑一次 |
| 进程 | 一直开着的服务器 | 跑完即止的任务 |
| 干什么 | 实时逐文件编译,**不打包** | 用 Rollup **打包** → 产出 `dist/` |
| 为谁优化 | 开发者(快速反馈) | 终端用户(小 + 快) |

**为什么要两套?因为两个场景需求正好相反:**
- 开发:只有自己访问 localhost,要的是"改一行立刻看到效果" → 不打包最爽。
- 生产:全世界用户 + 真实网络,要的是"首屏快" → 必须压缩合并成一个包;而且浏览器根本不认识 `.tsx`。

> 佐证:跑 `vite build` 时,输出第一句就是 `building for production...`(为生产而构建)。

---

## 2. 本仓库真实脚本(`apps/web/package.json`)

```jsonc
"dev":     "vite --port 3000",   // 开发:天天用,dev server,不打包
"build":   "tsc && vite build",  // 上线前:跑一次,打包出 dist/
"preview": "vite preview",       // 打包后:本机静态服务器预览成品
```

- `tsc && vite build` 的 `&&`:**先纯类型检查(tsc,不出文件),通过了才让 Rollup 真正产出 `dist/`**。类型有错就不会打包。

---

## 3. build 之后 `index.html` 的入口改写

```html
<!-- 源 index.html(在 <body> 里) -->
<script type="module" src="/src/main.tsx"></script>

<!-- 产物 dist/index.html(挪到 <head> 里) -->
<script type="module" crossorigin src="/assets/index-[hash].js"></script>
```

**一句话记住:入口那行,从"指向源码 `.tsx`"改成"指向打包成品 `.js`"。**

细节:
- 仍然是 `type="module"` —— **生产默认产物还是标准 ESM**,不是倒退回老式全局脚本。
- 挪到 `<head>` 是为了浏览器**尽早发现、尽早开始下载**。
- 你**不用手动改 html**,build 每次会自动重写这行去指向当前哈希。

---

## 4. 内容哈希(content hash)

产物文件名里那串(本次真实见过:`ChgcWHrL` → `C4ZKOHNB` → `Bp3mP0am`)由**文件最终内容**算出。

```
内容变 → 哈希变 → 文件名变 → 浏览器当新文件重新下载
内容不变 → 哈希不变 → 浏览器继续吃缓存
```

这套机制叫 **cache busting(破缓存)**。本次通过"改一行源码 → 重新 build → 哈希连续变了三次"亲眼验证。

**两层缓存策略(经典):**
- 带哈希的 `/assets/*.js` → 配**超长缓存** `Cache-Control: max-age=31536000, immutable`(缓存一年)。反正内容一改文件名就改,永远不会拿到过期旧代码。
- `index.html` **不带哈希**(要有固定 URL 让浏览器每次来问)→ 配短缓存/不缓存。
- 合起来:**入口易变、资源永缓存**。

> 附:真实项目会**代码分割**成多个 chunk,那时"只有内容变了的 chunk 换名字,没变的保持原名继续吃缓存"——这才是内容哈希 + 分包的真正威力。本仓库是单 bundle,演示不到。

---

## 5. 谁进了 bundle(核心陷阱)⭐

`App.tsx` 一共 import 了 4 个外部东西,但**它们进产物的命运完全不同**:

| import 的东西 | 进 bundle 了吗 | grep 证据 | 原因 |
|---|---|---|---|
| `react` + `react-dom` | ✅ 进(约 130KB,大头) | `reactjs.org/docs/error-decoder.html` 命中 | 运行时必须用到 |
| `@repo/ui`(Button/Card) | ✅ 进 | `#1890ff` / `#dddfff` 命中 | 界面真的用了 `<Button/> <Card/>` |
| `@repo/shared` | ❌ **一个字节没进** | `生成 ID是` 命中 0 次 | 见下,两个文件两种原因 |

**`@repo/shared` 里两个文件,两种不同的"没进包"原因:**
1. `types.ts`(`User` / `CreateUserInput`)—— App 里是 `import type {...}`,类型在编译阶段被**完全擦除(类型擦除 / erasure)**,运行时压根不存在。好比行李清单上"衣服"两个字,不是衣服本身。
2. `utils.ts`(`generateId`)—— 是**真实运行代码**,但 web **从头到尾没调用过它** → 被 **tree-shaking(摇树)** 在打包期摇掉。

**两个关键结论:**
- **"依赖了一个包" ≠ "把整个包打进产物"**。Rollup 根本不管 workspace 包边界,只顺着 `import` 图走、**用到啥打啥**。所以 monorepo 里放一堆共享包,产物也不会臃肿。
- **`import type` 是有产物瘦身意义的写法**,不是风格洁癖——它保证零运行时字节。

---

## 6. preview / dev / production 三者关系

> 本次用 `curl` 对照 dev(:3000)与 preview(:4173)真实响应验证。

**破一个误解:它们不是三份不同的东西。**
- **preview = "在本机假装成 production"**,伺服的就是 `dist/` 成品,**和真正上线那份零区别**。区别只在"谁伺服 / 在哪":preview 是本机静态服务器 `localhost:4173`;production 是真实服务器 / CDN + 域名 + HTTPS + 真实网络。
- preview 的用途:**上线前在本地验一验成品有没有毛病**(dev 跑得好好的,打包后偶尔会出问题)。
- **dev 才是异类**:没有 `dist/`,实时编译源码。

| 维度 | **dev**(`vite` :3000) | **preview**(`vite preview` :4173) | **production**(真实上线) |
|---|---|---|---|
| 伺服什么 | 源码,逐个实时编译 | 打包成品 `dist/` | 打包成品 `dist/`(同一份) |
| 打包了吗 | ❌ 否 | ✅ 是 | ✅ 是 |
| JS 请求数 | 几十个(每模块一个) | **1 个** bundle | **1 个** bundle |
| 代码长相 | 可读源码 | 压缩成一坨 | 压缩成一坨 |
| 热更新 HMR | ✅ 有 | ❌ 无 | ❌ 无 |
| 谁伺服 | 本机 dev server | 本机静态服务器 | 真实服务器 / CDN + 域名 |
| 用途 | 天天写代码 | 上线前本地验成品 | 给真实用户 |

### 怎么亲眼看出区别?→ 浏览器 Network 面板 三个抓手

1. **请求数**:dev 几十个 vs preview 1 个。
2. **代码长相**:dev 可读源码 vs preview 压缩一坨。
3. **有没有 `/@vite/client` 那条 HMR websocket**:dev 有,preview 没有。

**curl 实测细节:**
- **dev**:`/src/main.tsx` 实时返回**可读代码**,`import` 指向别的 URL(如 `/node_modules/.vite/deps/react.js`、`/src/App.tsx`)→ 浏览器为每个再发请求 → **裂变成几十个请求**;还带 `fileName`/`lineNumber`/`sourceMappingURL` 调试信息;用 `jsxDEV`(**React 开发版**)。index.html 里额外有一行 `/@vite/client`(HMR 客户端)。
- **preview**:index.html 只引用一个 `/assets/index-[hash].js`;那个 bundle 是 `(function(){const t=...` **一坨**、**无外部 import**(全焊死在一个文件)、无调试信息、React **生产版**。

---

## 附:本模块建立的完整闭环

```
开发模式                          生产模式(build/preview/prod)
──────────                       ────────────────────────────
浏览器直接 import .tsx      →     Rollup 打包成 1 个 .js
逐文件按需编译(ESM)       →     一次性转译 + 压缩 + tree-shake
几十个 HTTP 请求            →     1 个带哈希的 bundle
不缓存、图快                →     内容哈希 + 两层缓存策略
import type / 没用到的代码  →     类型擦除 / tree-shaking,零字节
可读 + HMR + 调试信息       →     压缩一坨 + 无 HMR + 无调试
```
