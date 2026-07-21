# Agent 工具组合策略 — 5 个 codebase 工具的选用规则

## 触发提问

> Week 3 周末任务:在 X 开源项目里改 Y 函数,观察工具组合 — Agent 会 grep 不会 find_def,选错工具

## 关键结论

- **grep_code 是"高召回低精度"钓鱼工具**:不知道 symbol 名时第一秒撒网用
- **find_definition 是"低召回高精度"定位工具**:有 symbol 名后精确锁定定义点 + signature
- **`find_references` 查的是模块级 import,不是函数 call site** — 想查"谁调用了 foo()",**必须用 grep_code**,这是新手最容易选错的工具
- **`get_file_outline` 是"5 秒看完一个 file"** — 替代 read_file 整文件,token 成本 100×
- **`find_imports` 是"完整依赖列表"** — outline 给的 imports 段截断到 top 10,要全部就用这个
- **典型工作流**:grep_code 钓鱼 → find_definition 精确化 → get_file_outline 看上下文 → find_imports 评估依赖

## 5 个工具的精度 / 召回坐标

| 工具 | 召回 | 精度 | 输入类型 | 何时用 |
|---|---|---|---|---|
| `grep_code(pattern)` | 高 | 低 | 字符串/正则 | **不知道 symbol 名,撒网钓鱼** |
| `find_definition(symbol)` | 低 | 高 | symbol 名 | **知道 symbol,要精确定义点** |
| `find_references(module)` | 低 | 高 | **模块名/file 路径** | **看模块被谁 import** |
| `get_file_outline(file)` | 中 | 中 | file 路径 | **5 秒看完一个 file 大纲** |
| `find_imports(file)` | 完整 | 完整 | file 路径 | **拿完整依赖 list** |

## 实战流程(以"评估 is_safe_sql 能否重构"为例)

```
任务: 评估 routers/chat.py 里的 is_safe_sql 函数能否安全重构

Step 1: grep_code('is_safe_sql', root, glob='*.py')
        ↓ 18 条命中 / 3 file
        ↓ 但混杂了定义 / 测试 / 注释 / call site

Step 2: find_definition(index, 'is_safe_sql')
        ↓ 精确锁定: routers/chat.py:L47 kind=function
        ↓ signature: def is_safe_sql(sql: str) -> bool

Step 3: 从 grep 结果减去定义点 → 17 个 "call site / test / 注释"
        ↓ 进一步人工分类:
        ↓   真业务 caller: chat.py:L104, L210 (2 处)
        ↓   测试: tests/test_silicon.py (10 条 test case)
        ↓   注释: 5 条 docstring 引用

Step 4: get_file_outline(index, 'routers/chat.py')
        ↓ chat.py 共 6 个 function,is_safe_sql 是 utility
        ↓ 同 file 兄弟: chat / chat_stream / 3 个 _stream_*

Step 5: find_imports(graph, 'routers/chat.py')
        ↓ 16 条 import,含 sqlalchemy + sqlalchemy.ext.asyncio + infra.security
        ↓ → 这个 utility 跟 SQL 安全紧密相关,删了影响 chat / chat_stream 主流程

Agent 决策:
        真业务 caller 仅 2 处且在同 file
        + test 覆盖良好(10 条 case)
        → 重构成本低,可以做
```

## 选错工具的 3 种典型场景

### ❌ 场景 1:想查函数 caller,用了 `find_references`

```python
# 错的:find_references 是 module 级
refs = find_references(graph, "is_safe_sql")  # → 0 条!
# is_safe_sql 是函数不是模块,find_references 永远返回 0

# 对的:函数 call site 走 grep_code
matches = grep_code("is_safe_sql", root, glob="*.py")
# → 18 条命中,扣掉定义点就是 caller 列表
```

**根因**:`find_references` 走的是 dependency_graph["reverse"],只有 `module → importers` 的映射,没有"函数被谁调用"的层级。函数粒度的反向查找**只能靠 grep**。

### ❌ 场景 2:撒网时用 `find_definition`

```python
# 错的:不知道 symbol 名时盲猜
hit = find_definition(index, "maybe_login_func")  # → 0 条
# LLM 猜错 symbol 名,find_definition 返回空,LLM 误以为"项目里没这功能"

# 对的:不知道 symbol 名时先 grep 钓鱼
matches = grep_code("login", root)
# → 16 条命中,从 content 里识别正确 symbol 名: "authenticate_user"
hit = find_definition(index, "authenticate_user")  # → 精确命中
```

**根因**:`find_definition` 假设你**知道 symbol 名**;grep_code 假设你**只知道关键词**。两步走比一步直达更稳。

### ❌ 场景 3:看一个 file 用 `read_file` 整文件

```python
# 错的:read_file 整个 chat.py
content = open("routers/chat.py").read()  # 500 行,~10k tokens 灌进 context

# 对的:get_file_outline 先看大纲
outline = get_file_outline(index, "routers/chat.py")
# → markdown 大纲 + imports,~500 tokens
# 决定:确实要看 L47-110 的 is_safe_sql 实现,再 read_file 精确范围
```

**根因**:LLM context 是稀缺资源,**只精确读到要看的范围**;outline 决定要看哪一段,read_file 只读那一段。

## 完整工具调用序列(实战记录)

```python
# Step 1: 钓鱼
r1 = grep_code("is_safe_sql", BACKEND, glob="*.py")
# total=18 truncated=False files_hit=3

# Step 2: 精确化
hits = find_definition(index, "is_safe_sql")
# [exact] routers/chat.py:L47 kind=function

# Step 3: 区分定义 vs 调用
def_lines = {(h["file"], h["line"]) for h in hits}
call_sites = [m for m in r1["matches"] if (m["file"], m["line"]) not in def_lines]
# 17 条 call/test/comment

# Step 4: 看上下文
outline = get_file_outline(index, "routers/chat.py")
# 6 functions in chat.py

# Step 5: 看依赖
imps = find_imports(graph, "routers/chat.py")
# 16 imports,含 sqlalchemy + infra.security
```

## 何时用 grep_code,何时用 find_definition?(决策树)

```
有具体 symbol 名?
├─ 没有 → grep_code(关键词)
│        ↓ 看 content,挑出真正的 symbol 名
│        ↓
└─ 有了 → find_definition(symbol)
         ↓ 拿 file:line + signature
         ↓
要找 call site?
├─ 是 → grep_code(symbol)
│       (不要用 find_references!那是 module 级)
└─ 否 → 拿到位置直接 read_file 改代码
```

## 5 个工具的成本对比(LLM context tokens)

| 工具 | 单次输出 token | 何时合算 |
|---|---|---|
| `read_file` 整文件 | 5k-50k(看 file 大小) | 真要改具体代码时 |
| `grep_code` | 100 条 × 50 tok ≈ 5k | 撒网钓鱼,可截断到 100 条 |
| `find_definition` | 1-5 条 × 30 tok ≈ 150 | 拿位置后直接 read_file 那段 |
| `find_references` | 5-50 条 × 20 tok ≈ 500 | 评估改某 module 的影响面 |
| `get_file_outline` | 1 字符串 ≈ 200 | 替代 read_file 整文件 |
| `find_imports` | 10-30 行 ≈ 500 | 评估依赖 |

**经验法则**:**先用低成本工具(outline / find_imports / grep with glob)缩小范围,最后才 read_file 精确段**。

## 坑 / Why

- **"函数粒度 vs 模块粒度"是工具分类的核心**:dependency_graph 只到 module 级,函数级反向查找**只能靠 grep**。这跟 IDE 的 "Find All References" 不同——IDE 走 LSP 能精确到函数级,我们的 day3 indexer 没做这一层
- **`get_file_outline` 的 imports 段截断**(top 10):故意截断防止 outline 太长挤掉 symbols 视觉重点;要完整 imports → `find_imports`,这是**两个工具的分工**
- **同一查询信号在不同工具下的不同表现**:
  - grep "is_safe_sql" → 18 条(全集)
  - find_definition "is_safe_sql" → 1 条(只看定义)
  - find_references "is_safe_sql" → 0 条(函数不是模块)
  - 同样一个名字,三个工具三种答案 — **设计者必须清楚每个工具的 scope**
- **Coding Agent 选错工具的真实代价**:Aider 早期版本经常用 find_references 查函数 caller 拿到 0 条 → 误以为"没人用" → 删了 → 测试挂掉 → 用户怒
- **工具组合的训练价值**:LLM 在 prompt 里被告知"有这 5 个工具",但**何时用哪个、组合顺序怎么排** — 这是 Coding Agent 的"软实力",day4-5 的 5 个工具就是给 LLM 练这种 orchestration 的训练场

## 关联

- [[grep-truncation-self-teaching-signal]] — grep_code 的截断信号
- [[ripgrep-json-events]] — grep_code 底层依赖
- [[llm-tool-actionable-error-tiering]] — 5 个工具的错误处理统一原则
