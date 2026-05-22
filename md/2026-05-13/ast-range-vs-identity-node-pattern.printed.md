# AST · 范围节点 vs 身份节点 · 分离模式

> 来源:week3/day1_workspace · decorated_definition 处理的反复 review
> 落盘日期:2026-05-13

## 触发提问

- `decorated_definition` 节点的 `start_point` 是 @ 那行,但我想要 def 那行,为什么?
- 修了 Bug 1 又新引入 Bug 2 — `kind` 永远是 "class"?
- "我看你的代码是先加一,后面在索引里面又减一。为什么直接不用这个 start_point 呢?"
- node 和 inner 分别是什么?为什么 helper 要两个参数?

## 关键结论

**对于"包装外壳节点"**(`decorated_definition` 把 N 个 decorator + 1 个 function/class 包起来),提取 SymbolInfo 时**同一个节点的不同字段要从不同位置取**:

- **范围字段**(`start_line` / `end_line`)→ 取**外层 node**(`decorated_definition`)的 start/end_point — chunk 范围含 `@`
- **身份字段**(`kind` / `name` / `signature`)→ 取**内层 inner**(`function_definition`)的 type/name/source_line — 真函数信息

这种"范围 vs 身份"分离不仅适用于 decorated_definition,**也是 tree-sitter 所有"包装层节点"的通用处理模式**。

## 字段表 · node vs inner 取哪个

| 字段 | 来源 | 理由 |
|---|---|---|
| `start_line` | **node** `.start_point[0] + 1` | chunk 起点要含 `@decorator` 那行 |
| `end_line` | node 或 inner 的 end_point(一致) | decorated_definition 的 end_point 跟 inner end_point 重合 |
| `kind` | **inner** `.type == "function_definition"` ? "function" : "class" | node.type 是 `"decorated_definition"`,不能判 |
| `name` | **inner** `.child_by_field_name("name")` | decorated_definition 没有 name field,只有内部真函数有 |
| `signature` | **inner** `.start_point[0]` 对应那行 source | def 那行才是签名,@decorator 不是 |

## 示例 · `_make_symbol(node, inner)` helper

```python
from tree_sitter import Node


def _make_symbol(node: Node, inner: Node, source_lines: list[str]) -> SymbolInfo:
    """统一处理"普通 def/class"和"装饰器包装"两种 case。
    
    Args:
        node:  "范围节点" —— 普通 case 就是 def/class 本体;装饰器 case 是 decorated_definition 外壳。
                决定 start_line / end_line(chunk 范围)
        inner: "身份节点" —— 永远是真实的 function/class_definition。
                决定 kind / name / signature(真身份)
        source_lines: source.split("\n") 切好的行(避免重复 split)
    """
    return SymbolInfo(
        kind="function" if inner.type == "function_definition" else "class",
        name=inner.child_by_field_name("name").text.decode(),
        start_line=node.start_point[0] + 1,       # ← 外层(可能含 @)
        end_line=node.end_point[0] + 1,
        signature=source_lines[inner.start_point[0]].strip().rstrip(":"),  # ← 内层 def 那行
    )


# 主循环
for node in root.children:
    if node.type in ("function_definition", "class_definition"):
        symbols.append(_make_symbol(node, node, lines))      # node == inner
    elif node.type == "decorated_definition":
        inner = next(
            c for c in node.children
            if c.type in ("function_definition", "class_definition")
        )
        symbols.append(_make_symbol(node, inner, lines))     # node ≠ inner
```

**口诀**:
- `node` = **范围**节点(决定 start_line / end_line 框多大)
- `inner` = **身份**节点(决定 kind / name / signature 是什么)

## 示例 · 错误对比 case

### 反面 1 — start_line 误用 inner(选了 Q2=B 但代码写 Q2=A)

```python
@staticmethod
@deprecated
def decorated_func(x, y):
    pass

# ❌ 错:start_line 取 inner(def 那行)
start_line = inner.start_point[0] + 1   # → 10(def 那行)— Q2=A 行为

# ✅ 对:start_line 取 node(@ 那行)
start_line = node.start_point[0] + 1    # → 8(@staticmethod 那行)— Q2=B 行为
```

**根因**:`inner.start_point` 是 def 那行,**根本不知道有 decorator 存在**。要包含装饰器必须用外层节点。

### 反面 2 — kind 误用 node.type(helper 内部 bug)

```python
def _make_symbol(node, inner, lines):
    # ❌ 错:kind 用 node.type,decorated_definition case 永远走 else 分支 → "class"
    kind = "function" if node.type == "function_definition" else "class"
    
    # ✅ 对:kind 用 inner.type,无论是否带装饰器都正确
    kind = "function" if inner.type == "function_definition" else "class"
```

**根因**:helper 在 decorated case 里 `node.type == "decorated_definition"`(既不是 function_definition 也不是 class_definition),三元运算永远走 falsy 分支。

## 示例 · 数 source 行号(.strip().rstrip(":"))

```python
# 假设 source 内容(1-based):
# 1: def hello(name: str) -> str:
# 2:     """Say hello."""
# 3:     return f"Hello, {name}"

lines = source.split("\n")   # ⚠ 函数开头切一次,不要在循环里反复 split

# hello 函数:inner.start_point = (0, 0) → inner.start_point[0] = 0
signature = lines[inner.start_point[0]].strip().rstrip(":")
# → lines[0].strip().rstrip(":")
# → "def hello(name: str) -> str"  ✓
```

**性能 tip**:`source.split("\n")` 是 O(n) 操作,**函数开头切一次**复用,**不要在循环里反复 split**(变成 O(n × symbols))。

## 坑 / Why

### 同节点不同字段取不同位置 = "数据视图分离"

**Why**:同一个符号在不同消费者那里有不同呈现 ——
- `start_line` 给"chunk 切分"用(要完整代码块,含装饰器)
- `signature` 给"LLM 看 / 人看"用(要简洁,只 def 一行)

这是"数据 vs 视图"的早期体现。`index.json` 里 `start_line` / `end_line` / `signature` 全存,**消费方按需取**。

**How to apply**:写 indexer / parser 的输出 schema 时,问自己 "消费者会怎么用这个字段?";不同用途 → 不同字段(冗余但语义清晰),**不要让消费方自己算变形**。

### "包装层节点"在 tree-sitter 里很常见

**Why**:不止 `decorated_definition`,还有 `expression_statement`(包装 expression)、`assert_statement`(包装 condition)、`async_function_definition`(包装 function_definition)。**模式都是一样的**:
- 外层节点提供"位置上下文"(start_point 含前缀)
- 内层节点提供"语义本体"(真正的 def / class / expression)

**How to apply**:
- 提取 symbols 时,**永远从外层节点取范围,从内层节点取身份**
- 看到 `node.type` 不在预期 set 里,先查"是不是有个包装层"
- day3 写 async def / async class 处理时复用同一个 pattern

### 重构信号:两个分支 90% 重复 → 抽 helper

**Why**:`function_definition | class_definition` 跟 `decorated_definition` 分支几乎一样,只差 "用 node 还是 inner"。**抽 helper 减少 bug 表面积** —— bug 1(`kind="function"` 写死)同时出现在两个分支,如果是 helper,bug 只出一次,修一次解决两处。

**How to apply**:
- 看到 if-elif 两个分支结构高度相似,**强烈推荐抽 helper 而不是复制粘贴**
- helper 的每个参数,**在脑中过一遍"每个调用点传进来时,这个值到底是什么"**(本次 review 撞 `node.type` bug 就是没过这一步)
- production-grade 升级方向是引入 `SymbolSpan` dataclass 把 `range_node` 和 `body_node` 显式打包

### `_make_symbol(node, inner)` 是个"两个语义相关参数"的 API 异味

**Why**:两个参数语义相关但又不同步 ——
- 普通 case:`node == inner`(传入相同对象)
- 装饰器 case:`node ≠ inner`(传入两个不同节点)

调用方需要记住这个区别,**容易传错**。day2 这个量级合理,但 day3+ 应该升级。

**How to apply**:
- 升级方向 1 — `SymbolSpan` dataclass:`@dataclass class SymbolSpan: range_node: Node; body_node: Node`
- 升级方向 2 — 调用方传 wrapper:`_make_symbol(SymbolSpan(node, inner), lines)`
- helper 只收一个参数,内部访问 `.range_node` 和 `.body_node`,语义更清晰

## 关联

- [[tree-sitter-python-node-schema]] — Node 对象 API 基础
- [[codebase-indexer-design-patterns]] — day2 indexer 工程设计
- [[string-escape-and-rerun-discipline]] — day1 修了 bug 又引入 bug 的纪律问题
- `week3/day1_workspace/day1_indexer.py` — extract_symbols + `_make_symbol` 实战代码
