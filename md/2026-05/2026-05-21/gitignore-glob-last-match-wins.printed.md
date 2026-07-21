# gitignore / rg glob 的 "Last Match Wins" 顺序敏感

## 触发提问

> 不是这么使用吗?[`["!*_demo.py", "*.py"]` 排除 demo 却仍命中]

> 解药 3:用 `-g '!pattern'` 排除自己 — 按这个方案来改。

## 关键结论

- **gitignore 家族(`.gitignore` / `rg -g` / `fd -g` / `ag --ignore`)统一遵循"Last Match Wins"**:列表里靠后的 pattern 优先级更高,**后规则覆盖前规则**
- **口诀:先撒网,再挖洞** — 先用宽 pattern 包含一大坨,再用 `!narrow` 挖出要排除的部分
- 顺序写反(`["!*_demo.py", "*.py"]`)→ 第二条宽 pattern 重新包含了 demo 文件,排除失效
- `-g` 可多次出现,gitignore 语法 `!prefix` 表示排除,**单字段 list + 顺序语义**比"分 include/exclude 双字段"更简洁
- 这套规则也用于 `.npmignore` / `.dockerignore` / `.eslintignore` — 学一次迁移 5 个工具

## 实测对照(同 pattern 不同 glob 顺序,结果差距 4×)

```
pattern = "def _find_rg_binary"
root    = week3

错误顺序 ['!*_demo.py', '*.py']    → 4 条 / 2 file (demo 仍命中 ❌)
正确顺序 ['*.py', '!*_demo.py']    → 1 条 / 1 file (demo 被排除 ✓)
```

## 执行语义解读

```bash
# 错误写法
rg -g '!*_demo.py' -g '*.py' "PAT" .
# 第一步: 看 "!*_demo.py" → 匹配 demo → 排除 ✓
# 第二步: 看 "*.py"       → 所有 .py 匹配 → 包括 demo! → 重新包含 ❌
# 最终: demo 没被排除

# 正确写法
rg -g '*.py' -g '!*_demo.py' "PAT" .
# 第一步: 看 "*.py"        → 所有 .py 被包含
# 第二步: 看 "!*_demo.py"  → demo 被覆盖 → 排除 ✓
# 最终: demo 被排除
```

## 类比:.gitignore 同款规则

```gitignore
# .gitignore 一行行从上往下处理,后行覆盖前行
*.log            # 第一行: 忽略所有 .log
!important.log   # 第二行: 但是 important.log 不忽略 → 后行优先
```

## 代码示例:_normalize_globs 实现

```python
def _normalize_globs(glob: str | list[str] | None) -> list[str]:
    """把 glob 参数统一成 list[str]。

    Examples:
        >>> _normalize_globs(None)                          == []
        >>> _normalize_globs("")                            == []
        >>> _normalize_globs("*")                           == []
        >>> _normalize_globs("*.py")                        == ['*.py']
        >>> _normalize_globs(["*.py", "!*_demo.py"])        == ['*.py', '!*_demo.py']
    """
    if glob is None:
        return []
    if isinstance(glob, str):
        return [] if glob in ("", "*") else [glob]
    return [g for g in glob if g and g != "*"]


# 在 _run_rg 里展开成多次 --glob
for g in _normalize_globs(glob):
    args.extend(["--glob", g])
```

## "自指匹配"坑(本主题的姊妹问题)

LLM 工具在自己项目里跑 grep 时,**pattern 字面量出现在自己 demo / test / docstring 里**会让工具命中自己 → 误以为"工具有 bug"。这是 Aider / Cursor / Continue 在 dogfooding 时都踩过的坑。

```python
# demo 文件里
result = _run_rg(rg, "XYZ_NEVER_EXISTS", week3, "*.py", 5.0)
#                     ^^^^^^^^^^^^^^^^^^
#                     这个字符串字面量出现在 demo 文件第 N 行
#                     rg 一搜就命中 demo 文件自己 → 期待 0 命中实际 1 命中
```

**3 个解药**:
1. **用随机串 pattern**:`"kjQz9_PpQyMTRwL"` — 你不会无意中写到代码里
2. **收窄 root**:不搜含 demo 的目录
3. **加 glob 排除**:`["*.py", "!*_demo.py"]` — 用 gitignore 排除语法

生产级 Coding Agent 默认排除 `docs/` / `examples/` / `test/` 路径,就是这个坑的扩展防御。

## 坑 / Why

- **顺序敏感**是 gitignore 设计哲学:逐行评估,后规则修正前规则;**不是 bug 是 feature**
- **不要分 include/exclude 双字段**:gitignore 的 `!` 前缀已经把 include/exclude 编码在字符串里,LLM 学一次就够;双字段(`include_globs / exclude_globs`)反而增加心智负担
- **测顺序坑的最佳 pattern 是"项目里也存在 + demo 里也写了"**:这样反复实验时顺序写错会立即暴露
- **LLM 工具不强制 glob 顺序**:LLM 完全可能写错。生产级会在 docstring 里**显式给口诀** + 在结果里**加 warning**:`"detected !pattern before broader *.py, may not exclude as expected"`
- **rg col 给的也是顺序敏感的字节位置**(见 [[rg-byte-offset-vs-char-index]])——顺序在 grep 工具的多个层面都重要

## 关联

- [[ripgrep-json-events]] — 多 glob 在 args 里如何展开
- [[schema-accept-multi-output-single]] — `glob` 入参接受 str/list/None 但出参规范化成 list
- [[llm-tool-actionable-error-tiering]] — 当 LLM 写错顺序导致截断时,truncated 信号会引导他自救
