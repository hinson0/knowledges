# tree-sitter Python · Parser 初始化与 Node Schema

> 来源:week3/day1_workspace + day2_workspace 会话提炼
> 落盘日期:2026-05-13

## 触发提问

- "TypeError: __init__() argument 1 must be tree_sitter.Language, not PyCapsule" 怎么解决?
- `root.type` 和 `children` 是什么意思?
- `for node in root.children:` 每一个 node 的 schema 是什么?
- `dotted_name` 怎么理解?

## 关键结论

- tree-sitter 0.22+ 要求 `Parser(Language(python_language()))`,**不能直接传 `python_language()`(PyCapsule)**
- 所有 AST 操作通过 **Node 对象的属性 + 方法**,Node 不是 dict 而是 C 指针的 lazy 包装
- Python grammar 的节点类型分两类:**带名节点**(`function_definition` / `dotted_name` 等)和**语法 token**(`","` / `"def"` 等)
- 节点信息通过 **`type` / `text` / `start_point` / `children` + `child_by_field_name`** 五件套获取
- **`ERROR` 节点** 是 tree-sitter 宽容解析的产物,真实项目索引必须 `continue` 跳过

## Schema · Node 对象 API 五件套

### 基础元信息

| 属性/方法 | 类型 | 含义 | 例子(`import os` 节点) |
|---|---|---|---|
| `node.type` | `str` | grammar 定义的节点类型名 | `"import_statement"` |
| `node.text` | `bytes \| None` | 节点对应源码片段(**字节,不是 str**) | `b"import os"` |
| `node.is_named` | `bool` | grammar 里有名字 vs 语法 token | True / False |
| `node.is_missing` | `bool` | grammar 幻觉出的占位节点 | False |
| `node.has_error` | `bool` | 子树内是否有语法错误 | False |

### 位置信息(切原文 / 算行号用)

| 属性 | 类型 | 含义 | 例子 |
|---|---|---|---|
| `node.start_point` | `(row, col)` tuple | 起点,**0-based** | `(0, 0)` |
| `node.end_point` | `(row, col)` tuple | 终点 | `(0, 9)` |
| `node.start_byte` | `int` | 起点字节偏移 | `0` |
| `node.end_byte` | `int` | 终点字节偏移 | `9` |

### 树结构导航

| 属性/方法 | 返回 | 含义 |
|---|---|---|
| `node.children` | `list[Node]` | **所有**直接子节点(含语法 token) |
| `node.named_children` | `list[Node]` | 只含 `is_named=True` 的子节点 |
| `node.child_count` | `int` | children 数量 |
| `node.parent` | `Node \| None` | 父节点 |
| `node.next_sibling` / `prev_sibling` | `Node \| None` | 兄弟节点 |

### 字段访问(核心特性)

| 方法 | 返回 | 含义 |
|---|---|---|
| `node.child_by_field_name(name)` | `Node \| None` | 取**单个**命名字段子节点 |
| `node.children_by_field_name(name)` | `list[Node]` | 取**多个**同名字段子节点 |

**关键概念**:`children` 是 grammar 解析出的**所有**子节点(扁平 list),`child_by_field_name` 是按 grammar 作者**人为指定的语义角色**取。

## 字段表 · AST 节点类型大全

| 节点类型 | 出现位置 | children 结构特点 |
|---|---|---|
| `module` | 文件顶层 root | children 是顶层语句的扁平 list |
| `function_definition` | 函数定义 | field `name` → identifier;field `parameters` → parameters;field `body` → block |
| `class_definition` | 类定义 | field `name` → identifier;field `body` → block |
| `decorated_definition` | `@decorator` 后跟 def/class | children 含 N 个 decorator + 1 个 function/class_definition |
| `import_statement` | `import X` / `import X, Y` | field `name` → 多个 dotted_name |
| `import_from_statement` | `from X import Y, Z` | field `module_name` → dotted_name/relative_import;field `name` → 多个 dotted_name |
| `dotted_name` | 限定名字(`os` / `os.path`) | "可能带点的名字",0 个或多个点都算同一类型 |
| `relative_import` | `.` / `..models` | children = `import_prefix`(N 个点)+ 可选 dotted_name |
| `ERROR` | 语法错误时 grammar 幻觉 | 包装一段无法解析的源码,**必须 continue 跳过** |
| `expression_statement` | 任何表达式语句 | 包装真实 expression |

## 示例 · 4 类 import 的 Node 内部结构

```python
import os
# → import_statement
#     ├── "import" (keyword token)
#     └── dotted_name "os" (field name="name")

import os, sys
# → import_statement
#     ├── "import"
#     ├── dotted_name "os"
#     ├── ","
#     └── dotted_name "sys"

from typing import TypedDict, Annotated
# → import_from_statement
#     ├── field "module_name" → dotted_name "typing"
#     └── 多个 field "name" → dotted_name "TypedDict" + dotted_name "Annotated"

from . import foo
# → import_from_statement
#     ├── field "module_name" → relative_import "."  (注意:不是 dotted_name!)
#     └── field "name" → dotted_name "foo"

from ..models import User
# → import_from_statement
#     ├── field "module_name" → relative_import "..models"
#     │     ├── import_prefix ".."
#     │     └── dotted_name "models"
#     └── field "name" → dotted_name "User"
```

## 示例 · dump_node debug 神器

写 extract_xxx 前先用这个看 AST 结构:

```python
def dump_node(node, indent=0, max_depth=3):
    """递归打印 node 树结构,debug 时神器。"""
    if indent > max_depth * 2:
        return
    pad = "  " * indent
    text = node.text.decode("utf-8", errors="replace")[:40]
    named = "★" if node.is_named else "·"
    print(f"{pad}{named} {node.type:30s} text={text!r}")
    for child in node.children:
        dump_node(child, indent + 1, max_depth)


# 用法:把疑难源码丢进去看结构
sample = """import os, sys
from typing import TypedDict, Annotated
from . import foo
"""
root = parse_code(sample)
for child in root.children:
    dump_node(child)
    print("---")
```

输出会一目了然展示每层节点的 type + text + named 状态。

## 示例 · Parser 初始化(0.22+ 升级踩坑)

```python
# ❌ 老写法(报错:argument 1 must be tree_sitter.Language, not PyCapsule)
from tree_sitter import Parser
from tree_sitter_python import language as python_language
PARSER = Parser(python_language())

# ✅ 新写法(0.22+ 强制要求 Language 包装)
from tree_sitter import Language, Parser
from tree_sitter_python import language as python_language
PARSER = Parser(Language(python_language()))

# ✅ 等价的"懒省事"方案(fallback)
from tree_sitter_language_pack import get_parser
PARSER = get_parser("python")
```

**PARSER 跟 Language 都是可复用的"编译好的语法",module-level 实例化一次即可**,后续 parse 多个文件共享同一个 PARSER 不要重建(性能差几个数量级)。

## 坑 / Why

### PyCapsule 升级是为类型安全

**Why**:`PyCapsule` 是 CPython 提供的"裸 C 指针包装",不透明,无类型。老版 `Parser.__init__` 接受裸指针不安全。0.22+ 强制 `Language(capsule)` 包一层,让"裸 C 指针"升级成"有类型的 Python 对象"。

**How to apply**:看到 `must be X, not Y` 形态的 TypeError,先去库的 changelog 找最近的 API breaking change;tree-sitter 这种 native 库一年内的破坏性变更不少。

### `dotted_name` 是"可能带点的名字",不是"必须带点"

**Why**:grammar 作者不想为 `os` 和 `os.path` 写两套规则,**统一一个 `dotted_name` 类型**,0 个点也合法。Python `ast` 模块用相反策略(`ast.Name` vs `ast.Attribute` 是两个类),tree-sitter 的"轻类型 + 重 field"路线更扁平,跨语言 grammar 维护成本更低。

**How to apply**:
- 直接 `node.text.decode()` 拿整体字符串,不要拆点
- 真要拆只用 `name.split(".")` Python 层处理,不依赖 grammar 子节点

### `node.text` 是 `bytes` 不是 `str`,`start_point` 是 0-based

**Why**:tree-sitter 是跨语言 C 库,Python str 是 unicode 对象 C 不认;0-based 是 C 风格。`.decode("utf-8")` + `+1` 是 Python 层对 C 行为的"礼貌包装"。

**How to apply**:
- 取文本必须 `.text.decode("utf-8")` 或更安全 `(node.text or b"").decode("utf-8")`
- 取行号必须 `start_point[0] + 1` 转 1-based(对齐编辑器视角)

### `ERROR` 节点要主动跳过

**Why**:tree-sitter 是"宽容解析"——遇语法错不死,猜一个合理的 AST 继续。这让你能 parse 半成品代码(IDE 实时补全场景),但 indexer 必须主动 `continue ERROR`,否则提取的 symbols/imports 会包含幻觉垃圾。

**How to apply**:
```python
for node in root.children:
    if node.type == "ERROR":
        continue
    ...
```

day3 索引真实项目时这条防御一定要加(否则 1 个残缺文件可能让你的 indexer 输出几十条幻觉 import)。

## 关联

- [[ast-range-vs-identity-node-pattern]] — decorated_definition 处理的"范围节点 vs 身份节点"分离
- [[codebase-indexer-design-patterns]] — 基于这套 API 的工程化设计
- `week3/day1_workspace/day1_indexer.py` — extract_symbols 实战
- `week3/day2_workspace/day2_indexer.py` — extract_imports 实战
