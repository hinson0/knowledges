Vite 里的 **HMR** 是：

> **Hot Module Replacement，热模块替换**

意思是：**开发时你改了代码，浏览器不整页刷新，只更新变化的那一小块模块。**

例如你改了 React 组件：

```tsx
function App() {
  return <div>Hello Vite</div>;
}
```

保存后，Vite 不会重新刷新整个页面，而是只把这个组件模块替换掉。

## 它解决什么问题？

没有 HMR 时：

```text
改代码
↓
浏览器整页刷新
↓
页面状态丢失
↓
重新登录 / 表单清空 / 弹窗关闭
```

有 HMR 时：

```text
改代码
↓
只更新变动模块
↓
页面尽量保持原状态
```

比如你页面上有计数器：

```tsx
const [count, setCount] = useState(10);
```

你改了按钮样式，HMR 后 `count` 可能还保持在 `10`，不会因为整页刷新变回初始值。

## Vite 的 HMR 大概怎么工作？

```text
你改文件
↓
Vite dev server 监听到变化
↓
通过 WebSocket 通知浏览器
↓
浏览器重新加载变动的 ESM 模块
↓
页面局部更新
```

Vite 开发环境是基于 **原生 ESM** 的，所以它能很细粒度地知道哪个模块变了。

## 和普通刷新区别

| 类型     | 行为             | 状态         |
| -------- | ---------------- | ------------ |
| 普通刷新 | 整个页面重新加载 | 状态丢失     |
| HMR      | 只替换变动模块   | 状态尽量保留 |

## React 项目里的 HMR

Vite + React 里通常靠这个插件处理：

```ts
import react from "@vitejs/plugin-react";

export default {
  plugins: [react()],
};
```

它背后用的是 **React Fast Refresh**，所以你改 React 组件时，能做到热更新并尽量保留组件状态。

## 注意

HMR 不是永远都能局部更新。

如果 Vite 判断这个模块不能安全热替换，就会退回到：

```text
full reload
```

也就是整页刷新。

总结一句：

> **HMR 就是开发时的“局部热更新”：改哪里，尽量只更新哪里，不重刷整个页面。**
