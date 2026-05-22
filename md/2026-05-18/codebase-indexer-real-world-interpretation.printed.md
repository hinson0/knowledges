# 真实项目 dependency_stats 解读 · 把图当代码考古工具用

> 来源:week3/day3_workspace · ~/coco/apps/backend 真实压测 + 解读
> 落盘日期:2026-05-18

## 触发提问

- day3 indexer 跑出来 `cycles_found = 0` / `top_imported` 一堆模块,这些数字怎么解读?
- 怎么从依赖图判断项目架构健康度?
- 看到 `structlog` 排在 top imported,能说明什么?

## 关键结论

- **0 cycle 在 production 项目里很罕见**,说明团队有严格 import 纪律(可能配了 import-linter)
- **top_imported 是项目的"重力中心"** —— top 模块影响面大,refactor 高风险
- **基础设施模块(`infra.config` / `infra.database`)排前 = 项目有清晰分层** —— 这是优秀架构信号
- **top_importing 通常是 routers/services > tests** = 典型 FastAPI 分层
- **structlog / pydantic / fastapi 在 top imported = 工程成熟度信号**(对比 print/dict/flask 团队)
- 30 秒跑一次 dependency graph **比读 README 更快了解陌生项目**

## 字段表 · 4 项核心 metric 解读模板

| metric | 你的值 | 解读 |
|---|---|---|
| `total_files` / `indexed_files` | 完成率 100% | 索引器 pipeline 健康(无 read fail / parse fail) |
| `cycles_found` | 0 ✅ / 1-3 ⚠ / 4+ ❌ | 0 = 优秀;1-3 = 常见可接受;4+ = 急需 refactor |
| `unresolved_relative` | < 5 | 接近 0 = 项目结构标准(无奇怪 `.....` 跳出 root) |
| `errors` | < 5% | 接近 0 = 没残缺/编码异常文件 |

## 字段表 · top_imported 模块解读对照

| 模块类型 | 排前的含义 | 真实例子 |
|---|---|---|
| **标准库** | 项目用了主流 Python 特性 | `typing` (13) = 强类型注解;`datetime` (5) = 时间处理 |
| **DB / ORM** | 数据持久化是核心业务 | `alembic` (11) = DB 迁移侵入业务;`sqlalchemy` = ORM |
| **基础设施(项目内)** | 项目有清晰分层 ✅ | `infra.config` (8) = 配置中心化;`infra.database` (5) = DB 抽象 |
| **日志** | 工程成熟度 ✅ | `structlog` (8) = 结构化日志(production-grade) |
| **Web 框架** | 业务封装良好(框架渗透少) | `fastapi` (7) = 业务层做了 router 封装,大部分业务不直接 import fastapi |
| **测试库** | 测试覆盖完整 | `pytest` (5) / `unittest.mock` (5) |

## 字段表 · top_importing_files 解读对照

| 文件位置 | 排前的含义 | 真实例子 |
|---|---|---|
| **routers/** | 路由层集成多个 service,排前正常 | `routers/chat.py` (16) — 业务复杂度高,**潜在 refactor 信号** |
| **services/** | 调用外部 SDK,排第 2 阵 | `services/silicon.py` / `services/tencent.py` (7) |
| **infra/** | ⚠ 排前是**异常信号**(基础设施依赖业务) | `infra/security.py` (6) — 可接受;`infra/database.py` 排前则要警惕 |
| **tests/** | 测试 import 多 mock,占 1-2 位正常 | `tests/test_auth_router.py` (6) |
| **main.py** | 应用入口,排中位正常 | `main.py` (6) |

## 示例 · 真实输出(coco/apps/backend)

```text
🔍 indexing: /Users/a114514/coco/apps/backend  (project_name=backend)
indexing: 100%|████████| 44/44 [00:00<00:00, 1474.98it/s]
✅ index dumped:
   files=44 / 44, symbols=156, imports=156, errors=0

🔗 building dependency graph...
🔄 detecting cycles...

📊 dependency stats:
   total_files          = 44
   total_unique_modules = 56
   cycles_found         = 0       ← 教科书级
   unresolved_relative  = 0       ← 项目结构标准

🥇 top imported modules:
    13 × typing             ← 强类型注解
    11 × alembic            ← DB 迁移
     8 × infra.config       ← ★ 配置中心化(内部 infra)
     8 × structlog          ← ★ 结构化日志(工程成熟度)
     7 × fastapi
     5 × datetime
     5 × infra.database     ← ★ DB 抽象
     5 × pydantic
     5 × pytest
     5 × unittest.mock

📦 top importing files:
    16 × routers/chat.py    ← 业务复杂度最高,refactor candidate
    13 × routers/auth.py
    10 × routers/ocr.py
     9 × routers/sync.py
     7 × services/silicon.py
     7 × services/tencent.py
     6 × infra/security.py
     6 × main.py
     6 × tests/test_auth_router.py
     6 × tests/test_chat_router.py
```

## 字段表 · 数字 → 架构判断推理

| 观察 | 推理 |
|---|---|
| `cycles_found = 0` | 团队有 import 纪律,可能配了 import-linter |
| `infra.config` (8) + `infra.database` (5) 排前 | 清晰的"基础设施层 / 业务层"分层 |
| `structlog` (8) 排前 | production 部署 + 集中式日志栈(ELK / Loki / Datadog) |
| `routers/chat.py` (16) 远超其他 router | chat 业务复杂度高,**refactor 优先 candidate** |
| `services/silicon.py` + `tencent.py` 出现 | 集成了硅基流动 + 腾讯云外部 API |
| **44 文件 × 平均 3.5 symbol × 3.5 import** | 高内聚低耦合的小型 FastAPI 后端典型形态 |

## 坑 / Why

### 0 cycle 在 production 项目里非常少见

**Why**:常见环模式:
- `models.user ⇄ auth.permissions`(用户表 vs 权限表)
- `api.routes ⇄ middleware`(路由 vs 中间件)
- `services ⇄ utils`(服务 vs 工具滥用)

你的项目 0 环 说明:
1. **infra/ 严格单向被依赖**(只被引用,不引用业务)
2. **routers/services/models 严格分层**,无跨层逆向 import
3. coco 团队**做了严格 import 纪律**,或者**有 linter 强制**(如 import-linter / pylint)

**How to apply**:0 cycle 是个**可直接告诉同事的 metric** —— "我跑了静态分析,你们的 import 结构没有任何循环依赖,production-grade 代码质量"。

### structlog 在 top imported 是工程成熟度信号

**Why**:团队用结构化日志 = **production 部署 + 集中式日志栈**。对比用 `print` 或裸 `logging` 的团队,structlog 团队的**可观测性高 1-2 个数量级**。

**How to apply**:
- 当你 week5 接 Langfuse 时,structlog 团队接入会很顺(本来就是 JSON-event-based)
- 用 print 的团队需要先把所有 print 改成结构化日志,**额外 1-2 周工作量**
- **Top imported 模块的选择 = 团队工程成熟度的代理指标**,面试时是个加分点

### top_importing 文件排前的"上帝模块"信号

**Why**:`routers/chat.py` 一个文件 import 16 个模块,**通常是个"业务上帝路由"** —— 把 chat / message / history / streaming / auth 都塞一起。**这是 refactor candidate**。

**How to apply**:
- 看到 `len(forward[file]) > 平均值 × 2` 的文件,优先考虑拆分
- 比较常见的拆分方式:按业务子域(`chat_streaming.py` / `chat_history.py`)、按职责(`chat_handler.py` 调度 + `chat_processor.py` 业务)
- week6 mini-Aider 可以**基于这个 metric 自动生成 refactor proposal**

### `infra/` 不应该出现在 top_importing 前几名

**Why**:基础设施层应该**被业务依赖,不主动依赖业务**(单向依赖原则)。如果 `infra/database.py` 跑进 top_importing 前 3 = 它依赖了业务层的东西 = **架构倒挂**。

**How to apply**:
- 跑完 dependency graph **重点扫一遍 top_importing 里 infra/ 是不是排前**
- 如果是,**立刻 grep 看 infra 文件 import 了什么业务模块**
- 用 import-linter 添加规则:`infra` 不可 import `routers` / `services`

### dependency graph 是新人 onboarding 的"作弊器"

**Why**:**30 秒跑一次比读 README 更快了解陌生项目骨架**。你 30 秒内得知:
1. 项目是 FastAPI 后端
2. 有清晰的 infra/routers/services/tests 分层
3. 配置和数据库被集中管理
4. chat 和 auth 是业务核心
5. 集成了硅基流动 + 腾讯云

**How to apply**:
- 接手任何陌生 Python 项目,**第一步跑 day3 indexer**
- GitHub / GitLab 都集成了 dependency graph 视图,**就是这个用途**
- week6 mini-Aider 用这个 graph 给 LLM 做"项目概览 prompt",**让 Coder agent 第一秒就知道项目骨架**

### 0 unresolved_relative 暴露了项目结构标准化程度

**Why**:`unresolved_relative` 是 day3 `resolve_relative_import` 算不出的相对 import 集合。如果项目用了奇怪的 `......too_deep` 跳出 root 之类,这个数字会上升。**0 表示项目结构跟标准 Python package 一致**。

**How to apply**:
- 这个数字高 = 项目结构非标(可能用了 monkey-patching / 动态 import / namespace package 等高级特性)
- 高 unresolved_relative 项目,RAG 上下文扩展会失败(因为依赖图不完整)
- day3 这个 metric 是 week4 RAG 项目选型的**前置 health check**

## 关联

- [[dependency-graph-schema-and-stats]] — top_imported / top_importing 的算法
- [[dfs-cycle-detection-three-state]] — cycles_found 的算法
- [[relative-import-resolution]] — unresolved_relative 的算法
- `week3/day3_workspace/dependency_graph.json` — coco 项目实际跑出的产物
- `week3/day3_workspace/index.json` — coco 项目 156 symbols / 156 imports 快照
