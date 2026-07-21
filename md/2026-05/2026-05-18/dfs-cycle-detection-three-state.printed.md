# DFS · 三态(WHITE/GRAY/BLACK)环检测算法

> 来源:week3/day3_workspace · detect_cycles 算法练习
> 落盘日期:2026-05-18

## 触发提问

- "DFS 算法简简单单地介绍一下,然后就用一个最小的 Demo"
- `cycle = path[:] + [next_file]` vs `cycle = path[path.index(next_file):] + [next_file]` 两种方案有什么区别?
- DFS 的"调用栈"长什么样?
- 普通 visited 集合为什么检测不到环,要升级三态?

## 关键结论

- DFS = 深度优先搜索,**沿一条路径走到底,走不通就回溯换条路**
- DFS 的本质是**用递归(或显式栈)模拟"压栈/弹栈"**,**调用栈 = 当前 DFS 路径**
- **三态(WHITE/GRAY/BLACK)是检测环的核心**:GRAY = 当前路径上、BLACK = 已完成
- **两态 visited 集合无法检测环**:因为分不清"在路径上" vs "已退出"
- 切环路径必须用 `path[path.index(next):]`,**`path[:]` 会把 DFS 入口前缀也算进环里**(尾环 case)

## DFS vs BFS · 一秒区分

```text
图:    A → B → C
       ↓
       D → E

DFS 访问顺序:A → B → C → (回溯) → D → E    "一条路走到黑"
BFS 访问顺序:A → B → D → C → E              "按层扫"
```

| 算法 | 数据结构 | 适合 |
|---|---|---|
| **DFS** | 栈 / 递归 | 环检测、拓扑排序、SCC(强连通分量) |
| BFS | 队列 | 最短路径、层次遍历 |

## 字段表 · 三态机解读

| 状态 | 含义 | 何时进入 |
|---|---|---|
| **WHITE** | 未访问过 | 初始 |
| **GRAY** | **正在当前 DFS 路径上**(还在递归中) | `dfs(node)` 函数开头 |
| **BLACK** | 已完成访问 + 子树确认无环 | `dfs(node)` 函数结尾 |

**检测环的逻辑**:遍历邻居时,**发现一个 GRAY 邻居 = 当前路径绕回来了 = 环!**

## 示例 · 4 节点无环图 DFS

```python
graph = {
    "A": ["B", "D"],
    "B": ["C"],
    "C": [],
    "D": ["E"],
    "E": [],
}

visited = set()

def dfs(node):
    if node in visited:
        return
    visited.add(node)
    print(f"访问 {node}")
    for neighbor in graph[node]:
        dfs(neighbor)

dfs("A")
# 输出:A → B → C → D → E
```

**调用栈动态**(时刻 = 函数嵌套层级):

```text
时刻 1:dfs(A)            栈: [A]
时刻 2:dfs(B)            栈: [A, B]
时刻 3:dfs(C)            栈: [A, B, C]
时刻 4:C 无邻居,return    栈: [A, B]
时刻 5:B 无邻居,return    栈: [A]
时刻 6:dfs(D)            栈: [A, D]
时刻 7:dfs(E)            栈: [A, D, E]
时刻 8-10:依次 return    栈空
```

**关键观察**:**调用栈 = 当前 DFS 路径** —— 这是检测循环的物理基础。

## 示例 · 3 节点带环图 + 三态检测

```python
# A → B → C → A
graph = {
    "A": ["B"],
    "B": ["C"],
    "C": ["A"],
}

WHITE, GRAY, BLACK = 0, 1, 2

state = {node: WHITE for node in graph}
path = []
cycles = []


def dfs(node):
    state[node] = GRAY          # 入函数 = 标 GRAY,入路径
    path.append(node)

    for neighbor in graph[node]:
        if state[neighbor] == GRAY:
            # ⚠ 找到环!回溯路径 = 从 neighbor 起点开始
            cycle = path[path.index(neighbor):] + [neighbor]
            cycles.append(cycle)
            return True
        elif state[neighbor] == WHITE:
            if dfs(neighbor):
                return True
        # BLACK 邻居:子树已确认无环,跳过

    state[node] = BLACK         # 出函数 = 标 BLACK,出路径
    path.pop()
    return False


for node in graph:
    if state[node] == WHITE:
        if dfs(node):
            break

print(cycles)   # → [['A', 'B', 'C', 'A']]
```

**核心瞬间**:在 `dfs(C)` 里看到邻居 A,而 `state[A] == GRAY`(还没退栈) → **路径绕回起点** = 环!

## 字段表 · `path[:]` vs `path[path.index(target):]` 在两种环形态的差异

环有两种形态,**只在"尾环"case 暴露差异**:

```text
情况 A · "纯环"(起点 = 环的一部分)
   A → B → C → A
   ↑___________|
   path = [A, B, C],next_file = A
   → 整个 path 都在环里

情况 B · "尾环 / 套索"(起点不在环里,只是入口)
   D → A → B → C → A
                ↑___|
   path = [D, A, B, C],next_file = A
   → D 不在环里!真正的环是 [A, B, C, A]
```

| 方案 | 情况 A(纯环) | 情况 B(尾环) |
|---|---|---|
| `path[:] + [next]` | `[A,B,C,A]` ✅ | `[D,A,B,C,A]` ❌ 多了 D |
| `path[path.index(next):] + [next]` | `[A,B,C,A]` ✅ | `[A,B,C,A]` ✅ |

**`path.index(next_file)` 的语义**:在 DFS 栈里找到环起点的位置,**前面的入口前缀(D 这种)就被切掉了**。

## 示例 · 为什么 visited(两态)检测不到环

```python
# ❌ 错误尝试:只用 visited set
visited = set()
def bad_dfs(node):
    if node in visited:
        return                  # ⚠ 只看到"访问过",没法区分"路径上 vs 已完成"
    visited.add(node)
    for neighbor in graph[node]:
        bad_dfs(neighbor)
```

跑 A → B → C → A:
- dfs(A):visited={A}
- dfs(B):visited={A,B}
- dfs(C):visited={A,B,C}
- C 的邻居 A 在 visited 里 → **直接 return**,**根本不知道这是个环**

**三态的妙处**:GRAY 专门标记"当前路径上";看到 GRAY 邻居 = 回环;看到 BLACK 邻居 = "虽然访问过,但已经退出路径",**这条边不构成回环**。

## 坑 / Why

### 三态 WHITE/GRAY/BLACK 是 CLRS 算法书的经典约定

**Why**:Cormen 那本黑皮书定义的"出栈即变色"设计,**同时支持环检测 + 拓扑排序 + 强连通分量(SCC) 三种算法**。学一次用一辈子。

**How to apply**:
- day3 detect_cycles 用了第一招
- week6 Multi-Agent 拆任务图后,用**拓扑排序**决定执行顺序 + 检测环防死锁 —— 同款代码,只是判定条件不同
- week7 evaluation 算"模块强连通分量"找深耦合区,**SCC 算法基于同一套三态**

### "纯环 vs 尾环"是新人最容易忽略的边界

**Why**:**测试 fixture 都从环起点开始 DFS 时,两种 cycle 切片方案输出一样**(主题 2 mock 数据正好是纯环),所以代码"看起来正确";只有加入"D 进入 A → A→B→C→A"这种**尾环 fixture**,bug 才暴露。

**How to apply**:**production-grade test suite 必须包含尾环 fixture**(`d.py → a.py → b.py → c.py → a.py`),专门暴露这种"看起来等价但 corner case 不等价"的实现。Week 7 evaluation harness 设计 test set 时,核心技能就是"找出能让错误实现失败的最小 case"。

### `path.index(x)` 在大图是 O(n) 隐藏 bottleneck

**Why**:小图无感,大图(>1000 节点)累积 O(V × E) 拖慢 DFS。算法面试常考"DFS 检测环的复杂度",标准答案是 O(V + E) —— 那个 "+V" 来自每个节点最多入栈一次。**如果 `path.index` 没优化**,实际是 O(V × E)。

**How to apply**:同时维护 `path: list` + `path_position: dict[node, int]`,`path.index(target)` 改成 `path_position[target]`,O(n) → O(1)。day3 量级无需优化,**面试时这是个加分点**。

### 递归 DFS 在 Python 默认深度 1000 会爆栈

**Why**:Python 默认 recursion limit 是 1000。索引深度 > 1000 的模块依赖链(monorepo 偶发)会 RecursionError。

**How to apply**:
- 小项目(< 100 节点):递归 DFS 简洁,直接用
- 大项目:`sys.setrecursionlimit(10000)`,或改 iterative DFS(手动维护栈,代码膨胀到 50+ 行)
- production-grade 工具(import-linter / pylint)用 iterative DFS

## 关联

- [[dependency-graph-schema-and-stats]] — day3 detect_cycles 在 DependencyGraph 上的落地
- [[codebase-indexer-real-world-interpretation]] — 真实项目 0 cycle 的工程含义
- `week3/day3_workspace/day3_dependency_graph.py:detect_cycles` — 实战代码
