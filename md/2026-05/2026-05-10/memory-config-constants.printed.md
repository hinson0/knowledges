# Day 5 长期记忆模块的配置常量

> 来源：week2/day5_workspace/0510_2/1712.md。day5_memory.py 模块顶部的 magic number 集中定义，调召回质量时的统一入口。

## 常量清单

```python
DB_PATH = "./memories.sqlite"
EMBED_MODEL = "BAAI/bge-m3"
EMBED_DIMS = 1024
TOP_K = 3
SCORE_THRESHOLD = 0.5
```

## 字段表

| 常量 | 含义 | 谁在用 / 为什么这个值 |
|------|------|---------------------|
| `DB_PATH` | SQLite 库的文件路径，memory 表 + 向量 BLOB 都存这里 | `MemoryStore.__init__` 用它建表；路径相对当前工作目录——在哪个目录跑 `python day5_memory.py`，就在哪里生成文件 |
| `EMBED_MODEL` | embedding 模型名，传给硅基流动 API 的 `model` 字段 | `_embed()` 方法的 POST body 里；CLAUDE.md 技术栈表写定的就是 `BAAI/bge-m3` |
| `EMBED_DIMS` | 向量维度 = 1024 | 当前代码其实**没人用它**（只是给你做"心理参考"：bge-m3 默认 dense 模式输出 1024 维）。如果以后接 Chroma/Qdrant，建集合时要传这个数；现在算文档型常量 |
| `TOP_K` | 召回返回前几个结果 | `MemoryStore.search(k=TOP_K)` 默认值，也是 retrieve_memory 节点该传的；3 是 RAG 通用起步值 |
| `SCORE_THRESHOLD` | 相似度阈值，低于它的召回结果丢弃 | retrieve_memory 节点过滤用；0.5 是猜的，**smoke test 已经看到这个值不靠谱**（query="我电脑啥配置"，连"今天天气不错"都过 0.5 进来了）|

## 坑 / Why

- **为什么把这些值集中在文件顶部？** 这是 Python 项目的"魔术数字反模式"避坑做法——任何"未来会调"的常数，先放顶部命名，**别让 `0.5` 这种数字埋在 200 行外的 if 里**。day5 调召回质量时，你只会改这一行，而不是搜遍代码。
- **`EMBED_DIMS=1024` 是个"将来会用上"的占位**。当前自建 SQLite 不需要预声明维度（BLOB 想存几维存几维），但 week4 切到 Chroma 时，`create_collection(dims=1024)` 必须传准。**提前命名好，迁移时一行 import 就够**。
- **`SCORE_THRESHOLD = 0.5` 这个值的"反直觉"是 day5 的核心实验**：bge-m3 中文 cosine 基线偏高（0.4-0.55），所以 0.5 太松。写完 `retrieve_memory` 后，真实跑一次，**记录每条召回的 score 分布**，再调这个值——这就是 CLAUDE.md "所有数字必须真实"铁律的最小落地：简历里能写"通过观察 30 条 query 的 score 分布，把阈值从 0.5 调到 0.65，准确率从 X 提到 Y"。**这就是 RAG 调优面经的金矿**。

## 相对路径 vs 绝对路径

`DB_PATH = "./memories.sqlite"`（相对路径）的 trade-off：

| 选择 | 优 | 劣 |
|------|-----|-----|
| 相对路径 | 可移植性好（项目 clone 到别处也能跑） | 必须在固定目录跑（`cd week2/` 然后 `uv run python day5_memory.py`），否则 sqlite 会乱建在不同目录 |
| 绝对路径 | 无歧义，在哪跑都对同一个文件 | 项目 clone 走就废了 |

day5 学习阶段，**相对路径足够**，只要记得永远在 `week2/` 目录跑。

## 关联

- [embedding-vs-llm-and-rag.md](./embedding-vs-llm-and-rag.md) — 为什么 EMBED_MODEL 不能用 deepseek 替代
- [bge-m3-model-card.md](./bge-m3-model-card.md) — EMBED_DIMS=1024 的来源
- [long-term-memory-design.md](./long-term-memory-design.md) — SCORE_THRESHOLD 的调优实验背景

---

来源：week2/day5_workspace/0510_2/1712.md
落盘日期：2026-05-10
