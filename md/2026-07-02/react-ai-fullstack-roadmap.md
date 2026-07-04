---
name: react-ai-fullstack-roadmap
description: 转行 AI 全栈的系统学习路线(第一阶段主攻 React 前端),含分阶段清单、里程碑、作品集主线
date: 2026-07-02
tags: [学习计划, 前端, react, 全栈, ai, 转行, roadmap]
source: session
---

# 转行 AI 全栈学习路线(第一阶段主攻 React 前端)

## TL;DR

计算机科班(C / 数据结构)转行 **AI 全栈**,每周约 **48h 全职投入**。近期主线:把 **HTML/CSS/JS/TS + React** 打扎实,并把手上的 **turborepo**(`web`=React+Vite / `api`=Hono+Drizzle+SQLite)一步步长成 **AI 全栈作品集**。全职节奏预计 **4–6 个月**到可投简历。稳比快。

## 定位与背景

- **终极目标**:AI 全栈开发工程师。
- **第一步**:先攻一个前端框架 = **React**(理由:Claude Code 擅长、手上项目已是 React、生态与岗位面广)。
- **基础**:计算机专业,学过 C / 数据结构;3 年前学过 Vue(已忘)——编程内核在,缺的是前端特定知识 + 熟练度 + 作品。
- **投入**:约 48h/周(全职级别)。
- **弥补学历短板的关键**:GitHub 作品集 + 真实可访问的线上项目。

## 大图景:你的 turborepo 就是作品骨架

| 仓库中的位置 | 对应全栈的层 | 学习阶段填充 |
|--------------|--------------|--------------|
| `apps/web`(React+Vite) | 前端层 | 阶段 1–5 |
| `apps/api`(Hono+Drizzle+SQLite) | 后端 + 数据库层 | 阶段 6 |
| 之后接入 LLM/Agent | AI 层 | 阶段 6 |

**不是学孤立知识,而是逐层把这个仓库长成一个 AI 全栈产品。** 每一步都通向终极目标 + 直接产出作品集。

## 学习方法(沿用你验证过的习惯)

- **动手为主、先预测后验证**——每个概念先猜结果再跑证据(和学 Vite 时一样)。
- **每阶段用 `/smart:distill` 落盘笔记**到 `~/knowledges/md/<日期>/`。
- **学习模式 `/smart:learning`**:关键代码自己敲、我给标签块 + 审阅(已开启)。
- **善用 Claude Code 辅助**,尤其 React——但坚持自己敲、自己理解,不做复制侠。
- **每阶段结束更新本文件的进度勾选框**,作为长期主线追踪。

## 分阶段清单

### 阶段 1 · HTML + CSS(约 2–3 周)
> 你最可能的短板,认真补。目标:不查资料能手写页面结构与布局。
- [ ] HTML 常用标签、语义化、文档结构
- [ ] CSS 选择器、盒模型(margin/border/padding)
- [ ] **Flexbox 布局**(重点)
- [ ] Grid 布局
- [ ] 响应式(媒体查询、相对单位)
- [ ] 项目:静态个人主页
- [ ] 项目:一个响应式落地页

### 阶段 2 · JavaScript(约 4–6 周 · 核心,最花时间)
> 借你的 C 基础语法速通;重点在 JS 独有的部分。
- [ ] 语法速通:let/const、类型、函数、作用域(对比 C)
- [ ] 数组 / 对象 + map/filter/reduce/forEach
- [ ] **DOM 操作 + 事件监听**
- [ ] **异步:Promise / async-await / fetch**
- [ ] ES6+:解构、展开、箭头函数、模板字符串
- [ ] 模块化:import / export(直接接回 Vite 的 ESM)
- [ ] 进阶理解:闭包、原型链、事件循环
- [ ] 项目:Todo 清单(纯 JS + DOM)
- [ ] 项目:天气查询(调真实 API)
- [ ] 项目:一个原生 JS 小游戏

### 阶段 3 · TypeScript(约 1–2 周)
> 你有 C 的类型概念,好上手;现代前端标配。
- [ ] 基础类型、接口、类型别名
- [ ] 泛型、联合 / 交叉类型
- [ ] 项目:把阶段 2 的项目用 TS 重写

### 阶段 4 · React + 生态(约 6–8 周)
> 有了三大件,JSX/useState 全是"换个写法"。
- [ ] JSX、组件、props
- [ ] useState / useEffect
- [ ] 事件、表单、条件 / 列表渲染
- [ ] 自定义 Hook
- [ ] 路由(React Router)
- [ ] 状态管理(Zustand / Context)
- [ ] 请求封装 + 数据获取
- [ ] UI:Tailwind CSS + shadcn/ui
- [ ] 项目:一个完整 SPA(登录 + 列表 + 详情 + 增删改查)
- [ ] 项目:把 turborepo 的 `apps/web` 扩成真实应用

### 阶段 5 · 工程化 + 部署(约 1–2 周 · 你已入门)
> 你卡住那天想深挖的 Vite 细节,归位在这里。
- [ ] **`vite build` 生产打包**(开发不打包 → 生产切回 Rollup,产物长什么样)
- [ ] **Vite 插件机制**(`plugins: [react()]` 的 `react()` 到底做了什么)
- [ ] turbo monorepo 进阶(watch 开发流等,你的原定进阶计划 1)
- [ ] 环境变量、多环境配置
- [ ] Git 分支协作、PR 流程
- [ ] 部署到 Vercel(拿到真实可访问网址)

### 阶段 6 · 迈向 AI 全栈(前端稳固后展开)
> 把作品骨架补齐后端 + AI 层。
- [ ] Node 后端 + API 设计(Hono,你项目已有)
- [ ] 数据库(SQLite/Postgres + Drizzle,已有)
- [ ] LLM API 集成(Claude / OpenAI)、流式输出
- [ ] Vercel AI SDK、prompt、RAG、Agent 入门
- [ ] 项目:一个完整 AI 应用(把 turborepo 长成带 AI 能力的产品)

### 阶段 7 · 求职冲刺
- [ ] 打磨 2–3 个作品、写好 README
- [ ] 面试八股(HTML/CSS/JS/React/网络/浏览器)
- [ ] 算法刷题(借你的数据结构底子)
- [ ] 简历 + 投递

## 里程碑(按 48h/周估算 · 仅供参考,稳比快)

- **第 1 月**:阶段 1(HTML/CSS)+ 阶段 2 起步(JS 基础与 DOM)
- **第 2–3 月**:阶段 2 深入(异步/模块化)+ 阶段 3(TS)+ 阶段 4 入门
- **第 4 月**:阶段 4 生态 + 完整 SPA + 阶段 5 部署上线
- **第 5–6 月**:阶段 6(AI 全栈项目)+ 阶段 7(求职冲刺)

## References

- **前置知识**:pnpm+turbo 基础(`~/knowledges/md/2026-06-20/`)、Vite 三模块(`~/knowledges/md/2026-07-02/vite-dev-esm-hmr-turbo.md`)
- **主参考**:MDN Web Docs(基础权威)、JavaScript.info(JS 圣经)、react.dev(React 官方)、Tailwind / shadcn 官方文档
- **作品骨架**:手上的 `turborepo_learning` 仓库
- **下一步**:从阶段 1 · HTML+CSS 开始
