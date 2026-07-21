# Grep 工具的截断信号 — 让 LLM 自我教学

## 触发提问

> 先讲透 Q2 截断策略

> 给我 mock 几个 demo[让我感受 truncated 字段]

## 关键结论

- **截断是 LLM grep 工具的命门,不是事后补救**:rg 跑 100ms 出 10k 行,LLM 一次 context 装不下 1k 行
- **`truncated: bool` + `total_matches: int` 双字段是核心设计**:让 LLM 知道"这是冰山一角"而不是"全部就这么多"
- 没有这两个字段 → LLM 把样本当全集 → 给出错误的"全项目分析"
- 有这两个字段 → LLM **自己学会**"truncated=True 时换更窄 pattern / 加 glob 收窄"——这就是"教 LLM 自救"
- **截断策略 A 起步(顺序砍 max_results=100)就够用**,配合 truncated 信号 LLM 会自救;B 方案(file 维度均衡)留给 Week 6 mini-Aider 复杂场景

## Schema:GrepResult 的元信息字段

```python
class GrepResult(TypedDict):
    matches: list[GrepMatch]    # 已截断后的命中列表
    total_matches: int          # ripgrep 实际产出多少条(可能 ≫ len(matches))
    truncated: bool             # 是否触发了截断 — ★ "自我教学"信号
    files_hit: int              # 有命中的 file 数(分布信号)
    pattern: str                # 实际传给 rg 的 pattern(可能 normalize 过)
    glob: list[str] | None      # 实际 glob filter(已规范化)
    error: str                  # 工具错误;空 = 合法状态(可能是 0 命中)
```

## 截断的 3 个独立维度

| 维度 | 控制变量 | 不防它会怎样 |
|---|---|---|
| **count 截断** | `max_results=100` | 487 条全塞进 context → 5k+ tokens 一次 |
| **content 截断** | 单条 `>200 char` 截断 + "…" | 一行 minified.js 50KB → 一条 match 撑爆 |
| **file 截断**(未实现) | per_file 限额 | 一个 file 占 47 条 → 业务 file 看不到 |

day5 实现了前两道防线,第三道留给 Week 6。

## 3 个截断方案对比

| 方案 | 实现 | 失败场景 | 评级 |
|---|---|---|---|
| **A. 顺序砍**(推荐) | `kept = all[:max_results]` | rg 按字典序输出,可能前 100 条全是 `alembic/` | ✅ 起步够 |
| **B. file 均衡** | `per_file_cap` + group by file | per_file_cap 难定 | 🟡 Week 6 升级 |
| **C. 不截断**(反例) | `return all` | LLM context 爆掉,$0.10/次 | ❌ Day 5 故意会踩的坑 |
| **D. file_stats 旁路** | matches 少量 + file 统计旁路 | 信号密度 10× A | 🌟 Aider/Cody 用 |
| **E. rg-side `--max-count`** | rg 内部 short-circuit | total 字段失真 | 🟡 仅用于 A 不在乎 total 时 |

## 代码示例:A 方案(2 行,Day 5 实现)

```python
truncated = total > max_results
kept = all_matches[:max_results] if truncated else all_matches

return GrepResult(
    matches=kept,
    total_matches=total,        # ⭐ 保留真实总数
    truncated=truncated,        # ⭐ 显式标记
    files_hit=len(files_hit),
    pattern=clean_pattern,
    glob=effective_glob,
    error="",
)
```

注意 `kept = ... if truncated else all_matches` 的小优化:不 truncated 时直接复用引用,**省一次 list copy**。

## Mock 对比:两种 GrepResult 形态

**常态(truncated=False)** — LLM 看到全部:

```python
{
    "matches": [...3 条...],
    "total_matches": 3,
    "truncated": False,    # ← 关键
    "files_hit": 2,
    "pattern": "login",
    "glob": ["*.py"],
    "error": "",
}
# LLM 解读:"3 条命中,truncated=False → 全部就这些,放心用。"
```

**截断触发(truncated=True)** — LLM 学会自救:

```python
{
    "matches": [...100 条...],
    "total_matches": 487,     # ★ 关键 1:远 > len(matches)
    "truncated": True,        # ★ 关键 2:截断触发
    "files_hit": 38,
    "pattern": "import",
    "glob": None,
    "error": "",
}
# LLM 解读:"truncated=True + total=487 → 我查得太宽:
#   1. 缩 pattern: 'from app.auth import' → 只看业务层
#   2. 加 glob: ['*.py', '!alembic/**'] → 排除 migration
#   3. 改工具: 用 day4 find_imports 反查具体 file
# 不能假定这 100 条代表 487 条全部分布。"
```

## 坑 / Why

- **`total_matches` 跟 `len(matches)` 是两个字段不是一个**:初学者会问"matches 都给了,total 不就是 `len(matches)` 吗?"——错。truncated 时 `len(matches)=100`(被砍后),`total_matches=487`(真实总数),**这俩字段的差值就是 LLM 知道"还有多少没看到"的唯一信号**
- **`files_hit` 是"二阶信号"**:`total=487 + files_hit=38` 比 `total=487 + files_hit=2` 信号完全不同:38 → 加 glob 收窄更有效,2 → 换更窄 pattern 更有效
- **不告诉 LLM 截断了 vs 告诉了**:这是工具是否成熟的分水岭。Cursor / Aider 早期版本都因为不告诉而吃过 100× 成本苦头(0.001 元 vs 0.1 元一次)
- **Day 5 的"故意会踩的坑"就是输出爆炸**:没有 truncated 信号 = 488 行直接塞进 LLM context;有信号 = LLM 自己学会收窄
- **设计哲学:能教就不要替**:方案 A(教 LLM 自救)的精神是"教",方案 B(替 LLM 做对)的精神是"替"。前者承认 LLM 是 reasoner,后者把 LLM 当哑客户端

## 关联

- [[ripgrep-json-events]] — 截断前先解析的事件流
- [[llm-tool-actionable-error-tiering]] — error 字段跟 truncated 字段是工具的两大元信号
- [[schema-accept-multi-output-single]] — 输出规范化让 LLM 看到稳定形态
