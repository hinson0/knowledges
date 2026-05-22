# Day 4 LLM Lookup Tools 整体架构

## 触发提问

> "day4 开始"

> "find_definition / find_references / get_file_outline / find_imports 4 个工具怎么设计?"

> 整体 review day4 实现

## 关键结论

- **Day 4 是"数据消费层",对应 Day 2/3 的"数据生产层"** —— parser/index/graph 产出原始/派生数据,Day 4 把它们包成 LLM Tool Calling 函数。
- **4 个工具的"对偶模式"**:`find_definition` + `get_file_outline` 用 CodebaseIndex(forward 方向,"file 里有啥"),`find_references` + `find_imports` 用 DependencyGraph(forward/reverse 方向,"file 之间的关系")。**正好覆盖 day2 + day3 两个索引的 4 种典型查询方向**。
- **LLM Tool Calling 设计 3 要点**:① 输入容错(LLM 传 `User.login` 要能查到 `login`)② 输出 LLM 友好(扁平 dict 优于嵌套,markdown 优于 raw dict)③ `match_mode` 字段标"猜的"还是"精确",**让 LLM 不当 fuzzy 当 exact 用**。
- **不要返回原始 SymbolInfo / dict**,要包成 `DefinitionHit` / `ReferenceHit` 这种"LLM 工具语义"的 schema —— 多一个 `match_mode` 字段就值回票价。
- **Week 6 mini-Aider 的核心数据源就是这 4 个工具** —— Coder agent 第一秒用 `find_definition` 锁定符号 → `find_references` 评估影响面 → 才决定改不改。没有这套 2-step 链路,Coder 就是"瞎改一气"的危险品。

## Schema / 字段表

### 两层架构(数据生产 vs 工具消费)

```
原始数据(facts)          派生视图(derived view)
┌──────────────────┐      ┌──────────────────┐
│ CodebaseIndex    │      │ DependencyGraph  │
│   files[]        │ ───► │   forward        │
│     - symbols    │      │   reverse        │
│     - imports    │      │   cycles         │
└──────────────────┘      └──────────────────┘
       │                          │
       └──── Day 4 工具消费 ──────┘
              │
   ┌──────────┼──────────┐
   ▼          ▼          ▼
find_def  find_refs  get_outline / find_imports
```

### 4 个工具的输入/输出对照

| 工具 | 消费 | 输入 | 输出 | 用途 |
|---|---|---|---|---|
| `find_definition` | CodebaseIndex.files[].symbols | symbol_name + kind? | `list[DefinitionHit]` | "X 定义在哪" |
| `find_references` | DependencyGraph.reverse | module 或 file 路径 | `list[ReferenceHit]` | "谁 import 了 X" |
| `get_file_outline` | CodebaseIndex.files[symbols+imports] | file 路径 | `str` (markdown) | "X 文件有啥" |
| `find_imports` | DependencyGraph.forward | file 路径 | `list[str]` | "X 文件 import 了啥" |

### DefinitionHit Schema

| 字段 | 类型 | 语义 |
|---|---|---|
| `file` | str | 命中所在文件相对路径 |
| `line` | int | 起始行(1-based,含装饰器) |
| `kind` | `Literal["function", "class"]` | 符号种类 |
| `name` | str | 规范化后的符号名(剥点后) |
| `signature` | str | 签名字符串 |
| `match_mode` | `Literal["exact", "fuzzy"]` | **关键信号**:LLM 用来判断"是不是猜的" |

### ReferenceHit Schema

| 字段 | 类型 | 语义 |
|---|---|---|
| `module` | str | 归一化后的 module 字符串(非用户传入原样) |
| `importer` | str | import 它的文件路径 |

**没有 match_mode 字段** —— 因为 ReferenceHit 是字符串精确匹配,没有"猜的"概念。

## 代码示例

### 4 个工具的统一签名风格

```python
def find_definition(
    index: CodebaseIndex,
    symbol_name: str,
    kind: Literal["function", "class"] | None = None,
) -> list[DefinitionHit]: ...

def find_references(
    graph: DependencyGraph,
    target: str,
) -> list[ReferenceHit]: ...

def get_file_outline(
    index: CodebaseIndex,
    file_path: str,
) -> str: ...

def find_imports(
    graph: DependencyGraph,
    file_path: str,
) -> list[str]: ...
```

**风格统一**:第一个参数永远是数据源(index 或 graph),后面是 query 参数。

### LLM 工具设计 3 要点(反例对比)

```python
# ❌ 反例 1:输出 raw SymbolInfo
def find_definition_bad(...) -> list[SymbolInfo]:
    return [sym for ...]   # 缺 file 字段!LLM 不知道在哪个文件

# ❌ 反例 2:嵌套 dict
{
    "module_info": {"name": "...", "kind": "internal"},
    "importer_info": {"path": "...", "type": "file"},
}
# LLM 要多 parse 一层,字段冗余(kind: internal 用不上)

# ❌ 反例 3:raise Exception
def find_definition_bad2(...):
    if not hits:
        raise NotFoundError("...")   # tool calling 不要 raise
# 应该:return []  让 LLM 看空 list 自判

# ✅ 正确:扁平 DefinitionHit + match_mode 标信号 + 空 list 表示 miss
```

## 坑 / Why

### Why 用 TypedDict 构造器而不是 dict literal

```python
# ✅ 推荐:kwargs 构造,Pyright 检查字段名/类型/必填
DefinitionHit(
    file=file["path"],
    line=sym["start_line"],
    kind=sym["kind"],
    name=sym["name"],
    signature=sym["signature"],
    match_mode="exact",
)

# ⚠ 危险:dict literal,Pyright 不检查字段(漏写 match_mode 静默通过)
{"file": ..., "line": ..., ...}

# ⚠ 也危险:dict 包一层 cast,Pyright 当 type cast 不检查
DefinitionHit({"file": ..., "line": ..., ...})
```

**TypedDict 最大的坑**:`Type(...)` 走 kwargs 检查,`Type({...})` 走 cast 不检查 —— 长得像但语义完全不同。

### Why match_mode 字段必须存在

LLM 看 `match_mode: "fuzzy"` 心想:"我猜的,该检查一下"。
不带这个字段 → LLM 把 fuzzy 当 exact 用 → 后续 apply_patch 修错文件。
**1 个字段省 30% LLM 幻觉**。

### Why outline 返回 string,其他返回 list[dict]

`get_file_outline` 输出"给 LLM 看的概览" → markdown 字符串 LLM 解析最快(L24 / 🔸 等高密度信号原地展示)。
其他 3 个工具输出"给 LLM 进一步推理的数据" → 结构化 dict 利于 LLM 按字段读取。
**正确判断"该结构化 vs 该 markdown"是 tool 设计高阶技能**。

## 关联

- [[find-definition-two-phase-design]] — find_definition 的两阶段匹配
- [[find-references-init-normalization-bug]] — find_references 的归一化 + bug
- [[get-file-outline-markdown-rendering]] — outline 的 markdown 渲染
- [[codebase-index-vs-graph-layering]] — 为什么 facts/view 分层
