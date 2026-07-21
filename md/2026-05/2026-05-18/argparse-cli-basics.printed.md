# argparse · CLI 参数解析的标准库 4 件套

> 来源:week3/day3_workspace · day3_dependency_graph.py 的 main() CLI 入口
> 落盘日期:2026-05-18

## 触发提问

- argparse 是干嘛的?这段代码简单讲一下。
- `type=Path` 是什么意思?
- `required=True` 跟 `default=...` 的区别?
- `--project-name` 在 Python 里怎么访问?

## 关键结论

- `argparse` = Python 标准库,**声明一份"参数 schema",然后解析命令行字符串成 Python 对象**
- **4 件套**:`ArgumentParser` 实例 → `add_argument` 声明 → `parse_args()` 解析 → `args.xxx` 访问
- **`type=Path`** = 边界类型转换(进入即转,内部全程强类型),跟 pydantic、`_text` helper 一脉相承
- **`required=True`** = fail-fast(缺参数立刻死,不要默默 None)
- **自动 `--help`** = "配置即文档",降低 onboarding 成本
- 横杠转下划线:`--project-name` → `args.project_name`(argparse 自动转)

## Schema · argparse 4 件套流程

```text
Step 1:创建 parser
    parser = argparse.ArgumentParser(description="...")

Step 2:声明每个参数(N 次)
    parser.add_argument("--root", type=Path, required=True, help="...")
    parser.add_argument("--project-name", default=None, help="...")
    parser.add_argument("--output-dir", type=Path, default=Path(...))

Step 3:解析
    args = parser.parse_args()
    # 自动读 sys.argv,返回 Namespace 对象

Step 4:用属性访问
    args.root            # → Path("/...")
    args.project_name    # → str or None  (横杠转下划线)
    args.output_dir      # → Path(...)
```

## 字段表 · add_argument 常用字段

| 字段 | 含义 | 例子 |
|---|---|---|
| 第 1 参数 `"--xxx"` | 参数名,**双横杠 = 长选项**,单横杠 `"-x"` = 短选项 | `"--root"` / `"-r"` |
| `type=` | 收到字符串后**自动调这个可调用对象转换** | `Path` / `int` / `float` / `json.loads` / 自定义函数 |
| `required=` | 是否必填;不传会立刻报错退出 | `True` / `False`(默认) |
| `default=` | 不传时的默认值 | `None` / `Path("./output")` / `10` |
| `help=` | `--help` 显示的解释 | `"项目根目录,如 ~/coco"` |
| `action=` | 特殊行为(store_true / append / count 等) | `"store_true"` 让 flag 不带值 |
| `choices=` | 限定取值范围 | `["asc", "desc"]` |

## 代码示例 · day3 CLI 入口

```python
import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="day3 codebase dependency graph")
    parser.add_argument(
        "--root",
        type=Path,
        required=True,
        help="项目根目录,如 ~/coco/apps/backend",
    )
    parser.add_argument(
        "--project-name",
        default=None,
        help="项目模块名(默认取 root 文件夹名)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parent,
        help="输出目录(默认 day3_workspace/)",
    )
    args = parser.parse_args()

    root = args.root.expanduser().resolve()       # ~ 展开 + 转绝对
    project_name = args.project_name or root.name  # 没传就 fallback root 文件夹名
    # ... 后面用 root / project_name / args.output_dir 干活
```

## 示例 · type= 边界类型转换的妙用

```python
parser.add_argument("--root", type=Path)                   # str → Path
parser.add_argument("--top-n", type=int, default=10)       # str → int
parser.add_argument("--threshold", type=float, default=0.55)  # str → float
parser.add_argument("--config", type=json.loads, default="{}")  # str → dict
```

**没 type 时**:`args.root` 是字符串 `"~/coco/apps/backend"`(`~` 没展开,需要手动 `os.path.expanduser`)
**有 `type=Path`**:`args.root` 直接是 Path 对象,后面 `.expanduser().resolve()` 链式调用

## 示例 · 自动生成的 --help 输出

```bash
$ uv run python day3_dependency_graph.py --help

usage: day3_dependency_graph.py [-h] --root ROOT
                                 [--project-name PROJECT_NAME]
                                 [--output-dir OUTPUT_DIR]

day3 codebase dependency graph

options:
  -h, --help            show this help message and exit
  --root ROOT           项目根目录,如 ~/coco/apps/backend
  --project-name PROJECT_NAME
                        项目模块名(默认取 root 文件夹名)
  --output-dir OUTPUT_DIR
                        输出目录(默认 day3_workspace/)
```

**`-h / --help` 是 argparse 免费送的**,不用手写。

## 示例 · 漏传必填参数的 fail-fast

```bash
$ uv run python day3_dependency_graph.py

usage: day3_dependency_graph.py [-h] --root ROOT ...
day3_dependency_graph.py: error: the following arguments are required: --root
$ echo $?
2
```

退出码 2,**省去你手写一堆 `if not args.root: print("..."); sys.exit(1)` 防御代码**。

## 坑 / Why

### `type=Path` 是个"边界类型转换"模式

**Why**:跟 day2 写的 `_text` helper 是同一个哲学 —— **在系统入口处把字符串收窄成更严格的类型,内部全程用强类型**。

**How to apply**:
- argparse 让你**永远不会遇到"我以为是 Path 但其实是 str 的 bug"**
- 对比 bash 脚本:`$1 $2 $3` 永远是字符串,你得手动 `[ -d "$1" ]` 等防御,容易写错
- **Python + argparse 的"声明式类型"** = bash 脚本痛点终结者
- production-grade Python 工具(ruff / mypy / pytest / black)都用 argparse 或 click

### `required=True` 的 fail-fast 哲学跟 pydantic-settings 一脉相承

**Why**:**缺必填参数就立刻死,不要"用默认值悄悄继续"**。`required=False, default=None` 的危险在于:**用户忘记传时,代码用 None 跑下去,直到几行后 None 触发 AttributeError**,debug 路径长。

**How to apply**:
- argparse + pydantic 的组合是 Python "fail-fast" 工程范式的代表
- 启动时把所有参数 / 配置都强校验一遍,通过启动检查 = 后续代码可以放心用强类型
- week5 工程化时你会发现,production-grade 服务启动的前 100 行几乎都在做这种 fail-fast 校验

### `--help` 自动生成 = "配置即文档"

**Why**:你写完 4 个 `add_argument`,你的脚本就有了清晰的"对外契约":必填什么、可选什么、默认是啥、含义是啥。**Week 5 工程化时,任何 CLI 工具的"3 分钟入门"就是 `--help`** —— argparse 自动生成的 help 直接当文档用。

**How to apply**:
- 不用单独写 README 解释参数
- 用户看 `--help` 比读 README 快
- 这就是为什么 production-grade Python 工具都用 argparse/click

### 横杠转下划线是 argparse 的自动行为

**Why**:`--project-name` 在 Python 里不是合法变量名(横杠是减号),argparse 自动转成 `args.project_name`。

**How to apply**:
- 命令行用横杠(用户友好,符合 Unix 风格)
- Python 代码用下划线(语言要求)
- argparse 桥接两边

## 关联

- `week3/day3_workspace/day3_dependency_graph.py:main` — 实战代码
- `~/knowledges/md/2026-05-13/codebase-indexer-design-patterns.md` — `_text` helper 同款"边界类型转换"模式
- week5 工程化时 click / typer 是 argparse 的现代替代品(基于类型注解自动生成)
