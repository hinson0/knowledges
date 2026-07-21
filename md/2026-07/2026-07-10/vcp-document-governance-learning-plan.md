# VCP 文档治理与 AI Coding 上下文工程学习计划

> 目标：达到 Level 2——能够在其他项目中独立设计并搭建一套可运行的文档治理体系。  
> 后续：Level 3（CI、注释治理、语义一致性）暂列 TODO，不作为当前主线。  
> 参考仓库：`/Users/a114514/ce_repos/vcp`  
> 建议周期：10 个学习单元，每单元 60～90 分钟。  
> 更新日期：2026-07-10

## 一、学习结果

完成本计划后，应当能够：

1. 根据知识生命周期，把内容放入 AGENTS、当前状态、专题文档、ADR、Runbook、Todo 或 Lessons。
2. 根据代码 diff，在 5 分钟内识别需要检查的文档。
3. 为文档设计 `status`、`owner`、`last_updated`、`source_files` 和 `related_docs` 元数据。
4. 编写最小可用的文档 inventory、audit 和 AI 任务结束门禁。
5. 在半天内为另一个项目搭建一套最小文档治理系统。
6. 明确区分“流程防忘记”和“语义一致性”，不把自动审计误当成绝对正确性证明。

## 二、学习方法

采用以下比例：

- 60%：在练习项目中亲手重建。
- 30%：阅读 VCP 的真实实现。
- 10%：研究代码与文档共同演进的 Git 提交。

不要通读 VCP 的全部文档。学习重点是：

> 什么知识放在哪里；代码变化后如何找到受影响文档；由什么流程提醒；由什么门禁验证。

## 三、先建立五层知识模型

| 层级 | 解决的问题 | VCP 对应载体 |
| --- | --- | --- |
| 常驻规则 | 每次 AI coding 都必须知道什么 | `AGENTS.md`、嵌套 `AGENTS.md` |
| 当前事实 | 项目现在真实实现了什么 | `docs/context/CURRENT_STATUS.md` |
| 专题知识 | API、架构、安全和操作方式 | `docs/api`、`docs/architecture`、`docs/security`、`docs/runbooks` |
| 决策历史 | 为什么采用当前方案 | `docs/adr` |
| 经验反馈 | 哪些错误值得以后避免 | `tasks/lessons.md` |

判断口诀：

- 每次任务都必须知道：放 AGENTS。
- 描述当前实现：放 CURRENT_STATUS 或专题文档。
- 长期架构取舍：放 ADR。
- 一次性执行记录：放 Todo/Review。
- 可复用的踩坑模式：放 Lessons。
- 具体操作步骤：放 Runbook。

## 四、10 个学习单元

### 单元 1：理解文档治理的目标

阅读：

- `AGENTS.md`
- `docs/README.md`
- `docs/context/PROJECT_BRIEF.md`
- `docs/context/CURRENT_STATUS.md`

练习：用一页纸回答：

1. 哪个文件是当前实现状态入口？
2. PRD 和真实实现冲突时相信谁？
3. 为什么 AGENTS 不应该写成长篇架构说明？

产出：一张项目知识地图。

### 单元 2：学习文档分类和生命周期

阅读：

- `docs/adr/README.md`
- `docs/quality/CONTEXT_AUDIT.md`
- `tasks/lessons.md`
- `docs/releases/README.md`

练习：把以下内容分别归类：API 改动、架构决策、线上故障操作步骤、一次用户纠正、临时验证结果。

验收：能够解释 ADR、Runbook、Quality Report、Todo 和 Lesson 的区别。

### 单元 3：学习 frontmatter 和事实来源

掌握模板：

```yaml
---
title: 文档标题
status: draft|active|deprecated|superseded
owner: owning-area
last_updated: YYYY-MM-DD
source_files:
  - path/to/source.ts
related_docs:
  - path/to/document.md
---
```

练习：选择一个 `apps/api` controller，为它设计一份文档 frontmatter，不修改仓库。

重点：`last_updated` 只是时间信号；`source_files` 才是代码与文档的关联入口。

### 单元 4：学习代码变更到文档的映射

阅读：

- `.agents/skills/project-docs-maintainer/SKILL.md`

整理自己的 Change→Docs 表，例如：

| 代码区域 | 应检查的文档 |
| --- | --- |
| API controller / DTO | OpenAPI、REST/SSE/WS 文档、CURRENT_STATUS |
| Agent 工具和事件 | Agent workflow、tool policy、AgentEvent 协议 |
| Snapshot / Sitemap | 数据合同、同步协议、恢复 Runbook |
| Starter 模板 | 模板约束、生成规则、模板级 AGENTS |
| 部署链路 | 架构、部署 Runbook、安全边界 |

验收：看到一个 diff 后，可以说明“为什么这些文档受影响”。

### 单元 5：拆解 inventory 和 audit

阅读：

- `.agents/skills/project-docs-maintainer/scripts/doc_inventory.ts`
- `.agents/skills/project-docs-maintainer/scripts/context_audit.ts`
- 对应的 `*.test.ts`

理解当前检查项：

- 核心文档存在；
- managed docs 有 frontmatter；
- `last_updated` 合法且未超过阈值；
- 本地链接有效且不逃逸仓库；
- AGENTS 大小受控；
- generated inventory 存在。

练习：在临时目录中制造缺失 frontmatter、断链和过期日期，确认 audit 能失败。

### 单元 6：拆解 AI Coding Stop Hook

阅读：

- `.codex/hooks/policy.ts`
- `.codex/hooks/policy.test.ts`

重点理解 `evaluateStop`：

1. 工作区有改动时要求 `tasks/todo.md` 存在 Review。
2. 核心代码变化但没有文档变化时阻止结束。
3. 确认无需更新时，要求 Review 写明判断和原因。
4. API surface 变化时，要求 OpenAPI 与 API 文档同时更新。
5. 有改动时执行格式检查。

练习：给一个虚构 API 改动写出 Stop Hook 应当接受和拒绝的输入。

### 单元 7：理解命令和 Git 门禁

阅读：

- 根 `package.json`
- `.husky/pre-commit`
- `.agents/skills/vcp-git-workflow/SKILL.md`

画出命令关系：

```text
pnpm check
  → lint
  → typecheck
  → skills:check
  → pnpm test
      → 单元测试
      → codex:test
      → docs:audit
```

重点区分：

- AI Stop Hook：防止 AI 忘记做文档同步判断。
- Git pre-commit：当前主要保护单元测试和 staged tree。
- docs:audit：检查文档结构完整性。
- CI/MR：当前仓库内没有完整的服务端强制配置，这是 Level 3 范围。

### 单元 8：研究真实提交

执行只读命令：

```bash
cd /Users/a114514/ce_repos/vcp
git show 5b7da3f4
git show 77bfd9af
git show f7e07ae7
```

每个提交回答：

```text
代码改变了什么？
影响了哪些长期事实？
更新了哪些文档？
为什么是这些文档？
哪些细节不应进入 AGENTS？
是否形成了可复用 Lesson？
```

### 单元 9：在练习项目中重建最小系统

创建一个临时练习项目，搭建：

```text
AGENTS.md
docs/
  README.md
  context/CURRENT_STATUS.md
  architecture/
  api/
  runbooks/
  adr/
scripts/
  docs-inventory.ts
  docs-audit.ts
tasks/
  todo.md
  lessons.md
```

最小版本必须做到：

1. 扫描 Markdown 并生成 inventory。
2. 校验核心文档、frontmatter、日期、链接和 `source_files`。
3. 根据 changed paths 判断是否需要文档同步。
4. 允许在 Review 中明确说明无需更新及原因。
5. 把 audit 接入 `check` 命令。

不要直接复制 VCP 全部脚本；先按理解重写，再对照差异。

### 单元 10：故障演练和最终验收

主动制造：

1. 删除核心文档。
2. 制造断链。
3. 将 `last_updated` 改为过期日期。
4. 修改 API，不改 API 文档。
5. 只更新 OpenAPI，不更新 API 说明。
6. 修改核心代码，只改一份无关文档。
7. 在 Review 中给出合理的“无需更新”说明。
8. 把一次性修复错误写进 Lessons，判断它为什么不该长期沉淀。

验收标准：系统应阻止前六种情况，允许第七种情况，并能识别第八种知识分类错误。

## 五、迁移到其他项目时的最小模板

新项目优先落地以下能力：

1. 一个短小的根 `AGENTS.md`。
2. 一个文档导航 `docs/README.md`。
3. 一个当前状态事实源。
4. 架构、API、安全、Runbook、ADR 分层。
5. managed docs frontmatter。
6. Change→Docs 映射规则。
7. inventory + audit。
8. AI 任务 Review/Stop 门禁。
9. `check` 命令统一收口。
10. Lessons 只记录可复用模式，不记录流水账。

## 六、不要盲目复制 VCP 的部分

VCP 当前方案仍有边界：

- 触碰任意文档不能证明修改的是正确文档。
- `last_updated` 更新不能证明内容语义正确。
- 当前 audit 没有充分利用 Git 比较 source 与文档新旧。
- 对老旧代码注释缺少专门治理。
- 人类开发者如果不运行完整 `check`，仍可能绕过部分本地流程。
- 仓库内没有完整的服务端 CI/MR 文档门禁。

学习时应复制原则和反馈闭环，不要原样照搬全部目录、正则和脚本。

## 七、Level 3 TODO

以下内容作为后续增强，不进入当前 Level 2 主线：

- [ ] 根据 Git 历史比较 `source_files` 与文档更新时间。
- [ ] 校验所有 `source_files` 路径真实存在。
- [ ] 建立代码注释治理规则和静态检查。
- [ ] 对 `TODO`、`FIXME`、`@deprecated` 增加责任人或清理期限。
- [ ] 检查 OpenAPI、DTO/schema 和说明文档的语义一致性。
- [ ] 把 `docs:audit` 接入 CI/MR 必过门禁。
- [ ] 防止修改无关文档绕过同步检查。
- [ ] 建立文档 owner、覆盖率和过期趋势报告。

## 八、学习完成检查表

- [ ] 能解释五层知识模型。
- [ ] 能判断新知识应该放在哪里。
- [ ] 能根据 diff 识别受影响文档。
- [ ] 能设计 managed-doc frontmatter。
- [ ] 能独立实现 inventory 和 audit。
- [ ] 能设计 AI Stop Hook。
- [ ] 能设计合理的“无需更新文档”例外机制。
- [ ] 能在练习项目中通过八项故障演练。
- [ ] 能在半天内为新项目搭建最小版本。
- [ ] 能明确指出系统尚未解决的语义一致性问题。

完成以上检查后，Level 2 达成；再开始 Level 3 TODO。
