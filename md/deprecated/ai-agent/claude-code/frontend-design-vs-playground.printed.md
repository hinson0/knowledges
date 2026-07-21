# frontend-design vs playground

两个插件名字都和"前端/UI"沾边，但定位完全不同：一个是"给别人用的界面生成器"，另一个是"给自己探索的交互工具生成器"。

关键区分点是**产物的作用对象**：

- `frontend-design` 的产物是**交付给终端用户**的正式产品
- `playground` 的产物是**你自己调参**后把配置结果当 prompt 喂回给 Claude

## 对比表

| 维度 | `frontend-design` | `playground` |
|------|-------------------|--------------|
| 目的 | 生成生产级前端界面 | 生成单文件交互探索工具 |
| 产物 | React/Vue/HTML 组件、页面、完整应用 | 一个自包含 HTML（控件 + 实时预览 + prompt 输出框 + 复制按钮） |
| 用户 | 给**终端用户**看的成品 UI | 给**你自己**用来调参、探索设计空间 |
| 核心价值 | 避免"AI 味"的平庸设计（字体/配色/动效/排版有"态度"） | 把难以用文字描述的参数（大小/颜色/结构）用视觉控件代替 |
| 输出规模 | 完整组件库、整页面、多文件 | 单 HTML 文件，内联所有 CSS/JS，无外部依赖 |
| 触发场景 | "帮我做一个登录页 / 仪表板 / landing page" | "做个探索工具给我试 border-radius/shadow/间距组合"、"做个 SQL 查询沙盒"、"做个概念地图" |
| 模板 | 无模板，基于美学指南自由发挥 | 6 个固定模板（design-playground、data-explorer、concept-map、document-critique、diff-review、code-map） |
| 关键产出 | 直接可部署的代码 | 一个会输出"自然语言 prompt"的 HTML，用户调完参数复制 prompt 再喂回 Claude |

## 一句话区分

- **`frontend-design`**：做 **"最终的 UI"** —— 设计、实现、交付
- **`playground`**：做 **"探索 UI 的 UI"** —— 让你在浏览器里调参，调完把选择转成 prompt 再让 Claude 实现

## 对 React Native 移动端项目的相关性

- `frontend-design` 明确定位 "web components, pages, or applications"；React Native 移动端不匹配 → **可禁用**
- `playground` 是跨领域工具（data-explorer / concept-map / diff-review 这些和前端无关），做可视化调试/学习工具都用得上 → **保留**

## 实际例子

| 需求 | 该用哪个 | 产物 |
|------|----------|------|
| "做一个记账卡片组件" | `frontend-design` | 直接给你 React 组件代码 |
| "我想试不同字号 + 圆角 + 阴影的组合，看哪种记账卡片好看" | `playground` | 带 slider 的 HTML，调好后复制 "使用 14px 字号、12px 圆角、柔和阴影" 这句 prompt 再喂回来 |

## `playground` 的 6 个模板速查

| 模板 | 用途 |
|------|------|
| `design-playground` | 视觉设计决策（组件、布局、间距、颜色、排版） |
| `data-explorer` | 数据和查询构建（SQL、API、管道、正则） |
| `concept-map` | 学习和探索（概念地图、知识盲点、范围定义） |
| `document-critique` | 文档审阅（带 approve/reject/comment 工作流的建议） |
| `diff-review` | 代码审查（git diff、commit、PR 的逐行评论） |
| `code-map` | 代码库架构（组件关系、数据流、分层图） |
