# CodebaseIndex vs DependencyGraph 的两层分层

## 触发提问

> "我现在 Codebase index 和 graph,为什么我要去单独通过 Codebase index 去创建 graph 呢?"

> "为什么 cycle 的逻辑不放在 graph 里面,而要单独在外面计算完了 cycle 之后再添加到 graph?"

## 关键结论

- **分层 1:facts vs derived view** —— `CodebaseIndex` 是**事实层**(从 AST 直接提取的不可推导信息),`DependencyGraph` 是**派生层**(用 facts 算出来的、可丢可重建的关系)。**关键洞察:graph 完全可以从 index 重建,反过来不行 → 决定存哪个、扔哪个**。
- **分层 2:build vs analyze** —— 同一个数据结构内部也要分操作。`build_dependency_graph` 是构造类(O(N) 线性,必跑),`detect_cycles` 是分析类(O(V+E) DFS,按需跑)。**算法成本量级不同,合并 = 让所有 build 调用付环检测的钱**。
- **cycles 字段 schema 预留 + 计算延迟 = "半懒加载"模式** —— schema 承诺会有这个字段(`cycles: list[list[str]]` 初始 `[]`),**怎么算、什么时候算交给 caller 决定**:`graph["cycles"] = detect_cycles(graph)`。
- **类比模式**(facts + view):SQL 表 + 索引 / 编译器 AST + symbol table / Git object store + refs / 文件系统 inode + 路径树 —— **每一个例子都是"原始数据存一次,派生视图按需 build"**。
- **判断"分析结果该不该塞回 schema"**:**全图属性 → 塞回**(cycles 是图的拓扑特征);**特定 query 的答案 → 函数返回值**(find_references 结果、dependency_stats 报告)。

## Schema / 字段表

### 两种分层视角

```
分层 1:数据层级(facts vs derived view)
────────────────────────────────────
┌──────────────────┐  build   ┌──────────────────┐
│ CodebaseIndex    │ ───────► │ DependencyGraph  │
│  (parser 产出)   │  reduce  │  (reducer 产出)  │
└──────────────────┘          └──────────────────┘
  files[]:                      forward: ⚙ 重组
    - path                      reverse: ⚙ 反转
    - symbols                   cycles:  ⚙ DFS
    - imports                   unresolved: ⚙ 过滤


分层 2:操作类型(builder vs analyzer)
────────────────────────────────────
DependencyGraph 内部:
  构造类(builder):       分析类(analyzer):
    build_dependency_graph    detect_cycles
    O(N) 线性,纯组装         dependency_stats
                              find_references    ← day4
                              find_imports       ← day4
                              O(V+E) / O(N log N),按需跑
```

### 应该塞回 schema vs 应该独立返回的判断

| 分析产物 | 塞回 graph? | 理由 |
|---|---|---|
| `cycles` | ✅ 塞 | 全图属性,语义"图的拓扑特征" |
| `dependency_stats` | ❌ 独立 dict | 是报告/视图,不是图本身的属性 |
| `find_references` 结果 | ❌ 函数返回值 | 是 query 答案,随输入变化 |
| `forward / reverse` | ✅ 必塞 | 图的本体,不是分析结果 |

**判断标准**:全图、与查询无关 → schema 字段;局部、按需、随输入变 → 函数返回值。

## 代码示例

### Day 3 的"分层调用"

```python
# 三步分离:build / analyze / 塞回
graph = build_dependency_graph(index)     # O(N) — 构造
graph["cycles"] = detect_cycles(graph)    # O(V+E) — 分析 + 塞回

# Day 4 工具按需消费:
refs = find_references(graph, "app.models.user")   # 只用 reverse
imps = find_imports(graph, "app/main.py")           # 只用 forward
# ↑ 都用不上 cycles
```

### 反例:合并方案的 5 个症状

```python
# ❌ 反例:build 内部直接跑 cycles
def build_dependency_graph_BAD(index: CodebaseIndex) -> DependencyGraph:
    graph = {...}
    for file in index["files"]:
        # ... build forward + reverse ...
        pass
    graph["cycles"] = _internal_dfs(graph)   # ⚠ 强制每次都跑 DFS
    return graph
```

| 症状 | 后果 |
|---|---|
| 每次 build 都付 DFS 成本 | find_references 用不上 cycles 也得等 |
| DFS 算法改了 → build 函数改 | 触发所有 build 用户重测 |
| 想测 detect_cycles 没法只测它 | 必须 mock 整个 CodebaseIndex |
| build 失败 = 全死 | 无 graceful degradation |
| build 函数体爆炸 | 100 行变 300 行,单个函数 5 个职责 |

### 5 个 fixture 直接测 detect_cycles(不走 build)

```python
# 不必构造对应的 CodebaseIndex,直接构造 DependencyGraph fixture
no_cycle_graph: DependencyGraph = {
    "forward": {"app/a.py": ["app.b"], "app/b.py": ["app.c"], "app/c.py": []},
    "reverse": {}, "cycles": [], "unresolved_relative": [],
}
result = detect_cycles(no_cycle_graph)
assert result == []
```

**为什么这样能?** `detect_cycles` 只读 `graph["forward"]`,**不关心 forward 是谁 build 出来的** —— 可以是 build 出来的,也可以是手写极端 case。
**合并方案下**:要测 cycle detection,必须先构造能让 build 产出环的 CodebaseIndex,测试代码暴涨 3 倍。

## 坑 / Why

### Why 分开有 5 大收益

1. **关注点分离**:parser 是 Map(每个 file 独立),reducer 是 Reduce(全局汇总)。合并 → parser 不再是纯函数,并行化死路。
2. **不同消费场景拿子集**:day4 4 个工具只有 2 个用 graph,合并方案让所有 consumer 都背负载。
3. **派生数据的成本可选**:Coder agent 80% 调用只查定义,不用 graph,**省 70% 启动时间**。
4. **增量更新**:改一个 file → index 增量更新(O(1) parse),graph 全量 rebuild。两种节奏并存。
5. **schema 演化独立**:future 加 docstring / embeddings 字段时不相互污染。

### Why cycles 字段 schema 里预留但计算延迟

```python
class DependencyGraph(TypedDict):
    forward: dict[str, list[str]]              # build 时填
    reverse: dict[str, list[str]]              # build 时填
    cycles: list[list[str]]                    # ← 预留,初始 []
    unresolved_relative: list[tuple[str, str]] # build 时填
```

**Python 版"半懒加载"** —— schema 固定形态,填充时机由 caller 控制。
比真正的 lazy property 简单,效果一样:
- 现在跑 DFS?`graph["cycles"] = detect_cycles(graph)`
- 不需要?保持 `[]` 跳过
- 用别的算法?`graph["cycles"] = detect_all_sccs(graph)` 无缝替换

### Why 单向派生关系决定 facts/view 哪个是源

- **CodebaseIndex 是不可替代的**(从 AST 直接提取,丢了无法重建)
- **DependencyGraph 是可重建的**(完全可以从 CodebaseIndex 重新算)
- **存 facts(index.json),需要时再算 view(graph)** —— 这是数据库 / 编译器 / 文件系统的统一设计哲学

### 5 个行业类比(记忆锚点)

| 行业 | facts | derived view |
|---|---|---|
| SQL | 数据表 | 索引 / 视图 |
| 编译器 | AST | symbol table / call graph |
| 文件系统 | inode | 路径树 / 文件名缓存 |
| Git | object store(blob/tree/commit) | refs / index / packfile |
| **你的项目** | **CodebaseIndex** | **DependencyGraph** |

## 关联

- [[day4-llm-lookup-tools-architecture]] — Day 4 工具消费层
- [[dependency-graph-schema-and-stats]] (2026-05-18) — DependencyGraph 的 schema 细节
- [[dfs-cycle-detection-three-state]] (2026-05-18) — cycles 的算法实现
