# `/feature-dev:feature-dev` 工作流

## 定位

来自官方插件 `feature-dev@claude-plugins-official`，是一个**引导式功能开发工作流 command**。不是 skill，而是 **slash command**（`/feature-dev:feature-dev`）。

核心价值：**把"AI 帮我写代码"从一句话变成一套有阶段、有卡点、有并行审查的协作模式**。

## 整体结构：7 个 Phase

| Phase | 目标                    | 关键动作                                              | 用户确认点         |
| ----- | ----------------------- | ----------------------------------------------------- | ------------------ |
| 1     | Discovery（理解需求）   | 建 TodoList；功能不清就问问题                         | 确认理解          |
| 2     | Codebase Exploration    | **并行 2-3 个 code-explorer agent** 从不同角度探索    | —                  |
| 3     | Clarifying Questions    | 汇总歧义点、边界、错误处理，**列表式提问**            | ✅ **等用户回答**   |
| 4     | Architecture Design     | **并行 2-3 个 code-architect agent** 给多方案对比     | ✅ **等用户选方案** |
| 5     | Implementation          | 实现代码                                              | ✅ **必须等批准**   |
| 6     | Quality Review          | **并行 3 个 code-reviewer agent**（简洁/bug/约定）     | ✅ **修/不修决策**  |
| 7     | Summary                 | 关闭 TodoList，总结决策、修改、下一步                 | —                  |

## 核心设计哲学

### 1. 多 Agent 并行 = 多视角探索

每个 Phase 不是单个 AI 思考，而是**并行启动 N 个子 agent**，每个关注不同方面：

- **Phase 2 探索**：agent #1 找类似功能、#2 理解架构、#3 分析现有实现、#4 看 UI/测试模式
- **Phase 4 架构**：agent #1 最小改动方案、#2 优雅架构、#3 速度 + 质量平衡
- **Phase 6 审查**：agent #1 简洁/DRY、#2 bug/正确性、#3 项目约定

这比让一个 AI "自己想全面"更可靠——**不同 agent 各自深挖，互相独立**。

### 2. 强制用户卡点（Human-in-the-loop）

关键词 "DO NOT START WITHOUT USER APPROVAL" 在 Phase 5 明确写出。Phase 3/4/6 也都要等用户。

这是有意的"慢下来"——避免 AI 在"可能走错方向"的地方一路狂奔。

### 3. TodoWrite 全程跟踪

7 个 phase 都在 TodoList 里，用户随时能看到进度。

### 4. 读 Agent 推荐的文件

Phase 2 要求 code-explorer agent "返回一个 5-10 个关键文件列表"，主 agent 再把这些文件**真的读一遍**，不是只看 agent 的摘要。

## 配套的 3 个 Agent（同插件提供）

| Agent              | 使命                               |
| ------------------ | ---------------------------------- |
| `code-explorer`    | 深度追踪现有代码的架构、抽象、控制流 |
| `code-architect`   | 设计实现方案，考虑 trade-offs      |
| `code-reviewer`    | 审查简洁性、bug、项目约定合规       |

这 3 个 agent 装了 plugin 就会**自动被主会话关键词触发**——不一定非走 `/feature-dev:feature-dev` 命令才能用。

## 适合什么场景

### 适合

- **中大型新功能**（设计空间大，需要多方案对比）
- **不熟的代码库**（Phase 2 会帮你探索）
- **需求不明确**（Phase 3 的 clarifying questions 会逼你想清楚）
- 希望留下决策痕迹（Phase 7 的 summary）

### 不适合

- **琐碎的改动**（三行代码的 typo 修复，走完 7 个 phase 是过度）
- **紧急热修**（AD 流程太慢）
- **只需要探索，不实现**（直接用 code-explorer agent 即可）
- **严格 TDD 开发**（Phase 5 是整体实现，与 TDD 的 Red-Green-Refactor 小步快跑有架构张力）

## 与其他工具的协作位置

```
需求              探索代码          设计/实现              自审                提交管道
  │                 │                   │                    │                    │
  │   code-        │  /feature-dev:    │  Phase 6 内置     │  /smart:commit    │
  │   explorer     │  feature-dev      │  code-reviewer    │     ↓              │
  │   (独立)       │  Phase 1-5        │     ↓             │  /smart:push       │
  │                │                   │  (可选) /simplify │     ↓              │
  │                │                   │  (可选) /pr-      │  /smart:pr         │
  │                │                   │  review-toolkit   │                    │
  │                │                   │                    │  (可选) /code-     │
  │                │                   │                    │  review（PR 自动  │
  │                │                   │                    │  回帖）           │
```

## 使用要点

### 调用方式

```
/feature-dev:feature-dev 实现用户登录功能
```

参数会被填进 Phase 1 的 "Initial request" 字段。

### 想加 TDD？

Phase 5 不天然支持 TDD。三种接入方式：

1. **简单**：调用时追加 "请按 TDD 开发（Red → Green → Refactor）"
2. **永久**：在项目 CLAUDE.md 里声明 TDD 是默认开发流程
3. **严格**：fork 命令，把 Phase 5 拆成 5a/5b/5c/5d 的 TDD 循环

### 用 `/fast-feature` 之类的快速版？

官方没提供。想要更快的版本就跳过这个命令，直接说 "帮我实现 X"。

## 常见误解

1. **"feature-dev 会自动写代码"** — ❌ Phase 5 必须等你批准
2. **"跑完 feature-dev 就不用 review 了"** — ❌ Phase 6 是实现者自审，PR 级审查仍然该用 `/code-review` 或 `/pr-review-toolkit`
3. **"任意请求都可以塞进 feature-dev"** — ❌ 它是为"实现功能"设计的；如果任务是"总结"、"对比"、"查资料"，不该走这个流程

## 相关笔记

- [`review-skills-comparison.md`](./review-skills-comparison.md) — Phase 6 的 code-reviewer vs 独立 review 工具对比
- `~/coco/docs/knowledges/ai-native/context-engineering.printed.md` — feature-dev 的多 agent 并行是"上下文路由"的一个落地例子
