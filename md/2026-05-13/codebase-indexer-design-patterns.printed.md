# Codebase Indexer · 工程设计模式(day2)

> 来源:week3/day2_workspace · index.json 多文件索引器全程设计
> 落盘日期:2026-05-13

## 触发提问

- 把单文件 extract_symbols 扩到整个项目,产出 index.json 怎么设计?
- `from typing import a, b, c` 多名字怎么记?拆 N 条还是一条?
- "module 留空不是更好吗?"
- `node.text.decode()` Pylance 报 "decode 不是 None 的已知属性" 怎么修?
- `Path.relative_to()` 怎么用,给我 mock 数据
- `index_file` 返回 None 怎么收集到 error_files?

## 关键结论

day2 完成了一个完整的索引引擎冷启动 pipeline:**文件枚举 → AST 解析 → 多类型节点处理 → 错误兜底 → 结构化产出**。核心设计原则:

1. **三层 Schema**(ImportInfo / FileIndex / CodebaseIndex)分别承担"单条 import / 单文件 / 整项目"的语义
2. **消费者驱动**:`module` 字段永远填全(`import os` 也填 `module="os"`),让消费方 grep 一个字段就够
3. **结构差异分别处理**:`import a, b` 拆 N 条(对齐运行时 N 次 `__import__`);`from x import a, b, c` 一条(module 共享)
4. **错误就近处理**:`index_file` 内部 try-except → return None;上层只看 None/非 None 分流
5. **路径标准化**:存相对路径 + POSIX 风格(`.as_posix()`),index.json 跨机器 + 跨平台可移植
6. **Optional 类型在边界收窄**:`_text(node)` helper 一次性把 `Optional[bytes]` 收窄成 `str`,后续代码全程 str

## Schema · ImportInfo / FileIndex / CodebaseIndex

```python
from typing import TypedDict


class ImportInfo(TypedDict):
    """单条 import 语句的结构化表达。
    
    Schema:
        module:  被 import 的模块路径
                 - `import os`            → module = "os"
                 - `import os.path`       → module = "os.path"
                 - `from typing import X` → module = "typing"
                 - `from . import foo`    → module = "."(相对 import,不解析)
                 - `from ..models import` → module = "..models"
        names:   导入的具体名字 list
                 - `import os`                → ["os"]
                 - `from typing import X, Y`  → ["X", "Y"]
                 - `from x import *`          → ["*"]
        is_from: 是否是 from-import(决定 module 字段的语义)
        line:    源码里第几行(1-based,跟 SymbolInfo 对齐)
    """
    module: str
    names: list[str]
    is_from: bool
    line: int


class FileIndex(TypedDict):
    """单个 .py 文件的索引快照。"""
    path: str                    # 相对项目 root 的路径(跨机器可移植)
    symbols: list[SymbolInfo]    # day1 的 SymbolInfo
    imports: list[ImportInfo]    # day2 新增


class CodebaseIndex(TypedDict):
    """整个项目的索引快照,会被 dump 成 index.json。"""
    root: str                    # 索引根目录绝对路径(跨机器消费者忽略)
    files: list[FileIndex]       # 按 path 字典序排序
    stats: dict                  # 见下方 stats schema
```

### Stats 子 schema(可调试性的关键)

| 字段 | 类型 | 用途 |
|---|---|---|
| `total_files` | int | 扫描到的总数 |
| `indexed_files` | int | 成功索引数 |
| `error_files` | **list[str]** | 失败文件路径列表(**不是数字!**) |
| `total_symbols` | int | `sum(len(f["symbols"]) for f in files)` |
| `total_imports` | int | `sum(len(f["imports"]) for f in files)` |

**关键设计**:`error_files` 存 list 而非 int —— Week 4 RAG 调优时"为什么这个文件搜不到"一查 `error_files` 立刻定位。

## 示例 · `_text` helper(Optional[bytes] 边界收窄)

tree-sitter `node.text` 类型标注是 `Optional[bytes]`(边界 case:`node.edit()` 后未重 parse / `is_missing=True` 节点),直接 `.decode()` 触发 Pylance 警告。

```python
from tree_sitter import Node


def _text(node: Node) -> str:
    """安全提取 node 对应原文为 str。
    
    把 Optional[bytes] 收窄为 str,避免 Pylance 警告 + None 崩溃风险。
    fail-quiet:None 时 fallback 空字符串(production-grade,不让一个奇怪节点搞死索引器)。
    """
    return (node.text or b"").decode("utf-8")
```

**4 种修法对比**:

| 修法 | 代码 | 评价 |
|---|---|---|
| **helper(推荐)** | `_text(node)` | ✅ 一处定义全文件用,边界 case 兜底 |
| assert 收窄 | `text = node.text; assert text is not None; text.decode()` | 啰嗦,不推荐 |
| cast 强断言 | `cast(bytes, node.text).decode()` | "跟类型系统打架",简历项目避免 |
| `# type: ignore` | `node.text.decode()  # type: ignore[union-attr]` | 下下策,等于关报警 |

## 示例 · extract_imports(完整正确版)

```python
def extract_imports(source: str) -> list[ImportInfo]:
    """从源码提取所有顶层 import 语句。"""
    root = parse_code(source)
    imports: list[ImportInfo] = []

    for node in root.children:
        if node.type == "ERROR":
            continue                                          # ⚠ 防御 ERROR 节点

        line = node.start_point[0] + 1

        if node.type == "import_statement":
            # `import a, b` → 拆 N 条 ImportInfo
            # 对齐 Python 运行时 N 次 __import__ 调用
            for mod_node in node.children_by_field_name("name"):
                mod = _text(mod_node)
                imports.append(ImportInfo(
                    module=mod,
                    names=[mod],                              # 跟 module 同名(冗余但对齐 schema)
                    is_from=False,
                    line=line,
                ))

        elif node.type == "import_from_statement":
            module_node = node.child_by_field_name("module_name")
            module = _text(module_node) if module_node else ""
            names = [_text(n) for n in node.children_by_field_name("name")]
            imports.append(ImportInfo(
                module=module,
                names=names,                                  # `from x import a, b` 一条记录
                is_from=True,
                line=line,
            ))

    return imports
```

## 示例 · index_file + Path.relative_to

```python
def index_file(path: Path, root: Path) -> FileIndex | None:
    """把一个 .py 文件 parse 成 FileIndex,失败返回 None。"""
    try:
        source = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError) as e:
        print(f"⚠ skip {path}: {type(e).__name__}: {e}", file=sys.stderr)
        return None

    symbols = extract_symbols(source)
    imports = extract_imports(source)

    # ⚠ .as_posix() 强制 / 分隔,跨平台 git diff 干净
    rel_path = path.relative_to(root).as_posix()

    return FileIndex(path=rel_path, symbols=symbols, imports=imports)
```

### Path.relative_to 实例

```python
from pathlib import Path

root = Path("/Users/me/code/week3")
file = Path("/Users/me/code/week3/day1_workspace/day1_indexer.py")

file.relative_to(root)             # → PosixPath('day1_workspace/day1_indexer.py')
file.relative_to(root).as_posix()  # → 'day1_workspace/day1_indexer.py'

# 边界 case
Path("/repo").relative_to(Path("/repo"))            # → PosixPath('.')
Path("/other/x.py").relative_to(Path("/repo"))      # → ValueError: '/other/x.py' is not in the subpath of '/repo'
Path("a/b.py").relative_to(Path("/repo"))           # → ValueError: one absolute, one relative
```

**day3 防御**(symlink 跳出 root 时):
```python
try:
    rel_path = path.relative_to(root).as_posix()
except ValueError:
    return None
```

## 示例 · index_codebase 主循环(error_files 收集)

```python
def index_codebase(root: Path, use_tqdm: bool = True) -> CodebaseIndex:
    files: list[FileIndex] = []
    error_files: list[str] = []
    py_files = walk_python_files(root)

    if use_tqdm:
        from tqdm.auto import tqdm   # ⚠ .auto 兼容 Jupyter + CLI
        iterator = tqdm(py_files, desc="indexing")
    else:
        iterator = py_files

    for path in iterator:
        file_index = index_file(path, root)
        if file_index is None:
            error_files.append(path.relative_to(root).as_posix())   # ← 记路径,不只是计数
        else:
            files.append(file_index)

    stats = {
        "total_files":   len(py_files),
        "indexed_files": len(files),
        "error_files":   error_files,
        "total_symbols": sum(len(f["symbols"]) for f in files),
        "total_imports": sum(len(f["imports"]) for f in files),
    }

    return CodebaseIndex(root=str(root), files=files, stats=stats)
```

## 字段表 · 9 条 mock fixture(extract_imports 验证用)

```python
sample = """import os
import os, sys
import os.path
from typing import TypedDict
from typing import TypedDict, Annotated, NotRequired
from . import foo
from ..models import User
from ..models.user import User, Role
"""

expected_imports: list[ImportInfo] = [
    {"module": "os",      "names": ["os"],       "is_from": False, "line": 1},
    {"module": "os",      "names": ["os"],       "is_from": False, "line": 2},   # ← 拆出
    {"module": "sys",     "names": ["sys"],      "is_from": False, "line": 2},   # ← 拆出
    {"module": "os.path", "names": ["os.path"],  "is_from": False, "line": 3},
    {"module": "typing",  "names": ["TypedDict"], "is_from": True, "line": 4},
    {"module": "typing",  "names": ["TypedDict", "Annotated", "NotRequired"],
     "is_from": True, "line": 5},                                                # ← 一条
    {"module": ".",       "names": ["foo"],      "is_from": True, "line": 6},
    {"module": "..models",       "names": ["User"],         "is_from": True, "line": 7},
    {"module": "..models.user",  "names": ["User", "Role"], "is_from": True, "line": 8},
]

assert len(extract_imports(sample)) == 9, "expected 9, got different count"
```

## 坑 / Why

### 消费者驱动设计:`module` 字段填全 vs 留空

**Why**:`import os` 这种"非 from-import"语法上确实没有 from 模块,留空看起来"语法精确"。但**消费方查"谁 import 了 os"时**:
- 留空 → 必须 `if is_from: ... else look in names` 双分支
- 填全 → `module=="os"` 一个条件搞定,is_from 都不用看

**How to apply**:写 schema 时不要光想"我现在产出什么自然",要想"消费方查询时什么字段最顺手"。**让消费方少 1 行 if-else,你这步多 1 行赋值**,这是 API 设计的总成本最低化。

### `import a, b` 拆 N 条 vs 一条 的选择 = 跟运行时模型对齐

**Why**:`import os, sys` 在 Python 解释器内部是**先后两次** `__import__` 调用,所以语义上是 2 件事;但 `from x import a, b` 是 1 次 `__import__("x")` + 取 2 个名字,语义上是 1 件事。**拆与不拆跟 AST 表面无关,跟运行时模型对齐**。

**How to apply**:写 parser/extractor 输出时,问自己"运行时这是 1 件事还是 N 件事";不是 1 件事就拆,**避免下游消费方自己再拆**(责任放在最早能拆的位置)。

### Optional 是个传染病,要在边界集中处理

**Why**:`Optional[T]` 一旦进入代码,所有用到它的地方都要处理 None,**会病毒式扩散**。最优策略是在系统边界(进入 indexer 内部前)收窄成 `T`,内部全程 `T` 不再传染。`_text` helper 就是这个边界。

**How to apply**:
- tree-sitter API 暴露的 Optional:`parent` / `next_sibling` / `child_by_field_name` / `text`
- 进 indexer 内部前用 helper 收窄;helper 内部 fallback("" / 跳过 / 默认值)
- production-grade:Pydantic V2 / msgspec 在系统入口处 strict validate,内部全程 strict types

### `error_files: list[str]` vs `errors: int` = observability 的萌芽

**Why**:存数字 = 信息损失,你只知道"5 个失败"不知道是哪 5 个;存 list 让"错误本身变成结构化数据,不是日志副作用"。Week 5 接 Langfuse / Sentry 时,所有 trace 都要可序列化 —— **day2 这一步建立"错误也是数据"的思维**。

**How to apply**:
- 任何"统计 + 排查"两用的场景,都存 list 而不是 count
- day3 可以再升级为 `list[dict]`,每条带 `{"path": ..., "error_type": ..., "error_msg": ...}`
- schema 演化原则:**追加字段(append-only)而不是改字段语义**

### `.as_posix()` 是 production-grade 跨平台代码的真实需求

**Why**:Mac/Linux 默认 `/` 分隔,Windows `str(path)` 给反斜杠 → git diff 出大问题,JSON 跨 OS 不可读。`.as_posix()` 强制 `/`。

**How to apply**:所有"写进 JSON / 跨进程 / commit 进 git" 的路径字段,**统一 `.as_posix()`**;不写 `str(path)`。**Web / 容器 / CI/CD 全是 POSIX 标准**,你 macOS 本地不用 `.as_posix()` 也能跑,但 Windows 同事 git pull 后立刻崩。

## 关联

- [[tree-sitter-python-node-schema]] — Node API 基础
- [[ast-range-vs-identity-node-pattern]] — day1 extract_symbols 的"范围/身份"分离
- [[tqdm-naming-and-auto]] — tqdm.auto 在 indexer 的应用
- [[string-escape-and-rerun-discipline]] — `\\n` vs `\n` 引发的 ERROR 节点 case
- `week3/day2_workspace/day2_indexer.py` — 完整实现
- `week3/day2_workspace/index.json` — 落盘产物示例
