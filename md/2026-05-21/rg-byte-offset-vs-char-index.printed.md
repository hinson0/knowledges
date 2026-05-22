# rg col 字段是 byte offset,不是 char index

## 触发提问

> [实测发现] line 530 的 col_start/col_end 用 content[col_start:col_end] 切出来不是 normalize_pattern,而是 'e_pattern(代笔,LLM '

> 表示的不是 column,它是列的意思[澄清 col 字段的语义]

## 关键结论

- **`rg --json` 的 `submatches[].start/end` 是 UTF-8 byte offset**,不是 Python `str` 的 char index
- 对**纯 ASCII content** 两者等价(1 byte = 1 char);对**中文 / emoji / 韩文** content,Python `content[s:e]` 切出来跟期望不符
- 要切对必须走 byte:`content.encode()[s:e].decode("utf-8")`
- `GrepMatch.col_start` 注释里写"Python 切片友好"是**误导性描述**,只对 ASCII 文本成立 — 应改成 "0-based UTF-8 byte offset"
- 列号(col)在 Unix 编辑器术语里 = column,不是 row;`line` 字段才是行号

## 实测对照(同一个 pattern "normalize_pattern")

```
content = '# %% 工具函数:normalize_pattern(代笔,LLM 容错)----...'

【含中文 content】
col_start=18, col_end=33

  content[18:33]                  == 'e_pattern(代笔,LLM '     ❌ Python str 切错
  content.encode()[18:33].decode() == 'normalize_pattern'      ✓ byte 切对


【纯 ASCII content】
content = 'def normalize_pattern(raw: str) -> str:'
col_start=4, col_end=21

  content[4:21]                  == 'normalize_pattern'    ✓ Python str 切对
  content.encode()[4:21].decode() == 'normalize_pattern'    ✓ byte 切对
  (ASCII 下 char index == byte offset)
```

## Why:中文为何错位

```python
content = '# %% 工具函数:normalize_pattern...'

# 字符位置(char index, Python str 切片用):
# '#'=0, ' '=1, '%'=2, '%'=3, ' '=4,
# '工'=5, '具'=6, '函'=7, '数'=8, ':'=9,
# 'n'=10, 'o'=11, ...

# 字节位置(byte offset, rg 给的):
# '#'=0, ' '=1, '%'=2, '%'=3, ' '=4,
# '工'=5..7 (UTF-8 3 bytes), '具'=8..10, '函'=11..13, '数'=14..16,
# ':'=17, 'n'=18, 'o'=19, ...

len("# %% 工具函数".encode())  # → 17 bytes
len("# %% 工具函数")           # → 9 chars(汉字 1 char)
```

## 代码示例:安全切片辅助函数

```python
def match_text(m: GrepMatch) -> str:
    """安全切出命中片段,兼容中文/emoji content。"""
    return m["content"].encode()[m["col_start"]:m["col_end"]].decode(
        "utf-8", errors="replace"
    )

# 使用对比
match_text(m)              # ✓ 永远对
m["content"][s:e]          # 仅 ASCII 对,中文错
```

## Schema 描述应该怎么写(修正版)

```python
class GrepMatch(TypedDict):
    """grep_code 单条命中。

    Schema:
        file:       命中所在文件(相对 root)
        line:       命中行号(1-based)
        content:    该行内容(去尾换行,>200 char 截断 + "…")
        col_start:  命中片段的起始字节 (0-based UTF-8 byte offset)。
                    ⚠ 不是 char index — 含中文/emoji content 下不能 content[s:e] 直接切。
                    要切对:content.encode()[s:e].decode()
        col_end:    结束字节(exclusive)。同上,byte offset。
    """
```

(原版"Python 切片友好"是错的)

## 行 / 列 命名传统对照

| 系 | 行 | 列 | 用于 |
|---|---|---|---|
| Unix grep/vim/ripgrep | `line` | `column` (col) | 编辑器 / grep 工具 |
| 数据库 / 电子表格 | `row` | `column` | SQL / Excel / pandas |
| GUI 编辑器(VSCode 状态栏) | `Ln` | `Col` | 给人看 |

day5 跟 ripgrep 走同一套(line + col)。两套**不要混用**:
- ✅ `{"line": 24, "col_start": 17, "col_end": 22}`  (Unix 风)
- ✅ `{"row": 24, "column_start": 17, "column_end": 22}` (DB 风)
- ❌ `{"row": 24, "col_start": 17}` (混搭,读者要二次反应)

## 坑 / Why

- **rg 选 byte offset 不是 char index 的原因**:rg 是 Rust 写的,处理任意编码字节流;byte offset 是无歧义的"绝对位置",char index 在不同语言/规范化下不一致
- **day5 透传 byte offset 不做转换的取舍**:转换要每条 match 都 encode() 一次,成本不低;且 99% 代码搜索是 ASCII,转换收益小 — **简化设计、文档化坑**
- **Week 6 mini-Aider 做精确高亮时要补转换**:如果 Coder 想做 `content[col_start:col_end]` 切片做 cite,必须走 byte 路径
- **col 字段对 LLM 几乎没用,但对 IDE 集成层有用**:LLM 看整行就够,IDE 用 col 做高亮 — schema 字段保留与否看下游消费者,不看上游产生者
- **submatches 数组(rg 一行内可能多个 submatch)**:day5 简化只取第一个,生产级实现需要循环所有 submatches

## 关联

- [[ripgrep-json-events]] — submatches.start/end 在事件流里的位置
- [[schema-accept-multi-output-single]] — schema 描述的"误导性术语"也是设计债
