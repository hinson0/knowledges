# `/feature-dev` 命令

> 引导式 feature 开发工作流，强调"先理解现有代码，再写新代码"。适合中型功能开发。

## 核心理念

不是直接写代码，而是经过**发现 → 探索 → 设计 → 实现 → 审查**五个阶段，确保新代码与现有架构融合，而不是强行插入。

## 完整流程（7步）

```
Phase 1: Discovery（发现）
  → 仔细阅读需求，识别约束和验收标准
  → 需求模糊时主动提问

Phase 2: Codebase Exploration（代码库探索）
  → 派发 code-explorer agent 分析相关现有代码
  → 追踪执行路径、架构层次、集成点和约定

Phase 3: Clarifying Questions（澄清问题）
  → 呈现探索发现
  → 提出有针对性的设计问题和边界情况
  → 等待用户回复后再继续

Phase 4: Architecture Design（架构设计）
  → 派发 code-architect agent 设计功能
  → 提供实现蓝图
  → 等待用户批准后再实现

Phase 5: Implementation（实现）
  → 按批准的设计实现
  → 适当情况下采用 TDD
  → 小而专注的提交

Phase 6: Quality Review（质量审查）
  → 派发 code-reviewer agent 审查实现
  → 解决关键和重要问题
  → 验证测试覆盖率

Phase 7: Summary（总结）
  → 总结构建内容
  → 列出后续事项或局限性
  → 提供测试说明
```

## 内部 Agent 协作

| Agent | 阶段 | 职责 |
|-------|------|------|
| `code-explorer` | Phase 2 | 深度分析现有代码，追踪执行路径，识别模式 |
| `code-architect` | Phase 4 | 设计实现蓝图，给出文件/接口/数据流方案 |
| `code-reviewer` | Phase 6 | 审查实现质量、安全性、可维护性 |

## 与其他命令的对比

| 命令 | 适合场景 |
|------|----------|
| `/ecc:plan` | 只需要计划文档，手动实现 |
| `/feature-dev` | 中型功能，需要引导式全流程 |
| `/ecc:prp-implement` | 大型功能，PRP 全自动化驱动 |
| 直接对话 | 简单小改动，不需要结构化流程 |

## 关键设计原则

- **先探索再实现**：Phase 2 的 code-explorer 确保新代码遵循现有约定，不是强行插入
- **两次等待确认**：Phase 3（问题澄清）和 Phase 4（设计批准）都需要用户确认再继续，避免跑偏
- **TDD 可选**：Phase 5 用"where appropriate"——不强制，但推荐

## 典型调用

```bash
# 开始一个中型功能
/feature-dev 实现用户头像上传功能，支持裁剪和压缩

# 有明确约束
/feature-dev 给订单列表加分页，复用现有 Pagination 组件
```

---

## ECC 版 vs 官方版对比

ECC 内置了 `/feature-dev`（`commands/feature-dev.md`），官方插件提供 `/feature-dev:feature-dev`，两者流程相同但执行力度差异显著。

### 核心差异：并行 Agent 数量

| 阶段 | ECC `/feature-dev` | 官方 `/feature-dev:feature-dev` |
|------|-------------------|--------------------------------|
| Phase 2 探索 | 1 个 code-explorer | **2-3 个并行**，各聚焦不同维度 |
| Phase 4 设计 | 1 个 code-architect，给一个方案 | **2-3 个并行**，产出 3 种方案让用户选 |
| Phase 6 审查 | 1 个 code-reviewer | **3 个并行**，分别聚焦 DRY/bug/约定 |

### 官方版三个关键增强

**Phase 2 多视角并行探索**
```
Agent 1 → 追踪类似功能的实现
Agent 2 → 高层架构和抽象映射
Agent 3 → UI 模式 / 测试方式 / 扩展点
探索完后，Claude 自己再读 agent 返回的关键文件列表
```

**Phase 4 三种架构方案**
```
方案 A: minimal changes  → 最小改动，最大复用（适合救火）
方案 B: clean arch       → 可维护性，优雅抽象（适合重构）
方案 C: pragmatic        → 速度 + 质量平衡（适合日常开发）
→ 让用户选，而不是直接拍板
```

**Phase 3 标注 CRITICAL + 更强的暂停节点**
- 明确禁止跳过澄清阶段
- Phase 5 明确写 "DO NOT START WITHOUT USER APPROVAL"
- 用户说"你觉得怎样好就怎样"时，必须给出建议并等确认

### 选哪个？

| 场景 | 推荐 |
|------|------|
| 日常中型功能，走偏代价不大 | ECC `/feature-dev`（轻量） |
| 重要功能，一旦走偏代价高 | 官方 `/feature-dev:feature-dev`（重型） |

**本质**：ECC 版是精简单线程，官方版是每个关键节点都上并行多视角的重型版本，用并发换质量。
