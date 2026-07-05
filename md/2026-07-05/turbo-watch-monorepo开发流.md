# Turbo watch / monorepo 开发流

> 模块 3 学习笔记 · 2026-07-05 · 承接 [[vite-生产打包与dev-prod闭环]]、[[vite-插件机制-react插件]]

## 0. 一句话总纲(先记这个)

- monorepo 里,app 和它依赖的共享包之间**隔着一层"编译产物"**。改了共享包**源码**,必须有人把它**重编成产物**,下游 app 才看得到。
- 让改动自动传导,有两种 watch 思路:
  - **`turbo run dev`** = 各包自带 watch(`tsc --watch`/`vite`),turbo 帮你**一起开**。**← 日常开发首选**。
  - **`turbo watch <task>`** = turbo **亲自盯文件**、按依赖图**重跑普通任务**(2.x 新功能,去抖弱,偶尔多跑一次但无害)。
- 一切"先谁后谁"都由 `turbo.json` 的依赖图 `dependsOn: ["^build"]` 决定;同一张图,喂 `run` 是一次性构建,喂 `watch` 是增量重跑。

---

## 1. monorepo 的核心矛盾:为什么需要 watch 开发流

本仓库 `@repo/web` 这样用共享包:

```
web 的 import  →  解析到  @repo/ui 的 dist/index.js(编译产物)
                            ↑ 不是 packages/ui/src/*.tsx 源码!
```

**推论**:你改了 `packages/ui/src/Button.tsx`(源码),但**没人重编 `@repo/ui/dist`**,web 读到的就还是旧产物 → 改动看不见。

> 单包项目没这毛病:改源码 → vite 直接看到源码 → HMR。**是"多包 + 编译产物这一层"制造了这个矛盾。**

**一句话记住**:你改的是"设计图"(src),web 读的是"成品"(dist);成品没重新生产,web 当然看到旧的。

---

## 2. 亲手复现"卡住"

步骤:
1. 只跑单个 web 的 dev:`pnpm --filter @repo/web dev`(只有 web 的 vite,没人管 ui)。
2. 改 `packages/ui/src/Button.tsx` 的 `background`:`#1890ff` → `red`,存盘。
3. 看浏览器里 "➕ 添加用户" 按钮(它是 `@repo/ui` 的 `<Button>`)。

**现象**:按钮**没变色,还是蓝的**。

**铁证**(grep 源码 vs 产物):

| 文件 | 内容 | 说明 |
|---|---|---|
| `packages/ui/src/Button.tsx`(源码) | `background: "red"` | 你改了 |
| `packages/ui/dist/Button.js`(产物,web 真正读的) | `background: "#1890ff"` | 还是旧的! |
| `dist/Button.js` 修改时间 | 停在老早以前 | 证明 dist 根本没重建 |

---

## 3. 用 turbo 修好(dev 流)

```bash
turbo run dev --filter=@repo/web...
```

- 末尾**三个点 `...`** = `@repo/web` **和它依赖的所有包**(web + @repo/ui + @repo/shared),把范围收窄。
- turbo **并行**跑各包的 `dev`:
  - `@repo/ui` / `@repo/shared` 的 `dev` = `tsc --watch`(一直盯源码,一改就重编 dist)
  - `@repo/web` 的 `dev` = `vite`

再改一次 ui 源码(red → green),浏览器里按钮**自动变绿、不用刷新**。传导链:

```
你改 ui 源码(Button.tsx)
  → @repo/ui 的 tsc --watch 侦测到,重编 dist/Button.js
    → web 的 vite 发现依赖的 dist 变了,触发 HMR
      → 浏览器按钮自动变绿(不刷新)
```

**turbo 的功劳**:一条命令,把整条链上每个包的 watcher **按依赖顺序**一起拉起来、并排盯着。

---

## 4. `turbo run dev` vs 真正的 `turbo watch <task>`(核心区分)

模块名叫 "turbo watch",但日常修 bug 用的其实是 `turbo run dev`。两者是**两种不同思路**:

| | `turbo run dev`(常用) | `turbo watch <task>`(namesake,2.x 新功能) |
|---|---|---|
| 谁在 watch | **各工具自己**:ui=`tsc --watch`、web=`vite` | **turbo 自己**盯文件系统 |
| 跑的任务 | 长驻任务(`turbo.json`:`persistent:true, cache:false`) | 普通一次性任务(如 `build`=`tsc`) |
| 改文件后 | 各工具自己增量重建 + vite 给 HMR | turbo 侦测 → **按依赖图重跑**那个任务 |
| 例子 | `turbo run dev --filter=@repo/web...` | `turbo watch build` → 改 ui/src,先重跑 `ui#build`,再重跑 `web#build` |
| 适合 | 工具本身有 watch/HMR(如 vite)→ **日常开发首选** | 工具没 watch 模式,或想整条链重建/重测 |

**一句话记住**:
- `turbo run dev` = "**各包自带 watch,turbo 帮你一起开**"。
- `turbo watch` = "**turbo 亲自当那个 watcher,按依赖图重跑普通任务**"。

> 两者都靠 `turbo.json` 的依赖图 `dependsOn: ["^build"]` 决定"先 ui 后 web"。**同一张图:喂 `run` 是一次性构建,喂 `watch` 是增量重跑。**

---

## 5. 排查案例:改一次颜色,为什么 web 构建了 2 次?⭐

### 现象
一次改色 → 终端里 `$ tsc && vite build`(web#build)出现 **2 遍**,而且两遍产出**同一个哈希** `index-DybP_P8n.js`(→ 第 2 遍是白干,输入其实没真变)。

### 立假设(先别急着下结论)
- **假设 A**:纯产物级联 → 预期 `ui×1 / web×2`。
- **假设 B**:编辑器双写(原子保存) → 预期 `ui×2 / web×2`。

### 对照实验(绕开编辑器)
用 python `open(p,'w')` 对 `Button.tsx` 做**单次原地写入**(不经编辑器),结果:

```
@repo/ui:build:  cache miss ×2   ← 两个【不同】输入哈希 50170d18… / ca54ef09…
@repo/web:build: cache miss ×2
✓ built in       ×2
```

### 定案
- **不是依赖图错**:turbo 每次都规矩地"先 ui 后 web"。
- **也不能单赖编辑器**:脚本写入一样触发。
- **真因**:**"保存文件"这个动作本身,几乎从来不是单个文件系统事件**——
  - python 的 `open('w')` = 先**截断清空** + 再**写入** = 两个事件;
  - 编辑器"原子保存" = 写临时文件 + 改名覆盖 = 也是多个事件。
- `turbo watch` 对**每个事件**都反应一次,把 `ui → web` 这条链**各重跑一遍** → `ui×2 + web×2`。
- **铁证**:两次 `ui#build` 的输入哈希**不同** = turbo 确实读到了文件的两个不同状态(截断的空窗态 + 写满态)。

### 结论
- **冗余但无害**:最后一次构建拿的是正确内容、产物正确、依赖顺序正确。只是白干了一轮。
- 这是 `turbo watch`(2.x 较新)**去抖(debounce)没 vite 老练**的一个毛刺。

### 连带两个工程概念
- **原子保存**:编辑器先写临时文件再改名,避免别人读到"写了一半"的残缺文件。代价是产生多个文件事件。
- **去抖 debounce**:成熟的文件监听器侦测到变化后等几十毫秒,把一簇事件**合并成一次**再触发。

### 方法论 meta(比结论更值钱)
**先立假设 → 做对照实验 → 让数据纠正你**,而不是嘴上分析。这次实验就推翻了"假设 A / 赖编辑器"两种想当然。

---

## 附:模块 3 一图流

```
                       turbo.json 依赖图 (dependsOn: ["^build"])
                                    │
              ┌─────────────────────┴─────────────────────┐
        喂给 turbo run                                喂给 turbo watch
              │                                             │
   各包自带 watch 一起开                        turbo 亲自盯文件、按图重跑
   (ui: tsc --watch / web: vite)               (turbo watch build → ui#build → web#build)
              │                                             │
     改 ui 源码 → 重编 dist → vite HMR              改 ui 源码 → 依赖图增量重跑
     日常开发首选,去抖成熟                        较新,去抖弱,偶尔多跑一次(无害)
```

**monorepo 一句话**:app 隔着一层编译产物,改共享包源码要有人重编产物、下游才看得到;turbo 的价值就是拿着那张依赖图,把"谁先谁后、谁跟着谁重建"安排明白。
