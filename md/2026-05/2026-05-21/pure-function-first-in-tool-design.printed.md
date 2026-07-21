# 工具函数设计:纯函数优先(Pure-Function-First)

## 触发提问

> 你是有点问题的,因为 glob 它支持 string 类型,但是这个私有函数它又不支持 string。

(Pyright 报错:`_make_error_result` 的 `gl` 参数要 `list[str] | None`,但 grep_code 早期 D1/D2 失败时传的还是原始入参 `str | list[str] | None`)

## 关键结论

- **归一化是纯函数,永远不会失败,应该最早执行** — 这样后续所有代码只看到一种数据形态,类型 / 测试 / 心智负担全减半
- **TODO 顺序错位**会导致类型不兼容:D1 / D2 早返回时如果归一化还没跑,传递的是"原始入参类型",跟"归一化后类型"不匹配
- **代码顺序的隐藏依赖**:看似"先 fail-fast 再处理数据"合理,但一旦类型严格(union 入参),fail-fast 路径就被卡死 — TODO 排序应按**依赖最少 → 依赖最多**,不是按"哪个先 fail-fast"

## 错误顺序 vs 正确顺序

### ❌ 错误(D1 在归一化前)

```python
def grep_code(glob: str | list[str] | None = "*.py", ...):

    def _make_error_result(pat: str, gl: list[str] | None, msg: str): ...

    # D1: rg 不在
    rg_bin = _find_rg_binary()
    if rg_bin is None:
        return _make_error_result(pattern, glob, "...")
        #                                  ^^^^ 类型错!
        #                                  glob 是 str | list[str] | None
        #                                  但 gl 要 list[str] | None

    # D2: root 不在(同样问题)
    ...

    # 归一化在最后跑(顺序错)
    clean_pattern = normalize_pattern(pattern)
    glob_list = _normalize_globs(glob)
    effective_glob = glob_list if glob_list else None
```

### ✅ 正确(归一化提到所有 fail-fast 之前)

```python
def grep_code(glob: str | list[str] | None = "*.py", ...):

    def _make_error_result(pat: str, gl: list[str] | None, msg: str): ...

    # ★ Step 1: 先归一化(纯函数,永不失败,放最前)
    #            这样下面所有 _make_error_result 都拿到归一化后形态,类型对齐
    clean_pattern = normalize_pattern(pattern)
    glob_list = _normalize_globs(glob)
    effective_glob: list[str] | None = glob_list if glob_list else None

    # Step 2: D1 - rg 不在
    rg_bin = _find_rg_binary()
    if rg_bin is None:
        return _make_error_result(clean_pattern, effective_glob, "...")
        #                          ^^^^^^^^^^^^^  ^^^^^^^^^^^^^^
        #                          归一化后形态,类型对齐 ✓

    # Step 3: D2 - root 不在
    root_path = Path(root).expanduser().resolve()
    if not root_path.is_dir():
        return _make_error_result(clean_pattern, effective_glob, f"root not found: {root}")

    # Step 4 + 5: 跑 rg + 截断
    ...
```

## 设计原则:依赖图判断 TODO 顺序

**判断 TODO 排序**的口诀:**按数据/外部依赖从少到多排**,不是按"哪个先 fail-fast"。

| 步骤 | 依赖什么 | 是否纯函数 | 排序位置 |
|---|---|---|---|
| Step 1 归一化 | 仅入参 | ✅ 纯函数 | **最前** |
| Step 2 D1 (`_find_rg_binary`) | 文件系统 (PATH) | ❌ IO | 中间 |
| Step 3 D2 (root 检查) | 文件系统 | ❌ IO | 中间 |
| Step 4 `_run_rg` | subprocess + IO + 网络? | ❌ IO + 异常 | 后 |
| Step 5 截断 + return | 仅前置数据 | ✅ 纯函数 | 最后 |

依赖最少 → 最先做。纯函数 + 不会失败的步骤永远应该排在 IO/失败步骤之前。

## 为什么这条原则容易被违反

新手直觉:"看 rg 在不在 PATH 是第一件事,先 fail-fast" → 把 D1 放最前。但是:

- D1 失败时**也要返回 GrepResult**,GrepResult 字段需要归一化后的 pattern / glob
- 如果 D1 在归一化前,D1 失败时拿不到归一化后的数据,**只能传原始入参** → 跟 `_make_error_result(gl: list[str] | None)` 类型不兼容
- **fail-fast 不等于"代码最前面"** — fail-fast 是"早期检测早期返回",但前置数据**应该先准备好**

## 类似设计的 case 对照

| 项目 | 错误顺序 | 正确顺序 |
|---|---|---|
| day5 grep_code | D1 → D2 → 归一化 → run → 截断 | **归一化 → D1 → D2 → run → 截断** |
| Flask route handler | DB 查询 → 验证 input → 转换 input | **验证 input → 转换 input → DB 查询** |
| HTTP API | 鉴权 → parse body → validate fields | **parse body → validate fields → 鉴权** |
| 编译器 | optimize → type check → parse | **parse → type check → optimize** |

## 坑 / Why

- **类型错位暴露了"两种数据形态共存超过必要时长"**:原始 `glob: str | list[str] | None` 和归一化后 `effective_glob: list[str] | None` 在同一函数里**共存了多少行代码**,就有多少行容易出类型 bug
- **修法本质**:让归一化结果**尽早覆盖**原始入参,让函数主体只看到一种形态 — "pure-function-first" 是这个目标的实现路径
- **跟 Cleaner Code 的 "pure-function-first"**:Robert Martin 的原话是"all side effects should happen after pure transformations are done"(所有副作用应该在纯转换完成之后才发生)
- **测试上的额外收益**:把归一化拆成独立函数(`normalize_pattern` / `_normalize_globs`)且放最前,**测试可以单独跑这两个函数**,不用 mock 整个 grep_code 流程

## 关联

- [[schema-accept-multi-output-single]] — 归一化是"接受多形态/输出单形态"的具体实现
- [[llm-tool-actionable-error-tiering]] — D1/D2/D3/D4 4 档错误兜底,都依赖归一化先跑完
