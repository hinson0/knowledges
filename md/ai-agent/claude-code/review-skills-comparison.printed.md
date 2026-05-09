# PR 审查工具对比：`/review` vs `/code-review` vs `/pr-review-toolkit`

Claude Code 生态里有三个名字相似的代码审查工具，容易选错。三者代表**三种完全不同的审查哲学**。

## 三者共同点

**三个都是针对 pull request 的审查工具**，官方描述都明确提到 PR：

| 工具                  | 官方描述                                                     |
| --------------------- | ------------------------------------------------------------ |
| `/review`             | "Review a pull request"                                      |
| `/code-review`        | "Code review a pull request"                                 |
| `/pr-review-toolkit`  | "Comprehensive PR review using specialized agents"           |

差异**不在"本地 vs PR"**（都是 PR），而在**审查哲学**：

| 工具                  | 定位                                   | 流派           |
| --------------------- | -------------------------------------- | -------------- |
| `/review`             | 通用、黑盒、不可定制                   | **简约派**     |
| `/code-review`        | 固定流水线 + 自动回帖 GitHub           | **自动化派**   |
| `/pr-review-toolkit`  | 专项 agent 池 + 按需路由               | **精细化派**   |

## 来源与身份

| 工具                  | 加载形式                                                          |
| --------------------- | ----------------------------------------------------------------- |
| `/review`             | **Claude Code 内置 skill**（编译进二进制）                         |
| `/code-review`        | 官方插件 `code-review@claude-plugins-official`，提供 1 个命令     |
| `/pr-review-toolkit`  | 官方插件 `pr-review-toolkit@claude-plugins-official`，**1 命令 + 6 专项 agents** |

"内置 vs 插件"的设计哲学差异：

- **内置 skill**：通用、黑盒、不可定制
- **插件形式**：专业、透明、可改（命令文件可编辑）

Anthropic 用插件形式把"更专业但更重"的能力从内置剥离出来，保持二进制精简。

## 三方核心对比

| 维度                  | `/review`（内置）  | `/code-review`（插件）                  | `/pr-review-toolkit`（插件）                            |
| --------------------- | ------------------ | --------------------------------------- | ------------------------------------------------------- |
| **加载形式**          | 编译进二进制       | 独立 plugin，单 command                 | 独立 plugin，**1 command + 6 专项 agents**              |
| **运行时机**          | 任何时候           | **PR 已开**，一次性                      | **开发全程**（commit 前、PR 前、PR 反馈后反复）          |
| **审查架构**          | 不公开             | **5 个并行 Sonnet + N 个 Haiku 评分**    | **6 个专项 agent**，按需 1~6 个                          |
| **专项化程度**        | 通用               | 通用（但维度固定）                      | **高度专项**（注释/测试/错误/类型/通用/简化）            |
| **智能路由**          | 无                 | 无（固定跑 5 agents）                   | ✅ **根据 diff 自动选 agent**（改测试才跑测试分析）       |
| **参数化**            | 无                 | 无                                      | ✅ `review-pr tests errors` 只跑指定维度                  |
| **置信度过滤**        | 未知               | **整体 80 分硬过滤**                    | 各 agent 自己的 threshold（code-reviewer 用 >50）         |
| **输出目的地**        | 终端               | **直接 `gh pr comment` 回帖 GitHub**    | 终端结构化报告（Critical/Important/Suggestions/Strengths）|
| **前置要求**          | PR（官方描述所示） | 必须 `gh` + GitHub PR                   | git diff 即可（命令文档允许无 PR 状态下本地审）         |
| **agent 可独立调用**  | —                  | 否                                      | ✅ **6 个 agent 可被关键词自动触发**，不走命令也能用      |

## 各自的独特卖点

### `/review`（内置）

- **零配置**，二进制自带
- 快速轻量，适合简单场景
- 一行代码都改不了

### `/code-review`（插件）

- **自动化流水线**——可以接入 CI，PR 开了就自动跑、自动回帖
- **置信度硬过滤**——只发高置信度 issue（默认 ≥80 分），减少噪音
- 适合**规模化团队 + 严格 PR 制度**
- 命令文件可改 threshold、加 agent

#### 审查架构

```
PR diff
  ↓
Haiku eligibility check（是否跳过：draft、已审、trivial）
  ↓
5 个并行 Sonnet agent：
  ├─ Agent #1: CLAUDE.md 合规审计
  ├─ Agent #2: 浅层 bug 扫描（只看 diff）
  ├─ Agent #3: 基于 git blame 的历史上下文审查
  ├─ Agent #4: 相关历史 PR 的评论分析
  └─ Agent #5: 代码注释合规检查
  ↓
每个 issue → Haiku 评分（0~100）
  ↓
过滤 <80 的 → 只保留高置信度
  ↓
gh pr comment 回帖到 GitHub
```

#### 置信度评分量表（默认 threshold=80）

| 分数 | 含义                                                    |
| ---- | ------------------------------------------------------- |
| 0    | 完全不自信，false positive 或 pre-existing issue        |
| 25   | 略有信心，可能真也可能假                                |
| 50   | 中等信心，真问题但可能是 nitpick                        |
| 75   | 高度自信，真问题、会影响功能、或 CLAUDE.md 明确提到     |
| 100  | 绝对确定，反复核查后确认真问题                          |

### `/pr-review-toolkit`（插件）

- **按症下药**——6 个专家 agent 各管一摊，精度高
- **智能路由**——改了什么就跑什么，不浪费资源
- **独立触发**——不走命令也能用关键词触发（对话里说"review the error handling"会自动触发 silent-failure-hunter）
- **多次迭代友好**——开发过程中可以反复跑、跑不同方面

#### 6 个专项 agent

| Agent                     | 专长                               | 关键词触发                           |
| ------------------------- | ---------------------------------- | ------------------------------------ |
| **comment-analyzer**      | 注释准确性、注释腐化               | "注释是否准确"、"文档是否过时"       |
| **pr-test-analyzer**      | 测试覆盖**行为**而非行、评分关键性 | "测试是否全面"、"有没有关键测试缺口" |
| **silent-failure-hunter** | catch 块、静默失败、错误日志       | "审查错误处理"、"检查静默失败"       |
| **type-design-analyzer**  | 类型封装、不变性（1-10 打分）      | "审查 UserAccount 类型设计"          |
| **code-reviewer**         | 通用审查 + CLAUDE.md 合规          | "审查最近的改动"                     |
| **code-simplifier**       | 简化、重构、清晰度                 | "简化这段代码"                       |

**装 plugin 就生效**——不需要显式调用命令，Claude 在对话里根据关键词自动触发对应 agent。

#### 智能路由规则（`review-pr` 命令）

| 检测到的变更       | 自动触发的 agent         |
| ------------------ | ------------------------ |
| 任何代码变更       | code-reviewer（always）  |
| 测试文件改动       | pr-test-analyzer         |
| 新增/修改注释      | comment-analyzer         |
| 错误处理变更       | silent-failure-hunter    |
| 新增/修改类型      | type-design-analyzer     |
| 通过审查后         | code-simplifier（polish）|

## 决策树：你该用哪个？

```
你的场景？
├─ 没开 PR，只想审本地代码
│  → /review 按官方描述是 PR 审查，未必适合
│    更好选择：/feature-dev Phase 6 自审
│              或 /pr-review-toolkit:review-pr（支持 git diff 审查）
│
├─ 已开 PR，想让机器人自动审完回帖 GitHub
│  → /code-review ✅（自动化派首选）
│
├─ 已开 PR 或本地有 diff，想针对具体方面审查
│  ├─ "测试够不够"、"错误处理有没有坑"、"类型设计怎么样"
│  │  → /pr-review-toolkit（按需跑专项 agent）✅
│  └─ "感觉代码有点冗余，简化下"
│     → /simplify（code-simplifier plugin 独立版）
│     或 /pr-review-toolkit:review-pr simplify
│
├─ 想要通用、轻量、不折腾的 PR 审查
│  → /review（内置，零配置）
│
└─ 生产关键路径，要最大化严谨性
   → 两个都跑：pr-review-toolkit 深度查 + code-review 在 PR 上留档
```

## 组合工作流推荐

```
1. 开发中
   → pr-review-toolkit 的 agents 会被 Claude 自动触发（装了就生效）
     想针对性审查时手动跑：/pr-review-toolkit:review-pr tests errors

2. 准备开 PR 前
   → /smart:commit → /smart:push → /smart:pr

3. PR 开出后（如果要自动评审）
   → 装 /code-review，CI 接入它

4. 简单本地自检
   → /review（零配置）
```

## 定制化能力对比

| 工具                    | 能改吗？                                               |
| ----------------------- | ------------------------------------------------------ |
| `/review`               | ❌ 完全不可改                                           |
| `/code-review`          | ✅ 改 threshold、加 agent、改 prompt                    |
| `/pr-review-toolkit`    | ✅✅ 改 6 个 agent 各自的 prompt、增减 agent、改协调命令 |

`/code-review` 的命令文件在：

```
~/.claude/plugins/cache/claude-plugins-official/code-review/unknown/commands/code-review.md
```

`/pr-review-toolkit` 的 agents 和命令在：

```
~/.claude/plugins/cache/claude-plugins-official/pr-review-toolkit/unknown/
├── commands/review-pr.md
└── agents/
    ├── comment-analyzer.md
    ├── pr-test-analyzer.md
    ├── silent-failure-hunter.md
    ├── type-design-analyzer.md
    ├── code-reviewer.md
    └── code-simplifier.md
```

## 常见误解澄清

1. **"三者可以互相替代"** — ❌ 不能，输出方式和审查哲学完全不同
2. **"code-review 比 review 更好"** — ❌ 是更严谨，但对简单场景是过度杀鸡用牛刀
3. **"pr-review-toolkit 只能用 review-pr 命令"** — ❌ 6 个 agent 都可以被关键词独立触发
4. **"装了 pr-review-toolkit 就不需要 code-review"** — ❌ 两者目标不同：前者关注细分维度的本地报告，后者负责在 GitHub PR 上自动回帖
5. **"`/review` 可以审查本地代码"** — ⚠️ 官方描述明确是 "Review a pull request"。本地审查更适合用 `/pr-review-toolkit:review-pr` 或 `/feature-dev` 的 Phase 6 自审，别被工具名误导

## 相关笔记

- [`claude-code-permissions-guide.md`](./claude-code-permissions-guide.md) — 权限配置
- [`code-review.printed.md`](./code-review.printed.md) — `/code-review` 插件的中文翻译文档
- [`pr-review-toolkit.printed.md`](./pr-review-toolkit.printed.md) — `/pr-review-toolkit` 插件的中文翻译文档
- `~/coco/docs/knowledges/ai-native/ai-code-review-standards.md` — AI 代码审核通用标准
