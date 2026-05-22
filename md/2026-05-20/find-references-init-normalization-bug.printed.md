# find_references 的 __init__ 归一化与 Python 字符串不可变 bug

## 触发提问

> "关于 find_references 的使用,mock 一个情况给我"

> "review 我的实现,最终的结果跑出来一切都 ok"

> 真实跑通 demo,但隐藏 `__init__` 归一化失效的 P0 bug

## 关键结论

- **`find_references` 支持双输入**:`"app.models.user"`(module 字符串)或 `"app/models/user.py"`(file 路径)。**内部根据 `"/" in target or endswith(".py")` 判断走哪条路**。
- **`__init__.py` 必须剥点 → package 名**(`"app/auth/__init__.py"` → `"app.auth"`),对齐 Day 3 `detect_cycles` 的 `module_to_file` 归一化逻辑。
- **🔴 P0 bug:Python 字符串不可变** —— `s.removesuffix(".__init__")` **返回新字符串**,**必须 `s = s.removesuffix(...)` 赋值**。漏写赋值 = 归一化失效但代码静默。
- **"Demo 跑通了"≠"代码正确"** —— 真实项目的 `run_demo` 触发的 query 都是热点 module,**根本不走 `__init__.py` 路径**,bug 潜伏到只有专门 fixture 才能挑出来。
- **返回的 `module` 字段是归一化后的字符串**(不是用户传入的原 target)—— 这是工具的"自描述"信号,**告诉 LLM "你刚才传的等价 module 是这个"**,下次直接传 module 字符串就行。

## Schema / 字段表

### 输入归一化的 5 种触发形态

| 输入 target | 归一化后 module | 触发的代码路径 |
|---|---|---|
| `"app.models.user"` | `"app.models.user"` | else 分支(不归一化) |
| `"app/models/user.py"` | `"app.models.user"` | if 分支(去 .py + 替 /) |
| `"app/auth/__init__.py"` | `"app.auth"` | if 分支 + `__init__` 剥点 |
| `"fastapi"` | `"fastapi"` | else 分支(外部依赖) |
| `"totally.fake.module"` | `"totally.fake.module"` | else 分支 → reverse miss → `[]` |

### "空 list" 的 3 种语义(LLM 解读分支)

| 场景 | 真实含义 | LLM 应该做什么 |
|---|---|---|
| 入口文件 | `app/main.py` 本来就没人 import | "正常,不用担心" |
| 真的死代码 | 没人用 | "建议用户删" |
| 拼错 module 名 | 用户传 `app.modls.user`(打错) | "可能拼错,试试 `app.models.user`" |

**工具层不区分这三种**(都返回 `[]`),让 LLM 推理上移。

## 代码示例

### find_references 正确实现

```python
def find_references(
    graph: DependencyGraph,
    target: str,
) -> list[ReferenceHit]:
    # Q1: 输入归一化(file 路径 → module + __init__ 剥点)
    if "/" in target or target.endswith(".py"):
        module = target.removesuffix(".py").replace("/", ".")
        if module.endswith(".__init__"):
            module = module.removesuffix(".__init__")
            #        ^^^^^^^^^^ 必须赋值!Python 字符串不可变
    else:
        module = target

    # Q2: dict.get 自然 fallback
    importers = graph["reverse"].get(module, [])

    return [ReferenceHit(module=module, importer=imp) for imp in importers]
```

### 🔴 P0 Bug 代码(漏赋值)

```python
if module.endswith(".__init__"):
    module.removesuffix(".__init__")   # ❌ 返回值丢了,module 没变
```

**Bug trace**:
```
target = "app/auth/__init__.py"
module = "app/auth/__init__.py".removesuffix(".py").replace("/", ".")
       = "app.auth.__init__"

module.endswith(".__init__") → True
module.removesuffix(".__init__")     # 返回 "app.auth" 但丢了
# module 仍然是 "app.auth.__init__"

graph["reverse"].get("app.auth.__init__", [])
# day3 build 时 reverse 字典里的 key 是 "app.auth"(剥过 __init__)
# 所以 .get() 永远 miss

return []   # 永远空,即使真有人 import app.auth 也查不到
```

### 回归测试 fixture

```python
test_g: DependencyGraph = {
    "forward": {},
    "reverse": {"app.auth": ["app/main.py"]},   # 注意 key 是剥过 __init__ 的 package 名
    "cycles": [],
    "unresolved_relative": [],
}

# 同一个 package,2 种输入形态都应该 query 到同样结果
r1 = find_references(test_g, "app.auth")               # module 字符串
r2 = find_references(test_g, "app/auth/__init__.py")   # __init__ 路径

assert len(r1) == 1
assert len(r2) == 1, f"❌ __init__ 归一化失败:{r2}"   # bug 时这里挂
assert r1[0]["importer"] == r2[0]["importer"] == "app/main.py"
```

### Python 字符串不可变对比 list 可变

```python
# 字符串不可变:返回新字符串,必须赋值
>>> s = "app.auth.__init__"
>>> s.removesuffix(".__init__")     # 返回 "app.auth"
'app.auth'
>>> s                                # 原变量没动!
'app.auth.__init__'
>>> s = s.removesuffix(".__init__")  # 必须赋值
>>> s
'app.auth'

# list 可变:in-place 改原对象
>>> lst = [1, 2, 3]
>>> lst.append(4)                    # in-place
>>> lst
[1, 2, 3, 4]
```

## 坑 / Why

### Why __init__ 归一化不能省

- Day 3 `build_dependency_graph` 时 `module_to_file` 把 `app/auth/__init__.py` 映射成 `app.auth`(package 名),所以 `reverse` 字典里的 key 都是剥过 `__init__` 的。
- `find_references` 必须做同样的归一化,否则 LLM 传 `__init__.py` 路径永远查不到。
- **同一种归一化规则在不同位置(build 时 / query 时)必须保持一致** —— Day 3 build 怎么做的归一化,Day 4 query 就必须复用同一套逻辑。

### Why "Demo 跑通" 不代表代码正确

- `run_demo` 用真实 codebase(coco/apps/backend)实跑
- demo 自动挑 top-imported module 当 query(`stats["top_imported_modules"][0][0]`)
- top-imported 永远是 `app.models.user` 这种热点,**不会是 `__init__.py`**
- 所以 `__init__` 归一化分支没人走 → bug 永远不暴露
- **真正能挑出 corner case bug 的是 day3 风格的 hand-crafted fixture**(纯环 / 自环 / __init__ 环 / 外部依赖混入)
- 教训:**fixture 测试不是凑数,是 demo 跑通后的最后一道防线**

### Why ReferenceHit 没有 match_mode

- ReferenceHit 是字符串精确匹配(`graph["reverse"].get(module, [])`),**没有"猜的"概念**
- 对比 DefinitionHit:fuzzy 阶段用 normalize 后字符串重比对,**有"猜测"语义**,所以需要 match_mode
- **schema 字段不是装饰,有就有价值,没有就别加**(YAGNI)

### Why module 字段反映归一化后而非原 target

- LLM 传 `"app/models/user.py"` → 返回 `module: "app.models.user"`
- LLM 看到这个反射:"哦,我刚才传的 file 路径等价于这个 module,下次直接传 module 省一次归一化"
- **工具的"自我教学"信号** —— 帮 LLM 学正确的 API 用法

## 关联

- [[python-string-strip-vs-split]] — Python 字符串不可变 + strip/split/removesuffix 都要赋值
- [[find-definition-two-phase-design]] — 同样的归一化模式在 definition 工具
- [[day4-llm-lookup-tools-architecture]] — 4 个工具整体设计
- [[dependency-graph-schema-and-stats]] (2026-05-18) — Day 3 build 的归一化逻辑
