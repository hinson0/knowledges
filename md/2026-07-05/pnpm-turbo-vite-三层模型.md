# pnpm / turbo / vite —— 三层心智模型(capstone)

> 2026-07-05 自己做总结后提炼。用来一眼回忆"这三个工具到底各管什么、怎么协作"。
> 细节见:`vite-生产打包与dev-prod闭环.md`(2026-07-04)、`vite-插件机制-react插件.md`、`turbo-watch-monorepo开发流.md`(均 2026-07-05)。

## 一句话总纲

**pnpm 管【包】、turbo 管【任务】、vite 管【某个 app】;下层给上层铺路 —— pnpm 建图 → turbo 用图排任务 → vite 干具体 app 的活。**

## 分层图

```
pnpm    ← 最底层:管【包】
  │        · 有哪些包(由 pnpm-workspace.yaml 的 globs 定义)
  │        · 每个依赖从哪来:workspace:* 用本地包(建软链)vs 版本号从 registry 下载
  │        · 真正装好、建好 node_modules 里的软链
  │        ⇒ 产出:一张"包依赖图"(谁依赖谁)
  │
turbo   ← 中间层:管【任务】
  │        · 【读】pnpm 建立的那张包依赖图(自己不建图)
  │        · 用 turbo.json 的 dependsOn(如 ^build)把图翻译成"任务先后顺序"
  │        · 并行调度 + 缓存(FULL TURBO,输入没变就跳过)
  │        ⇒ 谁先 build 谁后 build、起服务前先把上游依赖补齐,都归它
  │
vite    ← 最上层:只管【单个前端 app 怎么跑/怎么发布】
           · dev server(`vite`):开发时的 web 服务器,实时编译 + HMR,【不打包】
           · build(`vite build`):为发布用 Rollup 打包/转译/压缩/哈希 → dist/
           · preview(`vite preview`):打包后本地预览成品(配套小助手)
```

## 三个易混点(自查)

| 疑问 | 答案 |
|---|---|
| "谁依赖谁"这张图是谁建的? | **pnpm**(靠 workspace 协议)。turbo 只是**读**它,不建。 |
| turbo 管的是"包依赖"还是"任务"? | **任务**。包依赖是 pnpm 的事;turbo 用包依赖图去**排任务顺序**。 |
| vite 是不是也管 monorepo? | 不。vite 只关心**它负责的那一个 app**;跨包协调(改 @repo/ui 传导到 web)是 **turbo + 各包 watch** 的事。 |

## 落到本仓库的具体例子

- `apps/web` 依赖 `@repo/ui`、`@repo/shared` → 这层关系是 **pnpm** 用 `workspace:*` 建的软链。
- `turbo run dev --filter=@repo/web...` → **turbo** 读到"web 依赖 ui/shared",于是先 build 上游、再并行起各包 dev。
- web 这个 app 本身怎么开发跑、怎么打包 → 全是 **vite** 的活;它消费的是 `@repo/ui` 的 **dist 产物**(不是源码)。
