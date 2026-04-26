# PRP Implement

## 概述

`/prp-implement` 是 ECC 工作流中的**实现执行技能**，用于按照 `/prp-plan` 生成的 plan 文件逐步实现功能。

**核心特征**：
- **不是 TDD**，而是"先实现，后验证"的验证循环模式
- 每改一个文件就立即验证（type-check），不积累破损状态
- 依赖 plan 文件中的代码约定参考（MIRROR）和陷阱提示（GOTCHA）
- 验证失败必须当场修复，不能跳过

---

## 6 个阶段

### Phase 0 — DETECT
自动检测项目的包管理器和可用命令：
- **包管理器**：检查 `bun.lockb`、`pnpm-lock.yaml`、`yarn.lock`、`package-lock.json`、`pyproject.toml`、`Cargo.toml`、`go.mod`
- **可用脚本**：从 `package.json`（或等价文件）识别 type-check、lint、test、build 命令

### Phase 1 — LOAD
读取 plan 文件，提取：
- Summary — 实现内容概述
- Patterns to Mirror — 要遵循的代码约定参考文件路径
- Files to Change — 需要创建或修改的文件清单
- Step-by-Step Tasks — 分步任务列表
- Validation Commands — 验证命令
- Acceptance Criteria — 验收标准

### Phase 2 — PREPARE
Git 初始化：
- 检查当前分支状态
- 若在 main 且干净，创建 `feat/{plan-name}` 分支
- 若在 main 且有未提交改动，中断并要求用户先 stash 或 commit
- 同步远端：`git pull --rebase origin $(git branch --show-current)`

### Phase 3 — EXECUTE（核心）
**顺序执行** plan 中的每个 Task：
1. **读 MIRROR 参考** — 打开 task 中 MIRROR 字段指向的约定文件，理解代码风格
2. **实现代码** — 按约定写代码，应用 GOTCHA 警告、使用指定的 IMPORTS
3. **即时验证** — 每改一个文件就跑 type-check
   - type-check 失败 → 立即修复 → 继续
   - 不允许累积错误
4. **追踪进度** — 记录 `[done] Task N: [task name]`

### Phase 4 — VALIDATE
按顺序执行 5 个验证级别，每一级失败都要先修复才能进入下一级：

1. **静态分析**
   - `type-check` — 零错误要求
   - `lint` — 自动修复，手动修复遗留错误

2. **单元测试**
   - 为每个新函数写至少一个测试
   - 覆盖 plan 中指定的边界用例
   - 测试失败 → 修复实现（而非测试，除非测试本身有问题）

3. **Build 检查**
   - 构建必须成功，零错误

4. **集成测试**（如适用）
   - 启动 dev server
   - 运行集成测试
   - 停止 server
   - 若失败 → 检查 server 启动状态、endpoint 是否存在、请求格式等

5. **边界用例测试**
   - 手动过一遍 plan 中列出的所有边界用例

### Phase 5 — REPORT
生成实现报告：
- 创建 `.claude/PRPs/reports/{plan-name}-report.md`
- 内容包括：Summary、预测 vs 实际、任务完成表、验证结果、文件变更、偏差说明、遇到的问题、写的测试
- 更新对应 PRD 的阶段状态（如适用）
- 归档 plan 文件到 `.claude/PRPs/plans/completed/`

### Phase 6 — OUTPUT
向用户汇总输出：
- plan 档案路径
- 当前分支名
- 验证汇总表
- 变更文件数
- 偏差说明
- 建议下一步：`/code-review` → `/prp-commit` → `/prp-pr`

---

## 验证策略

### 关键原则
- **Golden Rule**：验证失败，修复后再继续；永远不积累破损状态
- **即时反馈**：每改一个文件就 type-check，不是所有任务完成后才验证
- **快速失败**：第一个验证级别失败就中断，修复后重新开始

### 失败处理示例
| 场景 | 处理 |
|---|---|
| Type-check 失败 | 读错误消息 → 修复源文件 → 重新 type-check → 继续 |
| Test 失败 | 判断是实现 bug 还是测试 bug → 修复 → 重新运行 → 只有全绿才继续 |
| Lint 失败 | 先跑自动修复 → 手动修复遗留错误 → 重新 lint → 继续 |
| Build 失败 | 检查错误消息（通常是 import 或类型）→ 修复 → 重新 build → 继续 |

---

## 何时使用

**前提**：已经通过 `/prp-plan` 生成了 plan 文件

**调用方式**：
```bash
/prp-implement path/to/plan.md
```

**输入**：plan 文件（通常在 `.claude/PRPs/plans/` 目录）

**输出**：
- 实现报告（`.claude/PRPs/reports/`）
- 归档的 plan 文件（`.claude/PRPs/plans/completed/`）
- 当前分支已有全部代码改动，准备进入 code-review

---

## 与 TDD 的区别

| 对比 | `/prp-implement` | TDD 工作流 |
|---|---|---|
| 测试时机 | Phase 4（验证阶段）写测试 | 实现前先写测试（RED） |
| 驱动力 | 代码约定（MIRROR） + 验证循环 | 失败的测试 |
| 流程 | 实现 → 验证 → 修复 → 报告 | RED → GREEN → REFACTOR |
| 最佳场景 | 有明确代码规范、需要快速实现的功能 | 需要严格 TDD 保证、复杂边界用例多 |

**如果项目要求严格 TDD**：在 plan 文件的 Testing Strategy 中明确添加"先写测试"的 Task 步骤，`/prp-implement` 会按任务顺序执行，真正驱动 TDD。

---

## 与其他 PRP 技能的关系

```
/prp-plan
    ↓ (生成 plan.md)
/prp-implement
    ↓ (生成 report.md + 代码改动)
/code-review
    ↓ (审查改动)
/prp-commit
    ↓ (提交改动)
/prp-pr
    ↓ (创建 PR)
```

---

## 成功标准

- ✅ 所有 Task 已执行
- ✅ Type-check 零错误
- ✅ Lint 零错误
- ✅ 所有测试通过，新测试已写
- ✅ Build 成功
- ✅ 实现报告已生成
- ✅ Plan 已归档

---

## 常见陷阱

1. **积累验证失败** — 必须当场修复，不能跳过
2. **忽略 MIRROR 文件** — 不按约定写代码，导致风格不一致
3. **跳过中间验证** — 等所有 Task 完成再验证，浪费修复时间
4. **修改测试而非实现** — 测试失败应该修实现，除非测试本身逻辑错误
5. **遗漏边界用例测试** — Phase 4 第 5 级不能跳过
