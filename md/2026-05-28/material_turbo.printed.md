明白了。下面是这个仓库的全貌 + 你要的那条「首页路径」。

## 项目结构总览

```
material_turbo/                   ← Turborepo monorepo 根
├── pnpm-workspace.yaml           ← 把 apps/* 和 packages/* 声明为工作区
├── turbo.json                    ← Turbo 的任务编排(dev/build/lint/check-types)
├── package.json                  ← 根脚本:`pnpm dev` 就是 `turbo run dev`,会并行启所有 app
├── CLAUDE.md                     ← 你给我立的规矩(禁止直接动 main)
├── .githooks/pre-commit          ← 本地 hook:在 main 上 commit 会被拒
│
├── apps/                         ← ★ 可独立运行的应用都在这
│   ├── web/                      ← ★★ 你浏览器看到的那个站(端口 8123)
│   ├── prototype/                ← Atlas 的原型(HTML 版),被「逐页移植」到 web
│   └── docs/                     ← 另一个 Next.js 文档站(模板带来的)
│
├── packages/                     ← 可被多个 app 复用的共享包
│   ├── ui/                       ← 共享 React 组件
│   ├── eslint-config/            ← 统一 lint 规则
│   └── typescript-config/        ← 统一 tsconfig
│
├── docs/                         ← 仓库级文档(不是网站,是 md 文件)
├── graphify-out/                 ← graphify 钩子产出的知识图谱,不是源代码
└── .remember/                    ← remember 工具的历史缓冲,也不是源代码
```

## `http://35.74.250.39:8123/` 的请求路径

端口 `8123` 来自 `apps/web/package.json` 的 `"dev": "next dev --port 8123"`,所以打开的就是 **`apps/web`** 这个 Next.js 应用。

Next.js 16 用的是 **App Router**:URL 路径 `/` ⇒ 对应 `app/page.tsx`。所以请求链条是:

```
浏览器 GET /
   └─ apps/web/app/layout.tsx        ← 根布局(<html>/<body>、字体、metadata)
        └─ apps/web/app/page.tsx     ← 路由 "/" 的入口,内容只有一行:<AtlasApp />
             └─ apps/web/components/atlas/AtlasApp.tsx   ← 真正的容器组件
                  └─ apps/web/components/atlas/ChatMain.tsx   ← ★ 你看到的聊天主界面
```

**所以——如果你说的「首页内容」是页面里那个聊天 UI(标题、消息、输入框那些),要改的是 `apps/web/components/atlas/ChatMain.tsx`**,以及它依赖的:

- `components/atlas/components/*.tsx` — 子组件(`CandidateCard`、`InlineTaskCard`、`QuickTaskMessage` 等)
- `components/atlas/data/candidates.ts` — 假数据
- `components/atlas/tokens.ts` — 颜色/字号等设计 token(`A_TOKENS`)
- `components/atlas/icons.tsx` — 图标
- `app/layout.tsx` — 标题(浏览器 tab 上的 "Atlas")、全局字体、`<html lang>`
- `app/globals.css` — 全局 CSS

`★ Insight ─────────────────────────────────────`
- **`page.tsx` 是 Next.js App Router 的约定文件名**:任何目录下放一个 `page.tsx`,这个目录就变成一条路由。`app/page.tsx` ⇒ `/`,`app/about/page.tsx` ⇒ `/about`。`layout.tsx` 同理但表示「该路由及其子路由共用的外壳」,会包住子页面。
- **`page.tsx` 故意只有一行**:这是你之前移植 Atlas 时立的硬约束(memory 里那条 [atlas-prototype-port])——`page.tsx` 保持极简,真正的 UI 全部丢到 `components/atlas/` 里,这样路由层和视图层解耦,以后想加 `/atlas`、`/about` 之类的新路由只是再开一个目录,不用动现有组件。
- **`"use client"` 出现在 `AtlasApp.tsx` 顶部**:Next.js 16 默认所有组件都是 Server Component,只有显式标 `"use client"` 的子树才会带到浏览器跑(因为它用了 React state / context — `NavProvider`)。`page.tsx` 和 `layout.tsx` 本身仍然是 Server Component,只是渲染了一个 client 子树。这就是为什么字体和 metadata 放 `layout.tsx`(server 端处理更高效),交互逻辑放 `AtlasApp.tsx`(必须 client)。
- **`apps/prototype/`** 不是用来访问的运行时,是 HTML 静态原型,作为「视觉真值」存在,所以 memory 里那条"完全按原型不要乱改"的约束指的就是:动 `ChatMain.tsx` 时要对照 `apps/prototype/Prototype_A.html` 来改,不能凭感觉发挥。
`─────────────────────────────────────────────────`

想改首页,**入口文件就是 `apps/web/components/atlas/ChatMain.tsx`**。先告诉我你想改哪一块(文案?布局?新增功能?),我可以带你定位到具体的代码段。