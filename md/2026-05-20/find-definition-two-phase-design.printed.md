# find_definition 两阶段匹配设计

## 触发提问

> "review 我的 find_definition 实现"

> "`if normalized == symbol_name: return []` 的意思是什么?"

> "kind 参数到底是个什么样的情况?"

> "为什么 fuzzy 那段用的是 normalized 不是 symbol_name?"

## 关键结论

- **两阶段匹配(Q1=C)**:Phase 1 strict 精确比对 `sym["name"] == symbol_name` → 命中标 `match_mode="exact"`;Phase 1 miss → Phase 2 normalize 后用 `normalized` 重比对 → 命中标 `match_mode="fuzzy"`。
- **`if normalized == symbol_name: return []` early return = 性能优化 + 语义守护** —— 如果 normalize 没改动输入(plain identifier),strict 已经穷尽所有可能,fuzzy 重查纯属浪费 O(N) 遍历。
- **`kind` 参数是"歧义消除器"**,**99% 调用 `kind=None`(默认撒网)**。只有当返回 list 出现"function + class 同名混杂"时,LLM 主动加 `kind="function"` 重试 —— 这是 LLM 自我纠错模式。
- **2 个高频 bug**:① fuzzy 阶段用错变量(应该是 `normalized` 不是 `symbol_name`,Demo 跑不出来才暴露)② `DefinitionHit({...})` dict 包裹形式让 Pyright 类型检查保险被关。
- **`_make_hit` helper** 用 kwargs 构造 `DefinitionHit(file=..., line=...)` —— 漏字段时 Pyright 立刻红字。

## Schema / 字段表

### 输入归一化的 4 种 LLM 传入形态

| LLM 传入 | normalize 后 | match_mode |
|---|---|---|
| `"login"` | `"login"` | exact(strict 命中) |
| `"User.login"` | `"login"` | fuzzy(strict miss,normalize 命中) |
| `"login()"` | `"login"` | fuzzy(同上) |
| `"  User . login  "` | `"login"` | fuzzy(同上) |

### kind 参数的 4 种使用形态

| 调用 | 占比 | 场景 |
|---|---|---|
| `find_definition(idx, "login")` | **90%** | 默认撒网 |
| `find_definition(idx, "login", kind="function")` | 8% | LLM 明确"我要函数",排除同名 class |
| `find_definition(idx, "User", kind="class")` | 2% | LLM 明确"我要类" |
| 别的字符串 | 0% | Pyright 拦截(Literal 限定) |

## 代码示例

### normalize_symbol(LLM 容错命门)

```python
def normalize_symbol(raw: str) -> str:
    """把 LLM 传入的"自然语言式"符号名归一到 plain identifier。

    >>> normalize_symbol("User.login")       # → 'login'
    >>> normalize_symbol("login()")          # → 'login'
    >>> normalize_symbol("  User . login  ") # → 'login'
    >>> normalize_symbol("app.models.User")  # → 'User'
    """
    s = raw.strip()
    if "(" in s:
        s = s.split("(")[0].strip()          # split,不要用 strip('()')!
    if "." in s:
        s = s.split(".")[-1].strip()
    return s
```

### find_definition 完整实现

```python
def find_definition(
    index: CodebaseIndex,
    symbol_name: str,
    kind: Literal["function", "class"] | None = None,
) -> list[DefinitionHit]:
    def _make_hit(
        file: FileIndex,
        sym: SymbolInfo,
        mode: Literal["exact", "fuzzy"],
    ) -> DefinitionHit:
        return DefinitionHit(
            file=file["path"],
            line=sym["start_line"],
            kind=sym["kind"],
            name=sym["name"],
            signature=sym["signature"],
            match_mode=mode,
        )

    # Phase 1: strict 精确匹配
    exact_hits: list[DefinitionHit] = [
        _make_hit(file, sym, "exact")
        for file in index["files"]
        for sym in file["symbols"]
        if sym["name"] == symbol_name and (kind is None or sym["kind"] == kind)
    ]
    if exact_hits:
        return exact_hits

    # Phase 2: fuzzy 回退(normalize 后比对)
    normalized = normalize_symbol(symbol_name)
    if normalized == symbol_name:
        return []   # 已经是 plain,strict miss = 真没有

    return [
        _make_hit(file, sym, "fuzzy")
        for file in index["files"]
        for sym in file["symbols"]
        if sym["name"] == normalized and (kind is None or sym["kind"] == kind)
        #                  ^^^^^^^^^^ 不是 symbol_name!
    ]
```

### Bug trace(用 `"User.login"` 触发 fuzzy)

```
输入: symbol_name = "User.login"

Phase 1 (strict):
  比对每个 sym["name"] == "User.login"
  → 全部 miss(SymbolInfo["name"] 永远不带点)
  exact_hits = []

Phase 2 (fuzzy) [正确版]:
  normalized = "login"
  normalized != symbol_name → 不 early return
  比对每个 sym["name"] == "login"   ← 用 normalized
  → 命中 app/auth/login.py:L24
  fuzzy_hits = [<DefinitionHit match_mode="fuzzy">]
```

## 坑 / Why

### Why fuzzy 用 normalized 而不是 symbol_name(P0 bug)

```python
# ❌ 错的(复制粘贴 strict 那段忘改)
if sym["name"] == symbol_name and ...

# ✅ 对的
if sym["name"] == normalized and ...
```

**症状**:`find_definition(idx, "User.login")` 永远返回 `[]`,而 `find_definition(idx, "login")` 能命中 —— **fuzzy 阶段完全失效**。Day 4 那条"故意会踩的坑"(LLM 传 User.login 而不是 login)正好触发。
**Why bug 隐蔽**:类型对得上(都是 str),Pyright/runtime 都不报错,**只有跑 fuzzy 测试 case 才暴露**。

### Why DefinitionHit 必须用 kwargs

```python
# ⚠ Pyright 不检查字段(当 type cast)
DefinitionHit({"file": ..., "line": ..., ...})

# ✅ Pyright 检查字段名/类型/必填
DefinitionHit(file=..., line=..., ..., match_mode="exact")
```

漏写 `match_mode` 字段 → kwargs 形式立刻红字,dict 包裹形式静默通过 —— **TypedDict 最大的坑**。

### Why early return 重要

LLM 一次 conversation 平均 lookup 10~20 个不存在的符号(LLM 经常猜错名字)。**plain 输入 + strict miss**:
- 不加 early return:5000 × 2 = 10000 次比对(strict + fuzzy 用同一个字符串)
- 加 early return:5000 次(strict 一次)
- **省一半 CPU**

### Why kind 参数 99% 用默认

LLM 不知道也不需要知道符号是 function 还是 class,先撒网拿到全集再判断。`kind` 是 LLM **自我纠错的精度旋钮** —— 第一次返回多条歧义时,LLM 主动加 `kind` 重试。
**`kind` 不是给人写代码用的,是给 LLM 留的可选 filter**(类比 SQL 的 `WHERE type='function'`)。

## 关联

- [[day4-llm-lookup-tools-architecture]] — 4 个工具整体设计
- [[python-string-strip-vs-split]] — normalize 里 split 不能换成 strip 的根因
- [[find-references-init-normalization-bug]] — 同样的"归一化"模式在 references 工具的应用
