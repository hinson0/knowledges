# 工程纪律 · 字符串转义 + 重跑验证 + 调试残留

> 来源:week3/day1 + day2 反复撞坑的工程化沉淀
> 落盘日期:2026-05-13

## 触发提问

- `extract_imports("import os\\nfrom typing import TypedDict")` 为什么 parse 出 ERROR 节点?
- "输出的结果跟你说的不太一样啊" / "我已经修改好了"(但贴了过期输出)
- "为什么 module level 调试代码会有问题?import 时就跑?"

## 关键结论

3 条相互独立但都属于"工程纪律"层面的反复踩坑:

1. **`\\n` 在 docstring 写法 vs runtime 字符串写法**含义不同 —— docstring 里 `\\n` 渲染成 `\n`,**runtime 代码里 `\\n` 是 2 个字符不是换行符**
2. **改了代码必须重跑** —— 修了 bug 不重跑,贴出来的输出还是过期状态,review 人 + 你自己都被误导
3. **module-level 调试代码 = import 时副作用** —— `extract_xxx(SAMPLE)` 写在 module 顶层,被人 import 时也会跑,污染输出 + 二次 parse

## 示例 · `\\n` vs `\n` 的两种语境

### 语境 1 · docstring 里要写 `\\n`(为了显示成 `\n`)

```python
def extract_imports(source: str) -> list[ImportInfo]:
    """
    Usage:
        >>> extract_imports("import os\\nfrom typing import TypedDict")
    """
```

**为什么?** docstring 是字符串字面量,渲染显示给读者时,`\\n` 转义成 `\n`(单反斜杠),用户看到 `>>> extract_imports("import os\nfrom typing import TypedDict")` 就懂"哦是换行"。

### 语境 2 · 实际调用代码必须写 `\n`(为了真的换行)

```python
# ❌ 错(从 docstring 复制粘贴下来):
extract_imports("import os\\nfrom typing import TypedDict")
# 实际传给 tree-sitter 的是:
#   import os\nfrom typing import TypedDict     (一行,反斜杠+n 是 2 个字符)
# tree-sitter 看到这种"不合法 Python"返回 ERROR 节点 → root.children[0].type == 'ERROR'

# ✅ 对(单反斜杠,Python 解释器解析成换行):
extract_imports("import os\nfrom typing import TypedDict")

# ✅ 对(triple-quote 最可读):
extract_imports("""
import os
from typing import TypedDict
""")
```

### Debug 经验

撞这个坑时,**第一反应应该是 `print(repr(s))` 看实际字符**:
```python
s1 = "import os\\nfrom typing import TypedDict"
print(repr(s1))   # 'import os\\nfrom typing import TypedDict'  ← 双反斜杠提示是字面字符

s2 = "import os\nfrom typing import TypedDict"
print(repr(s2))   # 'import os\nfrom typing import TypedDict'   ← 单反斜杠是转义后真换行
```

## 示例 · 重跑验证的纪律

### 反例 · 同一个 review 撞 2 次

**第 1 次**(day1 extract_symbols review):
- 我修了 Bug 2(start_line 用 inner → 改成 node)
- 我贴回的文件底部 docstring 输出还是修复**前**的:`"start_line": 10`(应该 8)
- Claude 误以为 Bug 2 没修好

**第 2 次**(同一文件,第二轮 review):
- 我修了 Bug 1(kind 用 node.type → 改成 inner.type)
- 文件底部 docstring 输出还是修复**前**的:`decorated_func` 的 `kind="class"`(应该 "function")
- Claude 误以为新引入 bug

**根因**:**修了代码 → 没重跑 → 粘了过期输出**。

### 解决方案 · 把"重跑 + 粘新输出"做成肌肉反射

```bash
# 在 ~/.zshrc 或 ~/.bashrc 加 alias
alias d1run='cd ~/ai_agent_learning/week3/day1_workspace && uv run python day1_indexer.py'
alias d2run='cd ~/ai_agent_learning/week3/day2_workspace && uv run python day2_indexer.py'
```

**修完代码 → 立刻 `d1run` → 粘新输出到 docstring → 再让人 review**。

### Week 4 RAG 调优会暴增到每小时几十次

Week 4 调优 RAG 时,指标对比频率会暴增 —— 每次改 prompt / 改 chunk size / 改 reranker top-k 都要重跑测试集看 faithfulness 数字。**重跑动作如果不自动化,光手输 cd 命令就累死**。day2 这一刻立"先 alias 后调优"的习惯。

## 示例 · module-level 调试代码污染

### 反例 · day1 / day2 都撞

```python
# day1_indexer.py (反例)
PARSER = Parser(Language(python_language()))   # ✅ 必须 module-level,初始化一次复用

def extract_symbols(source): ...

# ❌ 下面这些写在 module 顶层,import 时都会跑:
root = parse_code(SAMPLE_PYTHON)             # 副作用:parse 一次
for i, child in enumerate(root.children):    # 副作用:print 一堆
    print(i, child.type, child.start_point)

deco_node = root.children[2]
inner_node = next(...)
sig_line_idx = inner_node.start_point[0]      # 副作用:污染 module namespace

extract_symbols(SAMPLE_PYTHON)                # 副作用:完整提取一次,结果还丢弃了
```

**问题**:`import day1_indexer` 这个 module 时:
- print 8 行调试输出到 stderr
- module namespace 被 `root` / `deco_node` / `inner_node` / `sig_line_idx` 污染
- `extract_symbols(SAMPLE)` 跑一次但结果没赋值,纯浪费 CPU

day3 写 codebase indexer 工具调用这个 module 时,光 import 就被 spam。

### 正确做法

```python
# module 顶层只放:
# - imports
# - constants(PARSER / DEFAULT_EXCLUDE)
# - Schema 定义(TypedDict / dataclass)
# - 函数定义(def)

# 所有调试代码 / 测试调用都搬进 __main__:
if __name__ == "__main__":
    # 在这里写所有 print / 测试用例
    root = parse_code(SAMPLE_PYTHON)
    print(extract_symbols(SAMPLE_PYTHON))
```

`if __name__ == "__main__":` 块只在 `python day1_indexer.py` 直接跑时执行,**`import day1_indexer` 时不会进**。

## 坑 / Why

### `\\n` vs `\n` 的本质 = 两层转义模型

**Why**:Python 字符串在不同语境有不同转义模型:

| 语境 | `\\n` 含义 | `\n` 含义 |
|---|---|---|
| docstring 字面量(被读者眼睛看) | 渲染成 `\n` 显示 | 渲染成换行 |
| 代码 runtime(被 Python 解释器读) | 解析成 2 个字符:反斜杠 + n | 解析成 1 个换行符 |
| JSON 字符串(被 JSON parser 读) | 又是另一套规则 | 又是另一套规则 |
| Prompt template(被 LLM 读) | 又是另一套 | 又是另一套 |

**How to apply**:
- 写完 prompt / 测试 fixture / 数据填充类代码,**先 `print(repr(s))` 确认实际字符**,再传给下游
- 跨语境复制粘贴时(docstring → REPL / JSON → Python)永远检查转义层级
- week5 写 prompt template 时这条会撞 3 次以上,**习惯比知识重要**

### 重跑验证是 production 工程的必修课

**Why**:代码改对了但输出过期 → 给 review 人或下游(包括未来的自己)错误信号 → 二次 debug 浪费时间。这种"代码 vs 输出错位"的 bug 在 ML/AI 项目里尤其多 —— 改了 prompt 不重跑 eval,改了 chunk 不重跑 retrieval 指标。

**How to apply**:
- 修代码 → 重跑 → 粘新输出 → 再 review,**这 4 步不可跳**
- alias 化常用脚本,降低重跑成本
- production 项目里 CI 流水线就是"强制重跑" —— pre-commit hook 跑 lint / test,push 前自动跑 e2e
- week5 工程化时 pre-commit + Langfuse 集成 = 把重跑纪律变成系统强制

### "module 顶层只放定义,副作用进 main" 是个普世原则

**Why**:Python module 在 first import 时执行所有 top-level 代码,**之后缓存在 `sys.modules`**。如果顶层有 print / 函数调用 / 文件 I/O,第一次 import 时会跑,**second import 静默跳过**(用户根本不知道你的 module 有副作用)。这种"看不见的副作用"是大型项目里最隐蔽的 bug 源之一。

**How to apply**:
- 永远把测试 / 调试代码挪进 `if __name__ == "__main__":` 块
- module 顶层只放 `import` / 常量 / Schema / `def` / `class`
- 看到 module 顶层有 `function_call(args)` 不带 `=` 赋值,**立刻重构**(纯副作用)
- production 项目里有 `import-linter` 这类工具检测顶层副作用,可以集成进 CI

## 关联

- [[tree-sitter-python-node-schema]] — ERROR 节点为什么出现(`\\n` 字符串导致 tree-sitter 解析失败)
- [[ast-range-vs-identity-node-pattern]] — day1 重跑验证撞 2 次的 review case
- [[codebase-indexer-design-patterns]] — day2 索引器的工程化标志
- `week3/day1_workspace/day1_indexer.py` — module-level 调试残留的修复对照
- `week3/day2_workspace/day2_indexer.py` — `\\n` ERROR 节点 fixture
