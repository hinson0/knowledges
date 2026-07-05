# Vite 插件机制 —— `react()` 到底做了什么

> 模块 2 学习笔记（2026-07-05）。配套上一篇《Vite 生产打包 与 dev↔prod 闭环》(模块1)。

## 0. 一句话总纲（先记这个）

**Vite 插件 = 一组挂在构建生命周期"钩子(hook)"上的函数。** Vite 在关键节点挨个调用它们、把文件源码交到你手里、用你的返回值替换。`react()` 就是其中一个,拆开是两个子插件:
- `vite:react-babel` —— 翻译 JSX + 自动补 import + dev 加调试信息
- `vite:react-refresh` —— 热更新保状态(Fast Refresh)

---

## 1. `react()` 不是魔法

Vite 核心只管两件事:**编译 + 伺服**。至于"怎么处理 React / Vue / Svelte",核心一律不管,全交给**插件**在各个钩子上"插一脚"。

`vite.config.ts` 里那行 `plugins: [react()]`,就是把 React 相关的处理挂进 Vite。之前默认接受、没追问的那些现象(不写 `import React` 也能用 JSX、报错能定位到源码第几行、改代码不刷新还保状态),**全是这一个 `react()` 变出来的**。

## 2. `react()` 返回的是插件**数组**(不止一个)

- 类型签名:`function viteReact(): Plugin[]` —— 返回的是插件**数组**。
- grep 它源码,有**两个** `name`:

| name | 管什么 |
|---|---|
| `vite:react-babel` | 翻译(JSX→JS、补 import、dev 调试信息) |
| `vite:react-refresh` | 热更新保状态 |

所以 `plugins: [react()]` 其实展开成 `[react-babel, react-refresh]`,Vite 再把数组摊平。

> **一句话记住:** 一次 `react()` 调用塞进俩插件——"一个函数返回多个插件"是插件常见的打包手法。

## 3. 插件的最小形态

一个插件,本质就是一个**普通对象**:

```js
{
  name: "插件名",            // 必填,报错时用来显示是谁干的
  transform(code, id) {      // 一个"钩子":每个文件经过 Vite 时被调用一次
    // code = 这个文件的源码(字符串)
    // id   = 这个文件的路径
    return 改写后的code;      // 你 return 什么,Vite 就用什么替换掉该文件
  }
}
```

> **一句话记住:** 插件的核心就是"钩子函数"。`transform` 每个模块调用一次,`return` 什么就用什么替换。

## 4. `react-babel` 在 `transform` 里干的三件事

用 dev 下 `curl http://localhost:3000/src/App.tsx` 得到的真实改写结果佐证:

1. **翻译 JSX**:`<h1>...</h1>` → `jsxDEV("h1", { children: ... })`。浏览器根本不认识 JSX 尖括号,**必须**转成函数调用才能跑。这是最核心的活。
2. **自动补 import**:在文件顶部凭空补上 `import jsxDEV from "react/jsx-dev-runtime"`。这叫 **automatic JSX runtime**,是现代 React **不用再手写 `import React`** 的原因——不是魔法,是插件替你补的。
3. **dev 专属·调试信息**:额外挂 `transform-react-jsx-self` / `transform-react-jsx-source` 两个 babel 小插件,给每个 `jsxDEV(...)` 补上 `fileName` / `lineNumber`。组件报错时,React 能告诉你"错在 App.tsx 第 70 行"。

真实产物片段:
```js
import jsxDEV from ".../react_jsx-dev-runtime.js";     // ← ② 没人写这行,插件补的
...
jsxDEV("h1", { children: "🏗️ ..." }, ..., {
  fileName: ".../App.tsx", lineNumber: 70              // ← ③ 报错定位
})
```

> **连回模块1:** 生产 `build` 时**不挂**那两个 dev 插件,且用 `jsx`(不是 `jsxDEV`)+ 压缩。这正是模块1观察到"dev 有调试信息、生产没有"的**根因**——同一个 `react()`,看你在 dev 还是 prod,给两套不同翻译。

## 5. `react-refresh` = Fast Refresh(热更新保状态)

`vite:react-refresh` 往每个组件文件注入这些东西:
```js
import * as RefreshRuntime from "/@react-refresh";
window.$RefreshReg$ = RefreshRuntime.getRefreshReg(".../App.tsx");
var _s = $RefreshSig$();
if (!window.$RefreshReg$) throw new Error("...can't detect preamble...");  // 自检
```
并通过 **`transformIndexHtml` 钩子**往 `index.html` 注入一段初始化 preamble(所以有上面那句自检)。

**效果对比:**

| 操作 | 结果 |
|---|---|
| 改一个组件代码存盘(Fast Refresh) | 只热替换那块,**保住组件 state**(计数器停在 5 不归零、页面不整体刷新) |
| 手动按 F5 刷新 | 一切重来,**state 清零**(计数器回到 0) |

> **一句话记住:** Fast Refresh = 改代码只换那块 + 保住 state;这就是 `react-refresh` 每天帮你干的活。

## 6. 动手验证:我自己写的最简插件

在 `apps/web/vite.config.ts` 里写了个"只打印、不改动"的插件:
```ts
function myLogger() {
  return {
    name: "my-logger",
    transform(code: string, id: string) {
      if (id.endsWith(".tsx")) console.log("🔌 my-logger 处理了:", id);
      return code; // 原样返回
    },
  };
}
// plugins: [react(), myLogger()]
```
重启 dev + 刷新页面后,终端打印:
```
🔌 my-logger 处理了: .../src/main.tsx
🔌 my-logger 处理了: .../src/App.tsx
```

> **结论(整个模块的钥匙):** 插件 = Vite 在处理每个模块时调用的函数。`react()` 用的是**同一套机制**,唯一区别是:`react()` 的 `transform` `return` 翻译后的代码,我的 `myLogger` `return` 原样。搞懂这 8 行,就搞懂 `react()` 了。

## 7. 细节:为什么只打印 `main/App`,没有 `Button/Card`?

日志里**只有 `main.tsx`、`App.tsx`,没有 `Button.tsx`/`Card.tsx`**。因为 `@repo/ui` 是以**编译好的 `dist/index.js`**(不是 `.tsx` 源码)被引入的:
```js
import { Button, Card } from "/@fs/.../packages/ui/dist/index.js";
```
`.js` 不匹配 `id.endsWith(".tsx")`,所以被跳过。

> **连回 monorepo:** web 用的是 `@repo/ui` 的**构建产物**,不是它的源码。

## 8. TS 小坑 + 连回模块1:dev 不查类型,build 才查

- 写 `transform(code, id)` 时 IDE 报 `ts(7006):参数隐式具有 any 类型`(项目开了严格模式)。
- **修法**:标注 `transform(code: string, id: string)`,或把工厂函数返回类型标成 `Plugin`(`import { type Plugin } from "vite"`)。

> **关键反差(务必记住):** 这条红线是 `tsc` 在把关。
> - `pnpm build` = `tsc && vite build` → **会卡在 tsc**,过不去。
> - `pnpm dev` → **照跑不误**,因为 dev 用 esbuild,只"扒掉类型"不做类型检查。
>
> 所以 **"编辑器/tsc 报红" ≠ "dev 跑不起来"**;**dev 不查类型,build 才查类型。**

---

## 附:模块 2 一图流

```
react()  →  返回 [react-babel, react-refresh]  (Plugin[])
             │
  react-babel ── transform 钩子:
             │     ├─ JSX <h1> → jsxDEV("h1",{...})      (浏览器不认 JSX)
             │     ├─ 自动补 import jsx-runtime           (不用写 import React)
             │     └─ dev 专属:加 fileName/lineNumber     (build 时去掉)
             │
  react-refresh ── transform 钩子:注入 $RefreshReg$/_s()  (热更新保 state)
                └─ transformIndexHtml 钩子:注入 preamble  (到 index.html)

插件机制本质 = Vite 在构建钩子上挨个调用你的函数,把文件交给你,用你的返回值替换。
```
