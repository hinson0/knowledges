# BGE-M3 模型卡片

> 来源：week2/day5_workspace/0510_2/1728.md。北京智源研究院（BAAI）2024 年初开源的 embedding 模型，是中文社区最受欢迎的开源 embedding 模型之一，在 RAG 场景里基本是默认推荐之一。

## 名字的由来：M3 = 三个"多"

BGE-M3 的 "M3" 代表它三个核心特性，这也是它最大的卖点。

### 1. Multi-Linguality（多语言）

支持 **100+ 种语言**，包括中文、英文、日文、韩文等等，而且**跨语言检索**能力很强——可以用中文问题去检索英文文档，照样能命中相关内容。这一点对国内做多语言知识库的场景特别有用。

### 2. Multi-Functionality（多功能）

一个模型同时支持**三种检索方式**，这是它最独特的地方：

- **Dense Retrieval（稠密检索）** —— 传统 embedding 方式，输出一个稠密向量（1024 维），算余弦相似度
- **Sparse Retrieval（稀疏检索 / Lexical）** —— 类似 BM25，给每个 token 一个权重，擅长精确关键词匹配
- **Multi-Vector（多向量 / ColBERT 风格）** —— 每个 token 都输出一个向量，做细粒度匹配，精度最高但开销也大

实际用的时候可以**三种混合**（hybrid retrieval），效果通常比单用任何一种都好。

### 3. Multi-Granularity（多粒度）

输入长度从**短句到 8192 token 的长文档**都能处理。一般 embedding 模型只能吃 512 token，文档长了就得切块；BGE-M3 直接把上下文窗口拉到 8K，对长文档 RAG 很友好。

## 关键参数

| 项目 | 数值 |
|------|------|
| 基础模型 | XLM-RoBERTa-large |
| 参数量 | 约 568M |
| 向量维度（dense） | 1024 |
| 最大输入长度 | 8192 token |
| 支持语言 | 100+ |
| 开源协议 | MIT |

## 实际使用感受

**优点：**

- 中文效果在开源模型里第一梯队
- 长文本支持好，少切块的麻烦
- 三合一 hybrid retrieval，灵活
- 完全开源免费，可以本地部署

**缺点 / 注意事项：**

- 模型不算小（2GB+），CPU 推理慢，最好上 GPU
- 1024 维向量在向量数据库里占空间，比 OpenAI 的 `text-embedding-3-small`（1536 维但算法更省）的存储成本要考虑
- 中英文场景下，对比闭源 SOTA（如 `text-embedding-3-large`、Voyage-3）在某些细分任务上仍有差距

## 怎么用

### FlagEmbedding 库（官方）

```python
from FlagEmbedding import BGEM3FlagModel

model = BGEM3FlagModel('BAAI/bge-m3', use_fp16=True)

sentences = ["什么是BGE-M3?", "BGE-M3是一个嵌入模型"]

# 只要 dense 向量
embeddings = model.encode(sentences, return_dense=True)['dense_vecs']

# 三种全要
output = model.encode(
    sentences,
    return_dense=True,
    return_sparse=True,
    return_colbert_vecs=True
)
```

### 或者用 sentence-transformers / Ollama / LM Studio

```bash
# Ollama 本地跑
ollama pull bge-m3
```

主流框架 LangChain、LlamaIndex 都内置支持。

## 它在 RAG 流程里的位置

```text
原始文档 → 切块 → [BGE-M3 编码] → 向量库（Milvus/Qdrant/Weaviate 等）
                                          ↑
用户问题 → [BGE-M3 编码] ───────────────────┘
                                       检索 top-k → 喂给 LLM
```

## 有没有更新版

BGE 系列还在更新，可以关注：

- **BGE-M3** —— 长文本 + 多语言，通用首选
- **BGE-reranker-v2-m3** —— 配套的重排序模型，召回后用它二次排序提升精度
- **BGE-EN-ICL** / **BGE-multilingual-gemma2** —— 后续的更大规模版本

实际生产里很常见的搭配是：**BGE-M3 做召回 + BGE-reranker-v2-m3 做重排**，效果比单用召回好不少，这又是一个典型的精度 vs 延迟的 trade-off。

## 关联

- [embedding-vs-llm-and-rag.md](./embedding-vs-llm-and-rag.md) — embedding 概念基础
- [vector-cosine-geometry.md](./vector-cosine-geometry.md) — 1024 维向量的余弦原理
- [memory-config-constants.md](./memory-config-constants.md) — `EMBED_MODEL=BAAI/bge-m3` 的常量定义

---

来源：week2/day5_workspace/0510_2/1728.md
落盘日期：2026-05-10
