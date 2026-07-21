# ripgrep --json 事件流

## 触发提问

> 简单介绍一下这个东西[ripgrep],然后给一到两个最小 demo。

> 这个 _run_rg 函数的使用 给我几个 demo

## 关键结论

- **`rg --json` 输出 JSONL** — 每行一个独立 JSON 事件,**不是整块 JSON**;不能用 `json.loads` 整块解析,要 `splitlines()` 逐行 `json.loads`
- 事件流 4 类:`begin` / `match` / `end` / `summary`,**只关心 `match` 类型**,其他跳过即可
- **退出码 3 个语义**:`0=有命中` / `1=无命中(合法)` / `2=真错`;**`1 不是错误`**,Python `subprocess.run(check=False)` 是必须的
- 流式事件流的设计意义:rg 可能搜几万 file 跑几秒,JSONL 让调用方一边读一边解析,**命中够数可立即 SIGTERM 杀进程**(生产级实现)
- 文本模式下 `path` 字段是 `{"text": "..."}`,binary 文件是 `{"bytes": "..."}` — 后者 LLM 看不懂,实现里要跳过

## 事件流 Schema(每条事件的 JSON 结构)

```json
// begin — 开始搜某 file
{"type":"begin", "data":{"path":{"text":"..."}}}

// match — 一条命中(主要要解析的)
{"type":"match",
 "data":{
   "path":{"text":"..."},
   "lines":{"text":"该行内容\n"},
   "line_number": 42,
   "absolute_offset": 1234,
   "submatches":[
     {"match":{"text":"login"}, "start":17, "end":22}  // start/end 是 byte offset
   ]
 }}

// end — 该 file 搜完
{"type":"end",
 "data":{"path":{"text":"..."}, "binary_offset":null, "stats":{...}}}

// summary — 全局搜完
{"type":"summary",
 "data":{"elapsed_total":{"human":"0.004026s","secs":0,"nanos":4025958}, "stats":{...}}}
```

## 代码示例:最小解析器

```python
import subprocess, json
from pathlib import Path

def run_rg(rg_bin: str, pattern: str, root: Path, glob: str | None, timeout: float):
    args = [rg_bin, "--json", pattern, str(root)]
    if glob:
        args.extend(["--glob", glob])

    proc = subprocess.run(
        args,
        capture_output=True,
        text=True,           # UTF-8 自动解码
        timeout=timeout,
        check=False,         # ❗ 不能 check=True:退出码 1 = 无命中是合法的
    )

    # 退出码 2 = 真正出错(regex parse error 等)
    if proc.returncode == 2:
        raise RuntimeError(f"ripgrep error (exit code 2): {proc.stderr.strip()}")

    matches = []
    for line in proc.stdout.splitlines():
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            # 偶发的非 JSON 行(binary skip 提示),跳过
            continue

        if event.get("type") != "match":
            continue

        data = event["data"]
        path_text = data.get("path", {}).get("text")
        if not path_text:  # binary 文件跳过
            continue

        matches.append({
            "file": path_text,
            "line": data.get("line_number", 0),
            "content": data.get("lines", {}).get("text", "").rstrip("\n"),
            "col_start": data["submatches"][0]["start"] if data.get("submatches") else 0,
            "col_end":   data["submatches"][0]["end"]   if data.get("submatches") else 0,
        })

    return matches
```

## 坑 / Why

- **为什么用 `--json` 而不是 `--vimgrep`**:`--vimgrep` 是 plain text(`file:line:col:content`),content 里有 `:` / `\n` / 转义会让 parse 错位;`--json` 每条事件字段名固定 + UTF-8 已解码 + multi-line match 也有结构,**工具化封装时唯一稳定选择**
- **不要用 `shell=True` 拼字符串**:pattern 里含 `;` / `$` / 反引号会执行任意命令 → 用 `args=list[str]` 形式,subprocess 自动 escape
- **`--json` 不是 JSON 是 JSONL**:`json.loads(proc.stdout)` 直接挂,要 `splitlines()` + 逐行 parse
- **rg 默认 respect `.gitignore` + 跳 binary + 跳 hidden**:这是 feature 不是 bug;LLM 想搜 `.gitignored` 目录要加 `--no-ignore`
- **stdout 偶尔混非 JSON 行**:如 binary skip 提示、stderr 串到 stdout — try/except `JSONDecodeError` 跳过,不要让一行炸掉整个 parse

## 关联

- [[grep-truncation-self-teaching-signal]] — 解析完事件后如何包装成 LLM 友好的 GrepResult
- [[rg-byte-offset-vs-char-index]] — submatches.start/end 是 byte offset,中文 content 切片不能直接 Python str
- [[gitignore-glob-last-match-wins]] — `-g` 多次出现的顺序敏感语义
