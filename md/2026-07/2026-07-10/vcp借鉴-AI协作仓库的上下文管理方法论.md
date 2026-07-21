# 借鉴自 VCP：让 AI 长期 vibe coding 不漂移的仓库级上下文管理

> 来源仓库：`~/ce_repos/vcp`（文中 file:line 均相对该仓库根）
> 针对两个典型痛点：**① 代码更新后文档没更新；② 代码更新后没有留存资产，AI 跨 session 无记忆导致漂移。**
> 本文自包含，含模板与落地步骤，可直接搬到其他项目。

---

## 0. 总览：三层叠加的设计

VCP 的整套机制可以概括为三层，缺一不可：

```
┌─ 软约定层（给 AI 读的规则）──────────────────────────┐
│ AGENTS.md / lessons.md / ADR / 代码→文档映射表           │
│ 负责让 AI「做得更对」                                    │
├─ 事实源绑定层（文档与代码的外键）────────────────────┤
│ frontmatter: last_updated + source_files                 │
│ 负责让「过期」变得可判定、可审计                          │
├─ 硬闸门层（脚本/hook 拦截）──────────────────────────┤
│ docs:audit 脚本 + Stop hook + pre-commit 守卫             │
│ 负责让 AI「至少做了」——不做就不许收口/不许提交            │
└──────────────────────────────────────────────────────┘
```

**核心洞察：约定负责质量，强制负责底线。** 只有约定（CLAUDE.md 写一堆规则）会被 AI 在长会话中逐渐遗忘；只有强制（hook 拦截）会让 AI 应付了事。两层配合：hook 拦住「没做」，约定指导「怎么做对」。

---

## 1. 痛点 ①：代码更新后文档没更新

### 1.1 VCP 的解法 = 两个时间尺度的强制

| 尺度 | 机制 | 防什么 |
|---|---|---|
| **即时**（本次会话） | Stop hook：改了代码目录却没动 `docs/` → **不许结束任务** | 「改了不同步」 |
| **周期**（60 天） | `docs:audit`：每篇文档 `last_updated` 距今 >60 天 → 审计失败 | 「长期无人问津的文档悄悄腐烂」 |

### 1.2 frontmatter 合同（文档到代码的外键）

每篇受管文档头部（VCP 实例：`docs/context/CURRENT_STATUS.md:1`）：

```yaml
---
title: 当前状态
status: active            # draft | active | deprecated | superseded
owner: engineering        # 归属域
last_updated: 2026-07-01  # ★唯一被脚本硬校验的字段
source_files:             # 本文档基于哪些代码（软绑定索引，给 AI 看的）
  - apps/api/src/sites/sites.controller.ts
  - packages/contracts/src/index.ts
related_docs:
  - PROJECT_BRIEF.md
---
```

关键认知（容易误解的点）：
- **`last_updated` 是新鲜度闸门的唯一输入**——审计脚本只算 `今天 - last_updated > 60 天` 就判 STALE（`context_audit.ts:46,144-159`）。**不做** source_files 的 git mtime 依赖追踪。
- **`source_files` 是给 AI 读的软索引**：告诉下一个 session「这篇文档对应哪些代码，改了那些代码就该回来更新我」。脚本只采集不校验。
- 为什么挂钟阈值反而好：实现是零依赖 ~200 行脚本；效果是逼着每篇文档 60 天内必被人/AI 重新审视一次——配合即时层，足够了。mtime 依赖追踪实现复杂且误报多（重构挪文件就炸）。

### 1.3 docs:audit 审计脚本（可直接照抄的规则集）

VCP 实现：`.agents/skills/project-docs-maintainer/scripts/context_audit.ts`（约 200 行，零依赖）。审计项：

1. **核心文档存在性**：硬编码 15 篇必须存在的文档清单（AGENTS.md、docs/README.md、CURRENT_STATUS.md 等），缺失即失败
2. **AGENTS.md ≤ 24KB**：强制常驻上下文精简（防入口文件膨胀吃掉上下文窗口）
3. **frontmatter 必填**：`docs/**` 每篇 .md 必须有 frontmatter
4. **`last_updated` 合法且 ≤60 天**
5. **本地断链检查**：`[text](href)` 目标不存在 → 失败（检查前先剥离代码块防误判）
6. **豁免显式化**：`docs/releases/**`（周报不可变归档）豁免新鲜度但**不豁免断链**；豁免规则同时写在脚本、脚本的单元测试、相关 SKILL.md、目录 README **四处联动**，改豁免会触发测试失败

编排：`docs:audit` 编进 `pnpm test`，`test` 编进 `pnpm check`（`package.json:39,62`）——跑全量验证必过文档审计。**审计脚本自身有单元测试**（`context_audit.test.ts`），防止机制被悄悄改坏。

另一个巧思：inventory 生成物固定 `generatedAt: "1970-01-01..."` 和相对路径（`doc_inventory.ts:48,156-157`）——**生成物确定性**，可提交、diff 干净。

### 1.4 Stop hook：改代码不动文档 → 不许收口

VCP 实现在 `.codex/hooks/policy.ts`（743 行策略引擎 + 36 个单测锁定），挂在会话 Stop 事件上。判定逻辑（`evaluateStop` :637-668）：

```
会话想结束时依次检查：
1. 工作区有改动但 tasks/todo.md 没有 "## Review" 小节 → block
   「请先补充任务 Review 和验证记录再结束」
2. 改了 API surface 文件（*.controller.ts / contracts 等前缀模式）
   却没同步 openapi/** 或 docs/api/** → block
   （除非 Review 里写明「API 无需更新 + 理由」）
3. 改了 docSyncPrefixes 里的代码目录（apps/* services/* packages/*...）
   却没碰 docs/ → block
   （除非 Review 里写明「文档同步判断：无需更新，因为...」）
4. 有改动就跑 pnpm format:check，不过 → block
```

**精髓：可绕过但必须留痕。** AI 判断「这次真不用更新文档」是允许的，但必须在 Review 里写下这个判断和理由——「不更新」这个决定本身被显式记录、可审计。这避免了强制僵死，又杜绝了静默跳过。

### 1.5 代码→文档映射表（约定层）

`.agents/skills/project-docs-maintainer/SKILL.md` Phase 2 维护一张表：

```
改 apps/agent/**      → 必查 docs/agent/AGENT_WORKFLOW.md、TOOL_POLICY.md...
改 packages/contracts → 必查 docs/api/API_CONTRACTS.md
改 services/**        → 必查 docs/architecture/...、runbooks/...
```

这张表和 Stop hook 的 `docSyncPrefixes` 是同一思想的软硬两面：表告诉 AI 具体查哪篇，hook 兜底「至少动了 docs」。

---

## 2. 痛点 ②：无留存资产 → AI 跨 session 无记忆 → 漂移

### 2.1 六类记忆资产，各防一种漂移

| 资产 | 防的漂移 | 关键设计 |
|---|---|---|
| `docs/context/CURRENT_STATUS.md` | **把计划当已实现** | 强制区分 implemented/skeleton/planned；声明「实现状态以代码和本文档为准，压过 PRD」；source_files 绑定代码；114 次提交≈每个 feature 收口更新一笔 |
| `tasks/lessons.md` | **重复踩同一个坑** | 三段式格式（见 2.2）；AGENTS.md 明文规定何时必须记录/不应记录 |
| `docs/adr/ADR-NNNN-*.md` | **架构反复横跳、重开已否决方案** | 背景/决策/后果/**考虑过的替代方案（含拒绝理由）**；只新增或标 superseded，不改历史 |
| `docs/superpowers/specs+plans/YYYY-MM-DD-*.md` | **实现偏离设计意图** | 日期前缀=不可变时间线；spec（设计）与 plan（执行）分离；frontmatter status 标 implemented |
| `tasks/todo.md`（**gitignore，本地）** | **会话中途丢范围、干完不留痕** | 活状态本地化不入库；Checklist + Review（含逐条验证命令与结果）；Stop hook 强制 Review 存在 |
| `tasks/archive/archive.md` | **记忆文件无限膨胀、旧分支合并把归档内容带回** | 按月归档；`<!-- lessons-archive: 2026-05 -->` 机读标记 + lessons-audit 脚本防回灌；lessons 归档压缩成高频规则摘要+日期索引 |

另有一个补充形态：**handoff 文档**（`tasks/pi-borrow-debate-handoff.md`）——一次性大调研/未决讨论的自包含结论快照，开头写明「新会话零上下文也能接着讨论」。适合跨 session 续接尚未落地的决策。

### 2.2 lessons.md 三段式（最值得抄的单一格式）

```markdown
## 2026-07-01：pre-commit 必须保护 staged tree，防止 hook 副作用生成空提交

- 问题模式: 已 stage 的变更在 pre-commit 阶段消失后，Git 仍生成了空提交…
  （发生了什么，带复现证据）
- 预防规则: 任何会跑测试/生成器的 pre-commit hook，都必须在执行前后比对
  staged tree 和 worktree diff，变了就直接失败…（以后怎么杜绝）
- 更早可捕获信号: commit 输出没有文件统计、`git show --stat HEAD` 为空但
  message 声称有修复…（下次怎么在更上游发现）
```

为什么这个格式好：普通的「踩坑记录」只写发生了什么，AI 下次读了未必能对号入座；三段式强制把一次性事故**升维**成「模式识别 + 预防动作 + 上游信号」，AI 可以直接执行。

**闭环设计（VCP 最漂亮的一笔）**：上面这条 lesson 后来被固化成了 `.husky/pre-commit` 里的 staged-tree 哈希守卫——**lesson 不止是文字，成熟一条就变成一条 hook 规则**。记忆资产 → 强制闸门的升级通道。

### 2.3 入口结构：单一权威 + 就近覆盖

```
CLAUDE.md          ← 一句话:「以 AGENTS.md 为准」+ @AGENTS.md 内联
                     只补工具适配层的通用行为约束（todo/lessons 维护规则等）
AGENTS.md          ← 唯一权威（≤24KB，被审计强制）
                     开头即「非平凡任务先读这些文档」的上下文入口清单
子目录/AGENTS.md    ← 就近优先（如 templates/next-starter/AGENTS.md）
                     领域专属硬规则物理隔离，不污染根文件
```

防的是「双事实源」：CLAUDE.md 和 AGENTS.md 各写一套规则必然分叉；一句话指向 + 内联是最稳的结构。

### 2.4 冷启动路径：新 session 怎么重建记忆

VCP 给 AI 铺好的读取顺序（写在 AGENTS.md 开头，AI 一进来就看到）：

```
1. CLAUDE.md → 被导向 AGENTS.md（自动）
2. README.md（项目入口）→ docs/README.md（文档地图）
3. docs/context/CURRENT_STATUS.md（实现状态真相，压过 PRD）★
4. docs/adr/README.md（已定架构决策，别重开）
5. tasks/lessons.md（历史坑，别重踩）
6. 接手特定 feature → docs/superpowers/specs|plans/ 对应日期文件
7. 动子目录前 → 读就近 AGENTS.md
8. 开工 → 本地 tasks/todo.md 建 Checklist；收口 → 写 Review（hook 强制）
```

### 2.5 硬闸门层全家福

| 闸门 | 位置 | 拦什么 |
|---|---|---|
| Stop hook 四连拦 | 会话结束时 | 无 Review / API 未同步 / 文档未同步 / 格式不过 |
| PreToolUse hook | 每次工具调用前 | 危险命令（`git reset --hard`、`rm -rf`）、main 分支直接 commit、绕过 git workflow skill、提交信息不含中文、生产部署无人工确认 marker |
| PostToolUse hook | 工具输出后 | 输出含 secret → 替换拦截 |
| pre-commit（husky） | git 提交时 | 全 workspace 单测 + **staged tree 哈希守卫**（测试前后比对 `git write-tree`，hook 偷改暂存区就 abort） |
| 规则自锁 | `pnpm codex:test` | hook 策略和审计脚本自身的 36+ 单测，防机制被改坏 |

注意：VCP **没有远端 CI**——全部强制落在本地 hook + 脚本 + 约定跑 `pnpm check`，照样成立。

---

## 3. 落地指南：搬到你的项目

### 第一档：今天就能上（零脚本，纯文件约定）

1. **建单一权威入口**：`AGENTS.md`（或 CLAUDE.md 独用也行，关键是**只有一个**），开头写「上下文入口清单」：新 session 先读哪几篇。
2. **建 `docs/CURRENT_STATUS.md`**：三态区分 implemented / skeleton / planned，声明「实现状态以代码和本文档为准」。给它加 frontmatter（last_updated + source_files）。**每个 feature 收口时更新一笔**——这一条就能解决你大部分的「AI 把没做的当做过的」。
3. **建 `tasks/lessons.md`**：三段式格式（问题模式/预防规则/更早信号）。在 AGENTS.md 里写清楚何时必须记录（纠正了范围/决策/流程/长期约束、同类问题重复出现）、何时不记（一次性 bug 细节、审美偏好）。
4. **`tasks/todo.md` 加进 .gitignore**：活状态本地化。约定格式：任务标题 + Checklist + 收口前写 `## Review`（含跑过的验证命令和结果）。
5. **在 AGENTS.md 写下软规则**：「改了 `<你的代码目录>` 必须检查 `docs/` 对应文档；确实不用更新时，在 todo Review 里写明理由。」

### 第二档：一周内加强制层

6. **写 docs:audit 脚本**（可直接参考 `context_audit.ts`，零依赖 ~200 行）。最小版只需三条规则：
   ```
   - docs/** 每篇必须有 frontmatter 和合法 last_updated
   - last_updated 距今 > 60 天 → 报 STALE，exit 1
   - 本地 markdown 链接目标必须存在（剥离代码块后再查）
   ```
   编进 `npm test` / CI。
7. **配 Stop hook**（Claude Code 用 `.claude/settings.json` 的 hooks，等价于 VCP 的 `.codex/hooks`）。最小版两条：
   ```
   - git 工作区有改动但 tasks/todo.md 无 "## Review" → block
   - 改动路径命中代码目录前缀但没碰 docs/ 且 Review 无「无需更新」声明 → block
   ```
8. **pre-commit**（husky）：跑单测 + staged-tree 哈希守卫（防 hook 副作用污染提交）。

### 第三档：项目成熟后

9. **ADR**：重大架构决策落 `docs/adr/ADR-NNNN-*.md`，必须含「考虑过的替代方案与拒绝理由」。
10. **specs/plans 日期前缀留档**：`YYYY-MM-DD-<slug>-design.md` / 同名 plan，feature 开工前写、做完标 status。
11. **归档机制**：lessons/todo 按月压缩进 `tasks/archive/archive.md`，加机读标记防旧分支合并回灌。
12. **豁免显式化**：任何审计豁免（如不可变归档目录）同时写在脚本+测试+文档，声明「改豁免要几处联动」。

### 直接可抄的最小 frontmatter 模板

```yaml
---
title: <文档标题>
status: active
owner: <归属域>
last_updated: <YYYY-MM-DD>   # 每次实质更新必改；审计脚本唯一硬校验字段
source_files:                 # 本文基于哪些代码；改了它们就该回来更新本文
  - src/...
related_docs:
  - ...
---
```

---

## 4. 最值得抄的六个点（按性价比排序）

1. **活状态本地化，沉淀经验入库**：todo.md gitignore（每个 worktree 自己的草稿），lessons/archive/ADR 入库。git 历史干净，记忆资产纯粹。
2. **CURRENT_STATUS 的三态区分 + 「压过 PRD」声明**：一句「不要把 planned 当 implemented，以代码和本文档为准」直接砍掉 AI 最大的幻觉源。
3. **Stop hook「无 Review 不许收口」+「可绕过但留痕」**：把「验证后再声称完成」「不更新文档要给理由」从自觉变成闸门。
4. **lessons 三段式 + lesson→hook 的固化闭环**：经验不止被记住，成熟一条就升级成一条机器强制。
5. **挂钟 STALE 而非依赖追踪**：60 天阈值 + last_updated，200 行零依赖脚本就能逼所有文档定期被回看——别一上来就想做 mtime 级依赖分析。
6. **每个论断带 file:line 证据**：lessons、specs、handoff、Review 全仓一致的「可复核」文化——AI 写的结论必须能被下一个 AI（或人）快速验证，这本身就是抗漂移。

---

## 5. FAQ：三个关键疑问

### Q1：这些代码相关的 MD 文档最初是怎么被创建出来的？

不是 AI 随手创建，有四条明确的创建路径，各有触发时机：

1. **项目初始化时的骨架（人定 + 脚本锁存在性）**：`docs/` 的目录职责表（context/api/agent/adr/runbooks…）是搭项目时定好的信息架构；15 篇核心文档清单硬编码在审计脚本里（`context_audit.ts:27-43`），缺一篇审计就失败。所以骨架不是"有空再写"，而是从第一天就必须在。
2. **feature 开工时**：按工作流先写 `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md`（设计）和 plans/（执行计划）——这是增量文档的主要出生点。
3. **重大决策时**：新建 `docs/adr/ADR-NNNN-*.md`（SKILL.md Phase 5 规定命名与结构）。
4. **feature 收口时**：更新 `CURRENT_STATUS.md` 等既有文档，而不是新建。

frontmatter 的 `source_files` 是 **AI 写这篇文档时自己填的**：SKILL.md 硬规则要求"文档里引用源码必须用仓库路径"，写作过程中讨论到哪些代码文件，就把路径列进 frontmatter。

**git 证据实例**（以 `docs/architecture/` 下文件为例）：
- 骨架路径：`SYSTEM_OVERVIEW.md`、`DATA_MODEL.md`、`PROJECT_BRIEF.md`、`ROADMAP.md` 全部诞生于同一个初始化提交 `63c2fdc6 2026-05-15 "chore: initialize VCP architecture baseline"`，且都在 coreDocs 硬编码清单里。
- **feature 随批创建路径（日常最主要）**：`SITE_OPERATION_LOCKS.md` 诞生于实现站点操作锁的提交（`7cb81b18 2026-05-29 "修复：完善站点操作锁和发布交互"`）；`DEPLOY_BUILD_FLOW.md` 诞生于接入 Cloudflare 发布闭环的提交。即 **AI 实现新机制时被 Stop hook + 映射表逼着，在同一批提交里为机制写下常青文档**——文档创建不是专门任务，是 feature 提交的一部分。

三类文档的分工（易混淆，务必分清）：

| 类型 | 位置 | 性质 | 更新策略 |
|---|---|---|---|
| 常青文档 | `docs/architecture/*.md` 等 | 机制**现状**的权威描述 | 机制变了就改，60 天审计保新鲜 |
| spec/plan | `docs/superpowers/**/YYYY-MM-DD-*.md` | 某次 feature 的设计与执行 | 日期定格，做完标 status |
| ADR | `docs/adr/ADR-NNNN-*.md` | 已拍板的**决策** | 永不改写，推翻就新写一篇标 superseded |

**ADR = Architecture Decision Record（架构决策记录）**，通用软件工程实践。固定结构：状态 / 背景 / 决策 / 后果 / **考虑过的替代方案（含拒绝理由）**。对 AI 的价值：防止新 session 把已否决的方案再提一遍、或把已定边界顺手改掉——"替代方案"一节等于直接告诉 AI「这条路走过了，别再走」。

### Q2：后续改了代码，AI 怎么"回来更新"文档？（完整闭环）

"回来更新"不是自动魔法，是三个机制合力，按时间线：

```
AI 改完代码，想结束会话
  │
  ├─ ① Stop hook 检查 git 改动路径：
  │    命中代码目录前缀（apps/、packages/…）但本次没碰 docs/**
  │    → 拦住，不许收口
  │
  ├─ ② 被拦后 AI 怎么知道更新哪篇？两个索引：
  │    a) SKILL.md 的「代码目录→文档」映射表（改 apps/agent → 查 docs/agent/*）
  │    b) source_files 反向检索：grep docs/ 下哪些文档的 frontmatter
  │       列了我刚改的文件 → 找到"声称依赖这个文件"的所有文档
  │
  ├─ ③ 两条出路（都留痕）：
  │    a) 更新文档，同时刷新 last_updated、增删 source_files
  │    b) 判断真不用更新 → 在 todo Review 里写「文档同步判断：
  │       无需更新，因为…」→ 放行，但这个决定被记录
  │
  └─ ④ 漏网兜底：就算这次被理由放行/改动没命中前缀，
       60 天 STALE 审计保证这篇文档最多 60 天后被强制回看，
       回看时对照 source_files 里的代码现状，过期就更新
```

所以「source_files 是软索引」指的就是第 ② 步 b：它是给 AI **检索用**的导航数据（"改了这些文件该回来更新我"），执行主体是 AI，不是脚本。

### Q3："脚本只采集、不校验"是什么意思？

仓库里有两个脚本，对 frontmatter 字段的态度完全不同：

- **`doc_inventory.ts`（采集器）**：扫全部 .md，把 frontmatter 各字段（title/status/owner/last_updated/source_files/related_docs）**原样抄录**进 `docs/_generated/docs_inventory.json`。它不做任何对错判断。
- **`context_audit.ts`（校验器）**：只对 `last_updated` 做硬校验（必须存在、日期合法、距今 ≤60 天，否则 exit 1 让构建失败），外加 frontmatter 存在性、断链、核心文档存在、AGENTS.md 体积。**它完全不碰 source_files**。

用一个具体例子看分界：

| 你做了什么 | docs:audit 的反应 |
|---|---|
| 在 `source_files` 里写一个不存在的路径 `foo/bar.ts` | **照样通过**——脚本不检查这个字段 |
| `source_files` 里列的代码上周改了，文档没动 | **照样通过**——脚本不比对代码 mtime |
| 把 `last_updated` 改成 90 天前的日期 | **立刻失败**——STALE |

"采集不校验"就是指 `source_files` 属于前一类：机器只负责抄录存档，从不基于它做自动判定。它的全部价值在于**被读**——被下一个 AI session 读、被人读。

为什么这样设计：如果机器要校验 source_files（路径存在性、mtime 比对"代码改了文档没改"），实现复杂且误报极多（重构挪个文件全线爆红）。VCP 的分工是：**机器管时间**（last_updated 挂钟，简单可靠），**AI 管语义**（哪些代码对应哪些文档、这次改动是否影响文档内容），**hook 管底线**（至少动了 docs 或写了理由）。

### Q4：Stop hook 的「逼」具体落在哪几行代码？

机制 = **拒绝结束回合 + 把整改指令作为 reason 喂回 AI**。链路（均在 `.codex/hooks/policy.ts`）：

1. `.codex/hooks.json` 把 policy.ts 挂到 `Stop` 事件（timeout 60s）——AI 想结束回合时宿主先跑它。
2. `evaluate()`（:685-690）：`stop_hook_active` 为 true 直接放行（防死循环），否则进 `evaluateStop`。
3. `gitChangedPaths()`（:183）：`git status --short --untracked-files=all` 收集改动路径。
4. 核心闸门（:655-659）：`needsDocSyncReminder(changedPaths) && !todoHasDocSyncJudgment()` → `block(...)`。
   - `needsDocSyncReminder`（:244-252）= 「任一改动 startsWith 代码目录前缀」且「无任一改动 startsWith docs//context/」——纯字符串前缀匹配，零语义分析。
   - 逃生门 `todoHasDocSyncJudgment`（:224-230）：Review 含"文档同步判断"或正则 `/无需(更新|同步).*(docs|context|文档)/`。
5. `block()`（:167-169）返回 `{ decision: "block", reason }`；宿主不结束回合，把 reason 作为消息喂回 AI。**reason 即 prompt**：文案本身就是可执行的整改指令（二选一：改文档 / 写理由）。
6. AI 整改后再次结束，宿主带 `stop_hook_active=true`，放行——语义是「保证收到过一次明确指令」，不是死锁。

同一个 evaluateStop 里按序还有三道：无 Review 拦（:637-641）→ API surface 加强版（:652，要求同时更新 openapi/** 和 docs/api/**，排除测试文件）→ format:check 实跑（:661）。

设计取舍：前缀匹配必然误报，对策不是提高精度而是逃生门留痕；闸门是字符串级的，防得住「没做」防不住「敷衍」，敷衍靠约定层（Review 必须含验证记录）+ policy.test.ts 锁住闸门本身。

## 6. 与运行时上下文工程的关系

本文讲的是「仓库层」（给开发用 AI 的记忆管理）。同仓库还有一套「运行时层」（VCP 产品自身给 LLM agent 组装上下文的工程：事件溯源、skill 按需加载、缓存断点等），学习材料见 `~/knowledges/md/2026-07-09/vcp-上下文工程学习路线.md` 及六站分册。两层同构：都遵循「单一事实源 + 有损留痕 + 确定性重建 + fail-soft/硬闸门」。
