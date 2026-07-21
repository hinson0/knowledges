# LLM 工具 Schema 设计:接受多形态,输出单形态

## 触发提问

> 解药 3:用 `-g '!pattern'` 排除自己 — 按这个方案来改

## 关键结论

- **入参容忍多形态,出参规范化成单形态** — 这是 LLM 工具 schema 的黄金原则
- 入参 `glob: str | list[str] | None` 接受 3 种形态(向后兼容 + 灵活性);出参 `GrepResult.glob: list[str] | None` 永远是 list(规范化)
- LLM 调用工具有多种"自然语言式"习惯(忘了清理、用单个字符串、用 list、用通配符),工具层做防御性归一化能**减少 LLM 心智负担**
- 这跟 day4 的 `normalize_symbol("User.login")` 是同款设计(传"User.login" 容忍,返回归一化后的"login")
- 减少 schema 字段数 > 增加分类字段:用 gitignore 的 `!` 前缀(`["*.py", "!*_demo.py"]`)比分双字段(`include_globs / exclude_globs`)更省心

## 入参 / 出参对照表(以 day5 grep_code 为例)

| 字段 | 入参类型(容忍) | 出参类型(规范化) |
|---|---|---|
| `pattern` | `str` (可能带引号 / 括号 / 空格) | `str` (`normalize_pattern` 后的 plain string) |
| `glob` | `str \| list[str] \| None` | `list[str] \| None` |
| `root` | `Path \| str` | (内部转 Path,不出参) |

入参形态(LLM 写得舒服) → 内部归一化(工具层吸收复杂度) → 出参形态(LLM 看得稳定)。

## 归一化辅助函数模式

```python
def _normalize_globs(glob: str | list[str] | None) -> list[str]:
    """把 glob 参数统一成 list[str]。"""
    if glob is None:
        return []
    if isinstance(glob, str):
        return [] if glob in ("", "*") else [glob]
    return [g for g in glob if g and g != "*"]


def normalize_pattern(raw: str) -> str:
    """LLM 习惯加引号 / 括号,去掉。"""
    s = raw.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        s = s[1:-1].strip()
    if s.endswith("()"):
        s = s[:-2].rstrip()
    return s
```

`if g and g != "*"` 是 Python 经典惯用法 — 过滤"假过滤"输入(空串 + 通配符):

```python
_normalize_globs(["*.py", "", "*", "!*_demo.py"]) == ["*.py", "!*_demo.py"]
#                            ↑    ↑
#                       空串过滤  "*" 过滤
```

## 单字段 list vs 双字段 include/exclude(为何选前者)

| 维度 | 单字段 list + gitignore 语法 | 双字段 include_globs / exclude_globs |
|---|---|---|
| LLM 调用心智 | 学一次 gitignore 语法,迁移 5 个工具 | 每次想"放哪个字段" |
| 跟生态一致性 | `.gitignore` / `rg -g` / `.npmignore` / `.dockerignore` 全用这套 | 自创类别,LLM 难学 |
| schema 字段数 | 1 | 2 |
| 表达力 | 强(顺序敏感的 include / exclude 互相覆盖) | 弱(分类后无顺序语义) |

**原则**:**少字段 + 复用社区标准语法 > 多字段 + 自创类别**。

## "误传容错"防御性过滤

LLM 偶尔传:
- `["*.py", ""]` — 忘了清理
- `["*"]` — 以为 "*" 是通配符可以传
- `None` / `""` / `"*"` — 三种"不过滤"的等价写法

工具层做防御性过滤后,LLM **不用学这种细节**,工具层吸收复杂度。

## 这套原则的其他应用

| 场景 | 入参容忍 | 出参规范 |
|---|---|---|
| day4 `find_definition(symbol)` | `"User.login"` / `"login()"` / `"login"` | 内部 `normalize_symbol()` 后查 |
| day4 `find_references(target)` | `"app.models.user"` / `"app/models/user.py"` | 自动判断 file 路径还是 module 名 |
| day5 `grep_code(glob)` | `None` / `"*.py"` / `["*.py", "!demo"]` | 出参永远 `list[str] \| None` |
| HTTP API field 接受 | `"true"` / `1` / `True` | 出参永远 `bool` |

## 坑 / Why

- **TypedDict 管字段、不管语义约束**:Python 的 TypedDict 只能保证 `col_start: int`、`col_end: int`,但保证不了 `content[col_start:col_end] == matched_text`。这类**跨字段约束**(cross-field invariant)要靠 ① runtime validator ② Pydantic `@model_validator` ③ property-based testing
- **入参 union 是为了 LLM 友好,内部 union 是债**:函数体内**不应该**长时间持有 `str | list[str] | None` 这种 union 类型 — 应该尽早 normalize,让函数主体只看到一种形态
- **跟 [[pure-function-first-in-tool-design]] 紧密相关**:归一化应该最早跑(纯函数 + 不会失败),让所有后续代码(包括 fail-fast 检查)都拿到归一化后的稳定形态
- **不替 LLM 想太多,保留它表达力**:`normalize_pattern` 不做"激进 escape 正则元字符" — 因为 rg pattern 默认是正则,激进 escape 会丢失 LLM 主动用正则的能力。**容错归一化要克制**,不要替 LLM 决定它的意图

## 关联

- [[pure-function-first-in-tool-design]] — 归一化作为纯函数应该放最前
- [[gitignore-glob-last-match-wins]] — gitignore 语法的具体应用
- [[llm-tool-actionable-error-tiering]] — 出参规范化也包含 error 字段的形态稳定性
