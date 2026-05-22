# argparse 在 Jupyter 报错 + 3 种调试姿势

## 触发提问

> 报错:`usage: ipykernel_launcher.py [-h] --root ROOT; ipykernel_launcher.py: error: the following arguments are required: --root`

> 跟着的 IPython 警告:`UserWarning: To exit: use 'exit', 'quit', or Ctrl-D.`

> "在 Jupyter 里调试这一块的代码"

## 关键结论

- **报错根因**:argparse 默认从 `sys.argv` 读参数,**Jupyter 启动时 `sys.argv` 是 `['ipykernel_launcher.py', '-f', 'kernel.json']`** —— argparse 没看到 `--root` 就 `sys.exit(2)` 报错退出。
- **`To exit` 警告的根因**:IPython 拦截了 `sys.exit(2)`,以为用户想退出 shell,**给的友好提示**(实际不是用户操作,是 argparse 触发的)。
- **正确做法 = 让底层函数(`run_demo`)既能被 main() 调,也能被 Jupyter 单独调** —— **CLI 入口和 Jupyter 调试是两种使用模式**,不要强行用同一个入口。
- **3 种解决姿势**:① 直接调 `run_demo(Path(...))` 跳过 argparse(教学场景最简单)② Jupyter 分步 cell 调试(发挥 Jupyter 优势:index 一次 build,query 反复试)③ 让 `main(argv)` 接受参数(工程化解法)。
- **`%load_ext autoreload` + `%autoreload 2`** —— Jupyter 改代码后**不重启 kernel** 也能自动 reimport,**索引不用重 build**。

## Schema / 字段表

### 3 种调试姿势对比

| 姿势 | 适合场景 | 缺点 |
|---|---|---|
| 直接调 run_demo | 教学初期,快速验证 | 单 cell,无法分步看每个工具 |
| 分步 cell 调试 | **教学最佳**,Jupyter 精髓 | 需要理解模块化拆分 |
| `main(argv)` 兼容 | 生产化,自动化测试 | 绕一圈还是走 argparse,失去 Jupyter 优势 |

### argparse + sys.exit 触发的 2 条 message

```
1. argparse: "the following arguments are required: --root"
   ↓ argparse 调 sys.exit(2)
2. IPython: "To exit: use 'exit', 'quit', or Ctrl-D."
   ↑ IPython 拦截 sys.exit,以为用户想退出
```

**这 2 条 message 是同一个根因**(argparse 没收到 --root),不是 2 个独立问题。

## 代码示例

### 姿势 1:直接调 run_demo(最简单)

```python
# %% Jupyter cell
from pathlib import Path
from week3.day4_workspace.day4_lookup_tools import run_demo

run_demo(Path("~/coco/apps/backend").expanduser().resolve())
```

**为什么有效**:`run_demo(root: Path)` 是纯函数,不读 `sys.argv`。

### 姿势 2:Jupyter 分步 cell 调试(教学最佳)

```python
# %% Cell 1: build 一次,后续 cell 复用(发挥 Jupyter 状态保持优势)
from pathlib import Path
from week3.infra.dependency_graph import build_graph_for_root

root = Path("~/coco/apps/backend").expanduser().resolve()
index, graph = build_graph_for_root(root, use_tqdm=False)
print(f"✅ {len(index['files'])} files, {len(graph['forward'])} graph nodes")

# %% Cell 2: find_definition 改不同输入反复试
from week3.day4_workspace.day4_lookup_tools import find_definition
find_definition(index, "User")

# %% Cell 3: 试 fuzzy 路径
find_definition(index, "User.login")   # 验证 normalize + fuzzy 走通

# %% Cell 4: 试 kind filter
find_definition(index, "user", kind="function")

# %% Cell 5: find_references
from week3.day4_workspace.day4_lookup_tools import find_references
find_references(graph, "app.models.user")

# %% Cell 6: 试 file 路径(归一化)
find_references(graph, "app/models/user.py")

# %% Cell 7: get_file_outline
from week3.day4_workspace.day4_lookup_tools import get_file_outline
print(get_file_outline(index, "app/models/user.py"))
```

**核心优势**:index + graph build 一次(~50ms),后续 cell 反复用。试 10 次不同 query 也不会重 build —— CLI 模式下每次跑都要重新 50ms。

### 姿势 3:让 main() 兼容 Jupyter(工程化)

```python
def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="day4 LLM lookup tools demo")
    parser.add_argument("--root", type=Path, required=True, help="项目根目录")
    args = parser.parse_args(argv)   # ← 关键:argv=None 走 sys.argv,给了就用 argv
    run_demo(args.root.expanduser().resolve())


if __name__ == "__main__":
    main()   # CLI 走默认(读 sys.argv)
```

```python
# %% Jupyter 里调
from week3.day4_workspace.day4_lookup_tools import main
main(["--root", "~/coco/apps/backend"])
#    ↑ 像命令行参数一样传 list
```

**不推荐教学阶段用** —— 绕一圈还是走 argparse,Jupyter 的"分步调试 + 状态保持"优势完全没发挥。

### autoreload magic(改代码不重启 kernel)

```python
# %% 第一个 cell(只跑一次)
%load_ext autoreload
%autoreload 2
```

**效果**:你在编辑器改 `find_definition` 函数体,**回 Jupyter 直接跑 cell**,自动重新 import 最新代码,**index/graph 不用重 build**。

## 坑 / Why

### Why argparse 在 Jupyter 必挂

```python
# argparse 内部大致逻辑
def parse_args(self, args=None):
    if args is None:
        args = sys.argv[1:]   # ← 默认从 sys.argv 读
    if missing required arg:
        sys.exit(2)           # ← 报错并退出
```

Jupyter 启动时:
```python
>>> import sys
>>> sys.argv
['/.../site-packages/ipykernel_launcher.py', '-f', '/.../kernel.json']
```

argparse 看到 `-f /.../kernel.json` → "我没有 `-f` 参数,而且 `--root` 还没给" → **报错退出**。

### Why "To exit" 警告紧跟出现

IPython 拦截 `sys.exit(2)`,以为用户想退出 shell,给的友好提示。**不是 bug**,是 IPython 的善意 —— 但在 argparse 场景下变成噪音。

### Why CLI 入口和 Jupyter 调试要分离

- **CLI**:从 `sys.argv` 解析参数 → 走 `if __name__ == "__main__"` + argparse
- **Jupyter**:直接调用 Python 函数 → 跳过 argparse,**自己手动传路径**
- **强行用同一个入口**:CLI 友好但 Jupyter 不爽,或反之

**正确架构**:
```
argparse 层(main)
    ↓ 解析后调用
纯函数层(run_demo, build_graph_for_root, find_definition, ...)
    ↓ 也可以被 Jupyter / pytest / 别的 script 直接调
```

**纯函数层永远是核心,argparse 只是"路径搬运工"**。

### Why parse_args(args) 参数化的设计

```python
args = parser.parse_args(argv)
#                        ↑ argv=None 走 sys.argv,给了 list 就用 list
```

这个 `argv` 参数是 argparse 的标准 escape hatch,**专门为"非 CLI 调用"留的**(unit test / Jupyter / 嵌入式)。**很多新手不知道这个参数**,导致 argparse + 测试代码极难写。

## 关联

- [[day4-llm-lookup-tools-architecture]] — run_demo 是 4 个工具的入口 demo
