# 相对 import 解析 · 前导点数 4 种等价写法对比

> 来源:week3/day3_workspace · resolve_relative_import + 数前导点的讨论
> 落盘日期:2026-05-18

## 触发提问

- `from . import foo` / `from ..models import X` 的 `.` `..models` 怎么解析成绝对模块路径?
- `dots = 0; for c in s: if c == ".": dots += 1; else: break` 和 `dots = sum(1 for c in s if c == ".")` 这两种等价吗?

## 关键结论

- 相对 import 解析逻辑 = **数前导点 + 切 file path + 拼 suffix + `__init__.py` 特殊处理**
- 前导点数 4 种写法:`for+break` / `sum(...)` / `itertools.takewhile` / `lstrip 长度差`
- **`sum(1 for c in s if c == ".")` 对 `"..models.user"` 不等价**(前导 2 vs 全量 3)
- **推荐 `len(s) - len(s.lstrip("."))`** —— Pythonic、C 实现、最短
- 跳出 root 的相对 import 应 fallback 到 `unresolved_relative` 字段

## 算法步骤

```text
1. 数 relative_module 前导点数 N
2. current_file 拆模块路径段(去 .py + 替 / → .)
3. __init__.py 特殊处理:它本身就是 package 的 module,不算嵌套
4. 向上 N 级:base = parts[:-N]
   - 如果 N > len(parts) → 跳出 root,return None
5. 拼接 suffix(点后面的部分):base + suffix → "app.models"
```

## 代码示例 · resolve_relative_import 完整版

```python
def resolve_relative_import(
    current_file: str,
    relative_module: str,
) -> str | None:
    """把 `from ..models import X` 的 "..models" 解析成绝对模块路径。

    Examples:
        >>> resolve_relative_import("app/auth/login.py", ".")
        'app.auth'
        >>> resolve_relative_import("app/auth/login.py", "..models")
        'app.models'
        >>> resolve_relative_import("app/auth/login.py", "...too_deep")
        # → None (跳出 root)
    """
    if not relative_module.startswith("."):
        return relative_module  # 不是相对 import,原样返回

    # ✨ 一行数前导点(最 Pythonic)
    dots = len(relative_module) - len(relative_module.lstrip("."))
    suffix = relative_module[dots:]

    # 拆 file path 成模块段
    parts = current_file.removesuffix(".py").split("/")
    if parts[-1] == "__init__":
        parts = parts[:-1]   # __init__.py 是 package 本身,不算嵌套

    if dots > len(parts):
        return None          # 跳出了 root

    base = parts[:-dots] if dots > 0 else parts

    if suffix:
        return ".".join([*base, suffix]) if base else suffix
    return ".".join(base) if base else None
```

## 字段表 · 4 种"数前导点"写法对比

| 写法 | 代码 | 评价 |
|---|---|---|
| **for + break** | `dots = 0; for c in s: if c == ".": dots += 1; else: break` | 显式,初学者最易读 |
| **sum 全数** | `dots = sum(1 for c in s if c == ".")` | ❌ **对 `..models.user` 不等价** |
| **takewhile** | `sum(1 for _ in takewhile(lambda c: c == ".", s))` | 学院派,需要 import |
| **lstrip 长度差** | `dots = len(s) - len(s.lstrip("."))` | ✅ **推荐**,一行 + C 实现 + 无需 import |

## 字段表 · 完整 case 等价测试

| relative_module | 前导点(写法 1/3/4) | 全部点(写法 2) | 等价? |
|---|---|---|---|
| `"."` | 1 | 1 | ✅ |
| `".."` | 2 | 2 | ✅ |
| `"..."` | 3 | 3 | ✅ |
| `"..models"` | 2 | 2 | ✅(suffix 无点) |
| `".foo"` | 1 | 1 | ✅ |
| **`"..models.user"`** | **2** | **3** | ❌ |
| **`"...services.email"`** | **3** | **4** | ❌ |
| **`"..a.b.c.d"`** | **2** | **5** | ❌ |

**结论**:**只要 suffix(点后面的模块路径)里也有点,sum 写法就不等价**。

## 示例 · 解析 trace

```python
current_file = "app/auth/login.py"
relative_module = "..models.user"

# Step 1:数前导点
dots = len("..models.user") - len("..models.user".lstrip("."))
# = 13 - 11 = 2

# Step 2:切 suffix
suffix = "..models.user"[2:]   # → "models.user"

# Step 3:拆 file path
parts = "app/auth/login.py".removesuffix(".py").split("/")
# = ["app", "auth", "login"]

# Step 4:__init__ 检查(此处不是)

# Step 5:向上 2 级
base = parts[:-2]   # → ["app"]

# Step 6:拼接
return ".".join(["app", "models.user"])
# → "app.models.user"  ✅
```

## 坑 / Why

### `sum` 写法的 bug 本质 = "前缀取" vs "全量计"

**Why**:看起来 `sum(1 for c in s if c == ".")` 简洁,但**语义跟"数前导点"完全不同**。新人常把"代码短"等同于"代码对"。

**How to apply**:
- 简洁性必须服从于语义,**先确认语义再追简洁**
- code review 时看到 `sum(...)` 数字符,**第一反应应该是问"这是数全量还是数前缀"**
- 90% 时候你会发现作者想数前缀但写错了

### `str.lstrip(c) + len 差` 是个被低估的 Python 习语

**Why**:
- 比 takewhile 更短(无 import)
- 比 for-break 更声明式
- **完全是 C 实现**(`lstrip` 走 C 字符串处理,比 Python 层循环快 5-10 倍)

**How to apply**:Python "短 + 快 + 清"的标准习语库,这是其中一条。week4 chunk 大量字符串处理时,`lstrip + len` vs `for-loop` 的速度差能直接反映到批量入库总时间。

### `__init__.py` 特殊处理:它本身就是 package

**Why**:`app/auth/__init__.py` 在 Python import 系统里**就是 `app.auth` 这个 package**,不是 `app.auth.__init__` 这个嵌套子模块。**所以拆 parts 后要去掉 `__init__` 段**,否则相对 import 算路径会多向上一级。

**How to apply**:`if parts[-1] == "__init__": parts = parts[:-1]` —— 这一行不写会导致 `app/__init__.py` 里的 `from . import x` 解析出错(本来应该是 `app.x`,会变成 ""(空)+ x = `x`,丢了 app 前缀)。

### "暴露 bug 的最小 fixture" 是 test 设计核心

**Why**:**两个实现在简单 case 下输出一致,只能证明"在那个 case 上等价"**,不能证明"在所有 case 上等价"。`"."` `".."` `"..models"` 在两种写法下都给 2,看不出差异;只有 `"..models.user"` 这种**双侧有点**的 case 才暴露 sum 写法的 bug。

**How to apply**:
- production-grade test suite 必须包含"对称性破坏 fixture"
- 设计 fixture 时问自己:"哪个 case 能让错误实现失败?"(不是"哪个 case 看起来合理")
- week7 evaluation harness 设计 test set 时,这是核心技能

## 关联

- [[dependency-graph-schema-and-stats]] — resolve_relative_import 在 build_dependency_graph 里的应用
- `week3/day3_workspace/day3_dependency_graph.py:resolve_relative_import` — 实战代码
- `~/knowledges/md/2026-05-13/tree-sitter-python-node-schema.md` — `relative_import` AST 节点结构
