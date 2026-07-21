摸清楚了。下面按"目录树 + 每个目录干什么"来讲,并标注**前端(浏览器)/ 后端(服务端)**的边界——这是理解这个项目最关键的一条线。

```
apps/web/
├── app/              ← Next.js App Router:路由 + 后端接口(约定式)
│   ├── layout.tsx        根布局:<html>/<body>、字体、<title>。所有页面的外壳
│   ├── page.tsx          首页路由 "/"。内容极薄,只 return <AtlasApp />
│   ├── globals.css       全局样式
│   ├── favicon.ico
│   └── api/admin/users/  ← 后端 REST 接口(服务端运行)
│       ├── route.ts          GET=列用户 / POST=建用户
│       └── [id]/route.ts     PATCH=改角色·重置密码 / DELETE=删用户([id]=动态参数)
│
├── components/atlas/  ← 真正的 UI(整个应用界面都在这)
│   ├── AtlasApp.tsx      应用总壳:挂 Auth/Nav 上下文、决定显示哪个屏
│   ├── ChatMain.tsx      主聊天/工作区界面
│   ├── Workstation.tsx   工作台界面
│   ├── nav-context.tsx   页面间导航状态(go/toast 等)
│   ├── tokens.ts         设计 token(颜色/字体/间距,= A_TOKENS)
│   ├── icons.tsx / buttons.ts   图标、按钮样式
│   ├── test-utils.tsx    测试专用:造"已登录"上下文、fake 客户端
│   ├── auth/             ← 认证相关 UI + 状态
│   │   ├── auth-context.tsx       登录态核心(就是这次改的文件)
│   │   ├── AuthGate.tsx           门卫:loading→转圈 / 没登录→登录页 / 已登录→放行
│   │   ├── AuthScreen.tsx         登录页
│   │   ├── ProfileScreen.tsx      个人资料(改昵称)
│   │   ├── UserManagementScreen.tsx  用户管理
│   │   └── ui.tsx                 表单小组件(EmailInput/PasswordInput/Field)
│   ├── components/       ← 可复用小组件(纯展示)
│   │   ├── CandidateCard / ScoreBadge / DomainPill / MiniRadar / InlineTaskCard / QuickTaskMessage
│   ├── data/             ← 静态/示例数据
│   │   └── candidates.ts
│   └── __tests__/        ← 组件测试(Vitest)
│
├── lib/               ← 非 UI 的逻辑/工具(多为服务端)
│   ├── supabase/
│   │   ├── client.ts         浏览器端 anon 单例客户端(前端用,只读公开 key)
│   │   └── admin.ts          服务端 service_role 客户端 + getUserFromToken(顶部 import "server-only")
│   └── auth/
│       ├── root.ts           "根账号"判定(受保护、不可删/降权)
│       └── require-admin.ts  后端鉴权闸:解析 Bearer token、校验 admin(就是发 401/403 的地方)
│
├── public/            ← 静态资源,按原样对外暴露(各种 .svg)
├── test-stubs/        ← 测试桩
│   └── server-only.ts    把 "server-only" 这个包替换成空壳,好让 vitest 能 import 服务端模块
│
├── .next/             ← 构建产物(自动生成,别手改)
├── node_modules/      ← 依赖(自动生成)
└── 配置文件:
    package.json        脚本(dev/build/test/lint/check-types)+ 依赖
    next.config.js      Next.js 配置
    tsconfig.json       TypeScript 配置
    eslint.config.js    Lint 规则(--max-warnings 0,零容忍)
    vitest.config.ts    测试配置;vitest.setup.ts 测试前置(如 jest-dom)
    next-env.d.ts       Next 自动生成的类型声明
    .env.local          机密配置(Supabase URL/key,gitignore);.env.local.example 是模板
```

## 三个最该记住的设计

**① `app/` 很薄,UI 全在 `components/atlas/`**
`app/page.tsx` 只有三行——`return <AtlasApp />`。Next 的 `app/` 负责"路由 + 后端",真正的界面是一棵从 `AtlasApp` 往下的组件树。所以想改界面去 `components/atlas/`,想改接口去 `app/api/`。

`★ Insight ─────────────────────────────────────`

- **App Router 是"约定式路由"**:`app/` 下的**文件夹名就是 URL 路径**,`route.ts` = 该路径的后端接口,`page.tsx` = 该路径的页面,`[id]` 这种方括号 = 动态参数(对应 `/api/admin/users/某个id`)。不用手写路由表。
- 这个项目几乎是"单页应用塞进一个路由":只有 `/` 一个页面,页面内部靠 `nav-context` 自己切屏(聊天/工作台/资料/用户管理),而不是靠 URL 跳转。
  `─────────────────────────────────────────────────`

**② 前端 / 后端的安全边界**

- **浏览器侧**:`components/**` + `lib/supabase/client.ts`,只拿得到公开的 `NEXT_PUBLIC_*`(anon/publishable key)。
- **服务端侧**:`app/api/**` + `lib/supabase/admin.ts` + `lib/auth/require-admin.ts`,才能读 `SUPABASE_SERVICE_ROLE_KEY`(超级权限)。

`★ Insight ─────────────────────────────────────`

- `lib/supabase/admin.ts` 顶部那行 `import "server-only"` 是**编译期保险丝**:一旦哪个前端组件不小心 import 了它,构建直接报错——从机制上防止把 service_role 密钥泄进浏览器。这就是为什么 `test-stubs/server-only.ts` 要存在:测试环境没有真正的服务端,得用空壳替身才能 import 这些模块跑单测。
- 你之前的 401 正是这条边界在起作用:前端带着失效 token 调 `app/api/admin/users`,服务端的 `require-admin.ts` 把它挡在门外。
  `─────────────────────────────────────────────────`

**③ 测试就近放**
组件测试在 `components/atlas/__tests__/`,而接口/库函数的测试(`route.test.ts`、`require-admin.test.ts`)直接和源码放同一目录——`.test.ts` 紧挨着被测文件。这是这个仓库 TDD 的习惯。

需要我针对某一块(比如 `auth/` 整条登录链路,或 `app/api` 的请求流转)再往下钻一层吗?
