# LLM 工具的错误分档:Actionable Error Tiering

## 触发提问

> 先讲透 Q4 错误兜底分档

> review @week3/day5_workspace/day5_grep_code.py 508-689

## 关键结论

- **错误分类要按"LLM 应对动作"分,不是按"哪一层报的错"分** — 从消费者视角设计错误码,不是从生产者视角
- **错误档合并标准**:两个错的 LLM 应对动作相同 → 可合并;不同 → 必须分开
- **Day 5 grep_code 4 档错误**:D1 rg 不在 / D2 root 不存在 / D3 timeout / D4 invalid regex — 4 档对应 4 种不同的 LLM 应对
- **`error=""` 是合法状态,不是错误**:0 命中走 `error=""` 路径,真错走 `error="..."` 路径
- error message 5 条铁律:**说出哪里坏 / 告诉怎么修 / 不要堆栈 / 不要重复 input / 不要英中混杂**

## Day 5 grep_code 的 4 档错误

| 档 | 触发情况 | LLM 应对动作 | 不应做 | error message 示例 |
|---|---|---|---|---|
| **D1** | `_find_rg_binary` 返回 None | **换工具**(用 read_file + Python re 兜底) | 不要重试 grep_code | `"ripgrep not found in PATH; install via `brew install ripgrep`"` |
| **D2** | `root` 路径不存在 | **改 root 路径**(拼错/stale/相对 vs 绝对) | 不要换工具 — rg 还在 | `"root not found: /totally/fake/path"` |
| **D3** | `subprocess.TimeoutExpired` | **收窄查询**(加 glob / 缩 pattern / 缩 root) | 不要原样重试 — 超时不会自愈 | `f"ripgrep timed out after {timeout}s; narrow glob or pattern"` |
| **D4** | rg 退出码 2 → `RuntimeError` | **改 pattern 写法**(escape 元字符 / 改 fixed-string) | 不要换工具 — 是你写错了 | `"invalid regex: <stderr from rg>"` |

## 不区分档的"合法状态"(等价 0 命中)

```python
# 0 命中:matches=[] + error=""
# LLM 应对:换 pattern / 加 --no-ignore 再试 / 确认拼写
GrepResult(matches=[], total_matches=0, ..., error="")
```

⚠ 不要把这个跟 D1-D4 混为一谈 — `error == ""` 是工具正常运行,只是没找到。

## 区分诊断逻辑(给 LLM 用)

```python
if result["error"]:
    # 非空 error → 工具问题(D1-D4)
    handle_tool_error(result["error"])
elif not result["matches"]:
    # error 空 + matches 空 → 真 0 命中
    suggest_change_pattern()
else:
    # 正常命中
    work_with_matches(result["matches"])
```

## error message 5 条铁律

| # | 铁律 | 反例 | 正例 |
|---|---|---|---|
| 1 | 说出**哪里**坏 | `"Internal error"` | `"ripgrep not found in PATH"` |
| 2 | 告诉**怎么修** | `"Subprocess failed"` | `"narrow glob or pattern"` |
| 3 | **不堆栈跟踪** | `"Traceback (most recent call last):\n  File ..."` | 一句话描述 |
| 4 | **不重复 input** | `"Failed pattern='login' glob='*.py'..."` | 这些已在 GrepResult 字段里 |
| 5 | **不英中混杂** | `"ripgrep 没找到,install via brew"` | 统一英文或统一中文 |

第 4 条是新手最容易踩的"信息冗余"——pattern / glob / root 都是 GrepResult 独立字段,error 里再 echo 浪费 token。

## 应该合并的细分(LLM 应对动作相同)

| 合掉的细分 | 归一档 | 理由 |
|---|---|---|
| rg 二进制损坏 / 未安装 / 权限不足 | D1 | LLM 都是"换工具" |
| root 是 file 不是 dir / root 不存在 / 无读权限 | D2 | LLM 都是"改路径" |
| regex 语法错 / PCRE2 特性不支持 / pattern 为空 | D4 | LLM 都是"改 pattern" |

## 不能合并的对比(LLM 应对动作不同)

| 容易误合 | 实际差异 |
|---|---|
| D2 vs D3 | "改路径" vs "收窄查询" — 反向操作 |
| D1 vs D4 | "换工具" vs "改写法" — 完全不同应对 |
| D3 vs 0 命中(`error=""`) | 真错 vs 合法状态 — 0 命中不是错误 |

## 代码示例:4 档实现

```python
def grep_code(pattern, root, glob="*.py", max_results=100, timeout=5.0) -> GrepResult:

    def _make_error_result(pat, gl, msg) -> GrepResult:
        return GrepResult(
            matches=[], total_matches=0, truncated=False, files_hit=0,
            pattern=pat, glob=gl, error=msg,
        )

    # 归一化(纯函数先跑,见 [[pure-function-first-in-tool-design]])
    clean_pattern = normalize_pattern(pattern)
    glob_list = _normalize_globs(glob)
    effective_glob = glob_list if glob_list else None

    # D1
    rg_bin = _find_rg_binary()
    if rg_bin is None:
        return _make_error_result(
            clean_pattern, effective_glob,
            "ripgrep not found in PATH; install via `brew install ripgrep`",
        )

    # D2
    root_path = Path(root).expanduser().resolve()
    if not root_path.is_dir():
        return _make_error_result(
            clean_pattern, effective_glob,
            f"root not found: {root}",
        )

    # D3 + D4 — 在 try/except 里
    try:
        all_matches, total, files_hit = _run_rg(
            rg_bin, clean_pattern, root_path, effective_glob, timeout
        )
    except subprocess.TimeoutExpired:
        return _make_error_result(
            clean_pattern, effective_glob,
            f"ripgrep timed out after {timeout}s; narrow glob or pattern",
            # ↑↑↑ 注意:
            #   - f 前缀必须有(不然 {timeout} 不被替换)
            #   - "timed out" 两个词,中间空格(英语固定搭配,不是 "timedout")
        )
    except RuntimeError as e:
        return _make_error_result(
            clean_pattern, effective_glob,
            f"invalid regex: {e}",
        )

    # 正常路径 + 截断
    truncated = total > max_results
    kept = all_matches[:max_results] if truncated else all_matches
    return GrepResult(
        matches=kept, total_matches=total, truncated=truncated,
        files_hit=len(files_hit), pattern=clean_pattern,
        glob=effective_glob, error="",
    )
```

## error 字段:single string vs 结构化 GrepError?

**当前 day5(扁平 string)**:
```python
error: str  # 空 = 无错;非空 = "<问题>; <建议>"
```

**也可以更结构化(没采用)**:
```python
class GrepError(TypedDict):
    code: Literal["rg_not_found", "root_not_found", "timeout", "invalid_regex"]
    message: str
    suggestion: str
    detail: str
```

| 维度 | 扁平 string | 结构化 GrepError |
|---|---|---|
| LLM 消化 | 直接读自然语言 | 要 parse dict |
| 字段密度 | 一句话搞定 | 4 字段易冗余 |
| 错误种类 | 4 档,简单够用 | 10+ 档才值得结构化 |
| 升级路径 | 反向兼容,加 `error_code` 字段就升级 | 当前过度设计 |

**Day 5 选扁平,Week 6 mini-Aider 有 retry 逻辑(按 code dispatch)时再升级**。

## 真 bug 案例:timeout error message 的两个错叠加

```python
# 当前出 bug 的写法
"ripgrep timedout after {timeout}s; narrow glob or pattern"
#         ^^^^^^^^^                ^^^^^^^^^^
#         拼写错(应该是 "timed out") {timeout} 不被替换(缺 f 前缀)

# 修正:
f"ripgrep timed out after {timeout}s; narrow glob or pattern"
```

**两个错叠加的破坏力 > 两个错单独**:
- 单独"拼写 timedout":LLM 能猜
- 单独"缺 f 前缀":LLM 看到字面 `{timeout}s` 也像超时
- 叠加 `"timedout after {timeout}s"`:**LLM 既不像英语又不像格式化字符串,可能误判为"工具坏了"**

**测 LLM 工具的 error message 的 trick**:跑一遍 demo 触发 error,**把 error 字符串 print 出来照镜子读一遍** — 你自己读不顺、看不懂"该咋办",LLM 也读不顺。

## 坑 / Why

- **LLM 工具的 error 跟 Python exception 哲学相反**:
  - Python `try/except` 鼓励**多种细分 Exception 类型**(`FileNotFoundError` / `PermissionError`),因为程序写代码时按类型 dispatch
  - LLM 工具反着来 — LLM 不写 try/except,是个读字符串的 reasoner,**字符串内容比类型签名更重要**
- **Cursor / Aider 早期 bug**:把 Python exception 一股脑 `str(e)` 丢回去 → LLM 看 `"[Errno 2] No such file or directory: '/path/...'"` 一头雾水(Errno 2 是啥?) → 改成 `"path not found: /path/...; check spelling"` 才稳
- **0 命中 vs 真错的"合法状态原则"**:Python `dict.get()`(找不到返回 None,合法) vs `list.index()`(找不到 raise,真错)是普遍设计模式;day5 grep 用 `.get()` 风格,因为 LLM grep "不存在的 symbol" 是高频合法操作

## 关联

- [[pure-function-first-in-tool-design]] — 4 档错误兜底的实现依赖归一化先跑完
- [[grep-truncation-self-teaching-signal]] — `error` 和 `truncated` 是 GrepResult 的两大元信号
- [[schema-accept-multi-output-single]] — error 字段的"扁平 string vs 结构化"是同源设计选择
