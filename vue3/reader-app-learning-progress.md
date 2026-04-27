# Vue3 阅读器项目 · 学习进度快照

> **Snapshot 时间**：2026-04-27
> **Claude Code Session 名**：`reader-vue-learning`
> **恢复方式**：在 `/Users/a114514/reader/` 目录下运行 `claude --resume`，选择 `reader-vue-learning`

---

## 项目背景

把 `reader_uiux/` 下的 React 高保真原型，迁移到一个 **Vue3 跨端工程**，同时作为本人**学习 Vue3 的载体**。

原型本身是 React + Babel Standalone 零构建的视觉参考，定位是"设计资产源"，不是要被搬运的代码资产。

---

## 已确认的根决策

| 决策项 | 选定 |
|---|---|
| 跨端框架 | **uni-app (Vue3) + TypeScript** |
| 构建工具 | Vite（uni-app CLI 模式，**非 HBuilderX**） |
| 包管理 | pnpm |
| 状态管理 | Pinia |
| MVP 范围 | **完整复刻 7 屏**（首页 / 搜索 / 详情 / 阅读器 / 用户中心 / 登录 / 注册） |
| 后端方案 | 纯前端 + Mock 数据（接口预留 `apiClient` 抽象） |
| 发布优先级 | **三端并行**（Android + iOS + 微信小程序） |
| 协作模式 | **教学模式**：用户动手，Claude 指引（Claude 不写实现代码） |

---

## 学习路径（10 站地图）

```
[第 0 站] JS/TS 基础回顾                       ← 当前位置 ⭐
[第 1 站] 单文件组件 .vue 长什么样
[第 2 站] 响应式数据：ref / reactive
[第 3 站] 模板语法：v-if / v-for / v-bind / v-on
[第 4 站] 组件通信：props / emit
[第 5 站] 计算属性 computed + 侦听器 watch
[第 6 站] 组合式函数 composables（useXxx）
[第 7 站] 生命周期 onMounted / onUnmounted
[第 8 站] Pinia 全局状态
[第 9 站] TypeScript 在 Vue 里怎么用
[第 10 站] uni-app 跨端的额外要点
```

**用户选定的推进顺序**：先 JS/TS 回顾 → 第 1 站讲解 → 搭练习环境 → 后续逐站。

每一站讲解模板：**概念 + 最小示例 + 在阅读器项目里的落点**。

---

## 下一步动作（当前阻塞点）⭐

回到 session 后**第一件事**是回答这两个问题：

### 问题 1：ES6+ 自评（给编号即可）

下面 10 条里，哪几条"完全不熟、需要详讲"？

| 编号 | 主题 |
|---|---|
| ① | `let` / `const`（不要 `var`） |
| ② | 箭头函数 |
| ③ | 解构赋值 ⭐（Vue3 里到处是） |
| ④ | 模板字符串 `` `${x}` `` |
| ⑤ | 模块化 `import` / `export` |
| ⑥ | 数组方法 `map` / `filter` / `find` |
| ⑦ | 展开运算符 `...` ⭐ |
| ⑧ | 可选链 `?.` 与空值合并 `??` |
| ⑨ | Promise / `async-await` |
| ⑩ | 简写属性 / 计算属性名 |

回答示例："③⑦⑧" / "全都熟" / "全都需要"。

### 问题 2：TypeScript 接触程度（三选一）

- A. **完全没碰过** → 从"类型是什么"讲起
- B. **看过别人写但自己没用过** → 重点讲在 Vue 里怎么用
- C. **写过一些** → 直接进第 1 站

### 答完之后

- 不熟的条目我逐个详讲 → 完了再进第 1 站
- 全熟则直接进**第 1 站：`.vue` 单文件组件长什么样**

---

## 学习练习环境（第 1 站结束后要搭）

二选一：

- **方式 A**：Vue Playground 在线版 https://play.vuejs.org/（零安装，前 5 站够用）
- **方式 B**：本地 Vite 工程
  ```bash
  pnpm create vite@latest my-vue-lab --template vue-ts
  cd my-vue-lab && pnpm install && pnpm dev
  ```

⚠️ **第 6 站之前不要碰 uni-app 工程**，先把纯 Vue3 学透，避免"语法是 Vue3 的还是 uni-app 的"混淆。

---

## 关键参考资料

| 资源 | 路径 |
|---|---|
| **工程实施计划**（已写好待批） | `/Users/a114514/reader/docs/cc/plans/reader-uiux-twinkling-narwhal.md` |
| React 高保真原型（视觉资产源） | `/Users/a114514/reader/reader_uiux/` |
| 原型主题令牌（直接搬到 Vue3） | `reader_uiux/screens.jsx:4-41` |
| 原型原子组件（11 个） | `reader_uiux/primitives.jsx:4-243` |
| 原型屏幕代码 | `reader_uiux/screens.jsx:46-862` + `auth-screens.jsx:152-337` |
| 原型 mock 数据 | `reader_uiux/data.jsx` |
| **原型用户偏好（必读）** | `reader_uiux/CLAUDE.md` |
| 原型项目说明 | `reader_uiux/README.md` |

---

## 项目"不要做"清单（来自 `reader_uiux/CLAUDE.md`）

- ❌ 不引入 Element Plus / Ant Design Vue / Vant / uView 等通用组件库（会破坏调性）
- ❌ 不重新引入"书签"功能（历史记录已够用，明确删除）
- ❌ 不照抄 React 代码（Hook ≠ ref，组合方式不同）
- ❌ 不用 emoji
- ❌ 不堆砌 data slop（图标 + 文字 + 数字三件套）

---

## 教学模式约束

- 用户动手写代码，Claude **不替代实现**
- 用户写完贴出来，Claude 点评
- 卡住时给**提示**，不直接给答案（除非用户要）
- 每个概念附"在阅读器项目里的落点"，让概念有着陆点
- 简体中文回复

---

## 工程当前状态

- ⛔ 工程目录 `reader_app/` **尚未创建**
- ⛔ 三端 appid **尚未申请**
- ⛔ **零行真实代码**已写
- ✅ 视觉原型 `reader_uiux/` 已完成
- ✅ 工程实施计划已写好（在 `docs/cc/plans/` 下）
- ✅ 学习路径地图已确立

---

## 重要决策点（备忘）

实施计划里有 3 个反直觉决定，回顾时不要忘：

1. **MVP 阅读器默认上下滚动模式**，不做横向翻页动画 —— 小程序端手势 API 受限。
2. **统一用 uni-app CLI**，不用 HBuilderX 做日常开发 —— GUI 工具不利于版本控制和 CI；HBuilderX 仅用于真机调试。
3. **`reader_uiux/` 保留为只读资产**，新工程开在 `reader_app/`，平级目录 —— 原型不动，永远是视觉对照基准。

---

## 已识别的关键工程风险（不要忘）

| 风险 | 应对 |
|---|---|
| oklch 颜色小程序不支持 | 构建期用 `culori` 库预转换为 hex |
| 长章节性能（10k+ 段） | `scroll-view` + 分块渲染 + IntersectionObserver |
| 小程序无法隐藏状态栏 | `navigationStyle: custom` + 自绘顶栏 |
| iOS / Android 安全区不同 | 封装 `useSafeArea()` composable |
| 微信代码包 2MB 主包限制 | 登录/注册/用户中心拆分包 |

---

**📍 回到 session 后的第一句话**：直接回答上面的"问题 1 + 问题 2"，进入 Vue3 学习。
