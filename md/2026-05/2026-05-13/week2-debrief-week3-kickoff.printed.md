# Week 2 通关复盘 + Week 3 启动菜单

> 来源:`week2/day5_workspace/0513/0855.md`(Week 2 收尾 + Week 3 起手)
> 落盘日期:2026-05-13

## 概念

Week 2 通关 = LangGraph 框架的完整体感(state schema / control flow / persistence / HITL / RAG)。**整周都是"框架体感 + 踩坑修复"**。Week 3 切换到 hands-on AST 工具链(tree-sitter / static analysis),为 Week 4 代码 RAG 准备数据预处理层。

## 字段表 · Week 2 五天能力堆栈

| Day | 掌握的能力 | 简历可写的 metric |
|---|---|---|
| Day 1-2 | LangGraph StateGraph / TypedDict / `add_messages` reducer | "用 LangGraph 重写 Week 1 Agent,代码量减半,可视化拓扑" |
| Day 3 | Checkpointer / SQLite saver / 跨进程 resume / thread 隔离 | "实现 3 种 saver 切换 + thread 隔离,验证中断后续跑准确率 100%" |
| Day 4 | HITL `interrupt()` / `Command(resume)` / 破坏性操作 gating | "实现工具调用人工审批,3 层防御范式(边路由 + node + execute 断言)" |
| Day 5 | 自建 RAG / SQLite + bge-m3 / 跨 thread 长期记忆 | "10 条 mock + 6 个 query 测得 score 分布(命中 0.62 / 噪音 < 0.50),阈值调到 0.55 后召回准确率 X%" |

## CLAUDE.md 留白 · Plan-and-Execute

CLAUDE.md Week 2 路线图里的 **Plan-and-Execute**(Day 3 任务)被跳过 —— 直接做了 checkpointer。这不是 bug:

- ✅ Week 6 mini-Aider 会做 Planner + Coder + Reviewer 的 multi-agent subgraph,**Plan-and-Execute 是它的子集**,届时一并补
- ⚠ 简历 "Plan-and-Execute 拆步" 这条 metric 暂时没有,Week 6 完成后补上

## 字段表 · Week 2 周末收尾任务

| # | 任务 | 对应 CLAUDE.md 铁律 |
|---|---|---|
| 1 | 录 30s demo gif(thread1 植入 → thread2 召回 → LLM 真的引用了事实) | 铁律 2 — 每天必有可演示产出 |
| 2 | 写 `week2/README.md`(架构图 + 关键 metric + 踩坑 highlights) | 铁律 3 — 每周必有 README |
| 3 | 知识落盘(用 `summary` skill 把 day5 流水笔记整合到 `~/knowledges/md/2026-05-13/`) | 沉淀 |

**README 必含的 metric**:score 分布数字、channel 冲突踩坑、triple-quoted 缩进、int vs float env 解析。**这些都是"真实数字 + 真实坑"**,符合铁律 4。

## 字段表 · Week 3 一周节奏

| Day | 任务 | 故意会踩的坑 |
|---|---|---|
| 1 | `tree-sitter-python` 装通,提取一个文件的所有函数/类 | macOS 上 tree-sitter 编译可能炸,要学查 issue |
| 2-3 | 扩到整个项目(FastAPI 源码),输出 `index.json` | 循环 import 让递归索引爆栈 |
| 4 | 新工具:`find_definition` / `find_references` / `get_file_outline` | LLM 传 `User.login` 而不是 `login`,查找失败 |
| 5 | `grep_code` 工具,内部调 ripgrep 子进程 | rg 输出 10k 行直接撑爆 context |

## 示例 · Week 3 Day 1 起手菜单(下周一首小时)

```bash
# 1. 装依赖(language-pack 比单 lang 包好,免编译)
uv add tree-sitter tree-sitter-language-pack
```

```python
# 2. 最小 demo:解析一个 Python 文件 → 打印所有 def + class 名字
from tree_sitter_language_pack import get_parser

parser = get_parser("python")
with open("some_file.py", "rb") as f:
    tree = parser.parse(f.read())
# TODO 遍历 tree,提取 function_definition / class_definition 节点
```

```bash
# 3. 真实项目:挑 FastAPI 的 fastapi/applications.py 提取所有函数
```

## 字段表 · Week 3 Day 1 设计三问

| 问题 | 选项 | 推荐 | 理由 |
|---|---|---|---|
| Q1. 索引粒度 | (A) 函数级 / (B) 类级 / (C) 文件级 | **A 函数级** | Week 4 chunking 也按函数切,粒度对齐 |
| Q2. 输出格式 | (A) 内存 dict / (B) JSON / (C) SQLite | **B JSON 起步** | Week 4 切 SQLite,中间产物用 JSON 方便人肉看 |
| Q3. 索引信息 | (A) 只名字 / (B) 名字 + 起止行 / (C) 名字+行+签名+docstring | **C 全字段** | Week 4 RAG 召回时这些 metadata 全用得上 |

## 坑 / Why

### 抽象周 / 具体周交替设计

**结论**:Week 2 → Week 3 是一次"风格转换"。Week 2 学的是抽象(LangGraph 框架),Week 3 学的是具体(AST 工具链)。

**Why**:这种"抽象周 / 具体周"交替是 8 周路线刻意设计的,**防止你在某一种思维模式里疲劳**。Week 4 又回到抽象(RAG 算法),Week 5 又回到具体(工程化)。reverse-Pomodoro 式的认知切换,8 周下来脑子会变得很灵活。

**How to apply**:遇到 Week 3 入门 tree-sitter 感觉跟 Week 2 LangGraph 思维路径完全不同 → 是正常的、有意为之的认知切换,不要试图把 Week 2 的范式硬套到 Week 3。

### Memory 是横跨 Week 2-8 的资产

**结论**:`day5_workspace/memories.sqlite` 文件不要删,后面几周一直会用。

**Why**:memory 库不是 Week 2 的"产出",是横跨 Week 2-8 的"资产"。Week 6 mini-Aider 的 Coder agent 可以查 memory 知道"用户偏好递归 vs 迭代";Week 7 evaluation 系统可以查 memory 知道"用户做的是哪类项目以选 testcase"。

**How to apply**:
- day5 用 SQLite 而不是 `InMemoryStore` 就是为了**持久化跨周积累**
- Week 3-8 写新代码时,先想"这个事实/规则要不要存进 memory 让以后的 agent 用"
- Week 7 评估系统会引入 `STORE.search` 选 testcase,届时 memory 库内容直接复用

### 路线图是 spec,不是合同

**结论**:CLAUDE.md Week 2 跳过 Plan-and-Execute 是合理的优先级判断。

**Why**:真实工程项目里,需求文档跟实际开发顺序经常不一致。**关键是知道你跳过了什么 + 什么时候补**。Week 6 mini-Aider 自然回头做 multi-agent,届时这条"留白"就闭环了。

**How to apply**:
- 新人会强迫自己跟 spec,资深工程师带着 spec 走自己的节奏
- 跳过任何任务时,**显式记录"跳过的是什么、何时补"**(像本篇这种"留白"声明)
- 简历写 metric 时,只写**真正做过的**,不要按 spec 假定的能力描述

## 字段表 · 当前节奏推荐

| 时间 | 任务 |
|---|---|
| 今天 2026-05-13 周三 | 跑端到端剧本录 30s gif;写 `week2/README.md` |
| 周四-周五 (5-14 / 5-15) | 知识落盘(用 summary skill);跟人吹一遍 RAG 故事 — 能讲清楚才算真懂 |
| 周一 (Week 3 Day 1) | `uv add tree-sitter tree-sitter-language-pack`;最小 demo 提取函数 |

## 关联

- [langgraph-rag-memory-3-step-plan.printed.md](./langgraph-rag-memory-3-step-plan.printed.md) — day5 三步收口路线图(取/注/存)
- [agentstate-cross-day-reuse.md](./agentstate-cross-day-reuse.md) — Week 2 后期的工程化收尾(state schema 跨 day 复用)
- [../2026-05-10/hitl-design-protocol.md](../2026-05-10/hitl-design-protocol.md) — Day 4 HITL 设计推理链
- [../2026-05-10/dangerous-op-gating.md](../2026-05-10/dangerous-op-gating.md) — Day 4 破坏性操作三层防御
- `CLAUDE.md` — 8 周路线总览(根目录)
- `week2/day5_workspace/day5_memory.py` — Week 2 收尾代码
- `week2/day5_workspace/memories.sqlite` — 跨周持久化 memory 库

---

来源:`week2/day5_workspace/0513/0855.md`
落盘日期:2026-05-13
