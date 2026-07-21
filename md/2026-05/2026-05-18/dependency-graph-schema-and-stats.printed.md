# DependencyGraph · Schema 设计 + 反向索引 + top N 统计

> 来源:week3/day3_workspace · build_dependency_graph + dependency_stats
> 落盘日期:2026-05-18

## 触发提问

- 把单文件 extract_imports 扩成"项目依赖图"怎么设计 schema?
- build_dependency_graph 的伪码怎么实现?
- 为什么把 reverse 放在 per-file local set 里失败?(用户 bug review)
- `top_imported = sorted(...)[:top_n]` 这是记录什么的?
- `Counter.most_common(top_n)` 跟 sorted+slice 比有什么区别?

## 关键结论

- DependencyGraph 4 字段:`forward` / `reverse` / `cycles` / `unresolved_relative`
- **`forward` 跟 `reverse` 是同一份事实的两个视图**(denormalize for read)
- **`reverse` 是 cross-file 全局索引**,不能 per-file local 累积(常见 bug)
- build 时 dedupe + sorted = diff 友好、消费方查询无重复
- `Counter.most_common(N)` 内部就是 `heapq.nlargest`,**比全 sort 高效**,语义优先选择

## Schema · DependencyGraph

```python
from typing import TypedDict


class DependencyGraph(TypedDict):
    """从 CodebaseIndex.files 反向 build 出来的依赖图。"""

    forward: dict[str, list[str]]
    # file_path → list[imported_module]
    # 例:"app/main.py" → ["fastapi", "app.models.user", ...]
    # 问题视角:这个文件依赖哪些?

    reverse: dict[str, list[str]]
    # module_name → list[file_path]
    # 例:"app.models.user" → ["app/main.py", "app/auth.py", ...]
    # 问题视角:谁依赖这个模块?(find_references 的基础)

    cycles: list[list[str]]
    # 每个内层 list 是一条循环依赖路径
    # 例:[["app/a.py", "app/b.py", "app/a.py"]]
    # 空 list 表示无循环

    unresolved_relative: list[tuple[str, str]]
    # 解析失败的相对 import (跳出 root 等)
    # 每条 (file_path, original_module)
```

## 字段表 · forward vs reverse 操作时机对照

| 操作 | forward | reverse |
|---|---|---|
| **何时初始化字典 key** | per-file 一次性赋值 | 不预初始化,`setdefault(module, [])` 按需 |
| **何时累积值** | per-file 一次性赋值(local set 已收集完毕) | **跨 file 累积 append** |
| **value 是什么** | 这个 file 依赖的 module list | 这个 module 被哪些 file 依赖 |

**记忆口诀**:
- **forward = "一对多"**(一个 file → 它的多个依赖)→ **整体赋值**
- **reverse = "多对多累积"**(多个 file → 一个 module)→ **多次 append**

## 代码示例 · build_dependency_graph 正确版

```python
def build_dependency_graph(index: CodebaseIndex) -> DependencyGraph:
    graph = DependencyGraph(
        forward={},
        reverse={},
        cycles=[],
        unresolved_relative=[],
    )

    for file in index["files"]:
        file_path = file["path"]
        modules_set: set[str] = set()   # 只装"这一文件依赖的 module",去重用

        for imp in file["imports"]:
            module = imp["module"]
            if module.startswith("."):
                resolved = resolve_relative_import(file_path, module)
                if resolved is None:
                    graph["unresolved_relative"].append((file_path, module))
                    continue
                module = resolved
            modules_set.add(module)

        # forward:per-file 一次赋值,sorted 让 diff 友好
        graph["forward"][file_path] = sorted(modules_set)

        # reverse:遍历这个 file 的每个 module,append 进全局索引
        for module in modules_set:
            graph["reverse"].setdefault(module, []).append(file_path)

    return graph
```

## 代码示例 · dependency_stats(Counter.most_common 版)

```python
from collections import Counter


def dependency_stats(graph: DependencyGraph, top_n: int = 10) -> dict:
    """从 DependencyGraph 算 top N 统计数字。"""
    # 最热门被依赖的模块
    top_imported = Counter(
        {mod: len(files) for mod, files in graph["reverse"].items()}
    ).most_common(top_n)

    # 依赖最多模块的文件(注意变量名:forward 的 key 是 file,value 是 modules)
    top_importing = Counter(
        {file: len(modules) for file, modules in graph["forward"].items()}
    ).most_common(top_n)

    return {
        "total_files": len(graph["forward"]),
        "total_unique_modules": len(graph["reverse"]),
        "cycles_found": len(graph["cycles"]),
        "unresolved_relative": len(graph["unresolved_relative"]),
        "top_imported_modules": top_imported,
        "top_importing_files": top_importing,
    }
```

## 字段表 · 5 节点带环 mock 数据

```python
mock_graph: DependencyGraph = {
    "forward": {
        "main.py":            ["fastapi", "backend.api.routes", "backend.db"],
        "api/routes.py":      ["fastapi", "backend.models.user", "backend.auth.login"],
        "models/user.py":     ["sqlalchemy", "backend.db", "backend.auth.login"],  # ⚠
        "auth/login.py":      ["backend.models.user", "backend.db"],                # ⚠
        "db.py":              ["sqlalchemy.orm"],
    },
    "reverse": {
        "fastapi":             ["main.py", "api/routes.py"],
        "sqlalchemy":          ["models/user.py"],
        "sqlalchemy.orm":      ["db.py"],
        "backend.api.routes":  ["main.py"],
        "backend.db":          ["main.py", "models/user.py", "auth/login.py"],   # ← 热点
        "backend.models.user": ["api/routes.py", "auth/login.py"],
        "backend.auth.login":  ["api/routes.py", "models/user.py"],              # ← 环!
    },
    "cycles": [
        ["models/user.py", "auth/login.py", "models/user.py"],   # user ⇄ login
    ],
    "unresolved_relative": [],
}
```

## 坑 / Why

### `reverse` 必须 cross-file 累积,不能 per-file local

**Why**:常见 bug 是引入 `reversed_files: set[str] = set()` 局部变量"对偶 modules",**但 reverse 的语义本身就是 cross-file 聚合**(同一个 module 被多个文件依赖)。put 在 per-file 局部 set 里会:
1. `graph["reverse"][module] = sorted(reversed_files)` 只记每个 file 的"最后一个 module" → reverse 数据丢失 90%+
2. 同一 module 被多个文件 import 的事实,因为 reversed_files 每个 file 都重置 = 完全丢失

**How to apply**:
- forward 是 per-file 一次赋值,reverse 是 cross-file 多次 append,**两者操作时机完全不同**
- 看到代码里 reverse 用了 `graph["reverse"][k] = sorted(local_set)`(整体赋值)就是错的;**应该是 `graph["reverse"].setdefault(k, []).append(v)`**(增量追加)
- 这个 bug 在 unit test 一个小 fixture 时极容易漏掉,**至少需要"2 个文件 import 同一个 module"的 fixture** 才能暴露

### 消费者驱动设计:`module` 字段填全 vs 留空

**Why**:`import os`(非 from-import)语法上没有 from 模块,留空看起来"语法精确"。但**消费方查"谁 import 了 os"时**:
- 留空 → 必须 `if is_from: ... else look in names` 双分支
- 填全 → `module=="os"` 一个条件搞定

**How to apply**:写 schema 时不要光想"我现在产出什么自然",要想"消费方查询时什么字段最顺手"。**让消费方少 1 行 if-else,生产方多 1 行赋值** —— API 设计的总成本最低化。

### `sorted(modules_set)` 替代 `list(modules_set)` = diff 友好

**Why**:set 转 list 顺序不稳定。两次跑同样的 input,output JSON 可能字段顺序不同 → **git diff 一堆假变更**。

**How to apply**:任何集合类型在落盘前 sort。day2 `walk_python_files` 已经 `sorted(files)`,day3 同步加 sort 风格统一。如果 `index.json` / `dependency_graph.json` 要 commit 进 git(强烈建议,项目快照),sort 是省心 + 省 review 时间的工程习惯。

### dedupe 必须 build 时做,不要推给消费者

**Why**:同一文件多次 import 同一模块(`import os` + `from os import path`)→ extract_imports 产出 2 条 ImportInfo → 直接塞 reverse 会让 `reverse["os"]` 同一 file 出现 2 次 → Week 4 RAG 召回有重复 chunk + detect_cycles 重复探查同一条边。

**How to apply**:`modules_set: set[str] = set()` per-file 局部去重,加进 reverse 时已经唯一。**dedupe 推到数据产出最早的位置,下游消费方代码更简单**(Elasticsearch / Lucene 的反向索引也都默认 doc_id 去重)。

### Counter.most_common vs sorted+slice 性能对比

**Why**:`Counter.most_common(N)` 内部用 `heapq.nlargest`(在 `cpython/Lib/collections/__init__.py:most_common`),N 远小于总数时**比全排序快 O(log n) 倍**。

| 写法 | 何时合适 | 复杂度 |
|---|---|---|
| `sorted(...)[:N]` | 数据小,代码自解释 | O(n log n) |
| `Counter().most_common(N)` | 语义是"计数"时最自然 | O(n + N log n) |
| `heapq.nlargest(N, ...)` | 语义是"取前 N"时最精确 | O(n + N log n) |

**How to apply**:
- day3 量级(几百 modules)三种都 OK
- week4 RAG 灌库后处理几万 chunks,选 heap 系列(`Counter.most_common` 或 `heapq.nlargest`)
- 算法面试 "top K problem" 答案就是 heap,**不是 sort 全部再切片**

### `key=lambda x: -x[1]` vs `reverse=True`

**Why**:`-x[1]` 来自数学惯例(乘 -1 等于降序),**但如果 x[1] 是字符串会 TypeError**。`reverse=True` 是 Python 声明式风格,**更不容易踩 type 坑**。

**How to apply**:production 代码统一用 `reverse=True`;看到 `-x[i]` 就疑心(算法竞赛风格,工程上不优雅)。

## 关联

- [[dfs-cycle-detection-three-state]] — cycles 字段的算法实现
- [[relative-import-resolution]] — `module` 字段相对 import 转绝对的工具
- [[codebase-indexer-real-world-interpretation]] — top_imported / top_importing 怎么解读
- `week3/day3_workspace/day3_dependency_graph.py:build_dependency_graph` — 实战代码
- `~/knowledges/md/2026-05-13/codebase-indexer-design-patterns.md` — day2 indexer schema 基础
