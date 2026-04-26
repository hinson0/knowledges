# `/ecc:frontend-design` 技能

> 反"AI 感"UI 的前端设计技能。核心理念：选一个方向，彻底执行。安全平庸的 UI 通常比有强烈风格的 UI 更差。

## 解决的问题

普通 AI 生成前端的典型问题：
- 居中 headline + 渐变 blob + 通用 CTA
- 均匀间距卡片网格，毫无层次
- 随机 hover 动效
- 默认 Tailwind/shadcn 风格，千篇一律

`/ecc:frontend-design` 强制在写代码前先想清楚视觉方向。

## 使用时机

- 从零构建 landing page、dashboard、app shell
- 把平庸界面升级为有设计感的产品
- 将产品概念转化为具体视觉方向
- 字体、排版、动效同样重要的场景

## 工作流（4步）

```
1. Frame（定框架）   → 目的 / 受众 / 情感基调 / 视觉方向 / 记忆点
2. System（建系统）  → 字体层级 / 颜色变量 / 间距节奏 / 动效规则
3. Compose（排版）   → 有意识的不对称 / 重叠 / 留白
4. Motion（动效）    → 只在有意义的地方加动效，不撒胡椒粉
```

## 可选视觉方向（选一个，别混）

| 风格 | 适合场景 |
|------|----------|
| brutally minimal | 工具类产品 |
| editorial | 内容 / 媒体平台 |
| luxury | 高端品牌 |
| retro-futurist | 科技感产品 |
| geometric | 数据 / 分析产品 |
| playful | 消费类 / 娱乐 |
| soft & organic | 健康 / 生活方式 |

## 强制规范

### 字体
- 选有个性的字体，避免通用默认
- 展示字体 + 正文字体搭配（设计导向页面）

### 颜色
- 明确的色板，一个主色域 + 少量强调色
- 避免紫色渐变白底（已是 AI UI 陈词滥调）

### 背景
- 用 atmosphere：渐变 / mesh / 纹理 / 噪点 / 透明度叠加
- 纯平背景很少是最好答案

### 布局
- 适时打破网格（对角线、偏移、分组）
- 即使布局非常规，阅读流向也要清晰

## 禁止模式（Anti-Patterns）

- ❌ 可互换的 SaaS hero section
- ❌ 无层次的通用卡片堆
- ❌ 没有系统的随机强调色
- ❌ 占位符感的字体排版
- ❌ 只因为好加而加的动效

## Quality Gate（交付前自检）

- [ ] 界面有明确的视觉观点
- [ ] 字体和间距感觉是有意为之的
- [ ] 颜色和动效支撑产品，而非随意装饰
- [ ] 不像 AI 生成的 UI
- [ ] 生产级实现，不只是视觉上有趣

## 与其他规则的关系

- 遵循 `rules/web/design-quality.md` 的反模板政策
- 遵循 `rules/web/performance.md` 的 CWV 指标
- 动效只用 compositor-friendly 属性（transform / opacity / clip-path）

## 典型调用

```bash
# 从零构建
"帮我做一个数据仪表盘" → /ecc:frontend-design

# 升级现有 UI
"这个页面太普通了，帮我做得有设计感" → /ecc:frontend-design
```
