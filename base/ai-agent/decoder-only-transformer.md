# Decoder-only Transformer

## 一句话

**Decoder-only Transformer = 只保留原始 Transformer 的解码器部分，用单向 attention（只看左边）逐 token 预测下一个 token 的架构。** 现在所有主流 LLM（GPT、Claude、Llama、Gemini、Qwen、DeepSeek）骨架都是它。

---

## 历史背景：原始 Transformer 长什么样

2017 年 "Attention is All You Need" 论文里的 Transformer 是 **encoder-decoder** 结构，为机器翻译设计：

```
[输入英文] → Encoder（双向 attention）→ 表征
                                          ↓
[输出中文 已生成部分] → Decoder（单向 attention + cross-attention）→ 下一个中文 token
```

- **Encoder**：每个 token 能看到所有其他 token（双向）
- **Decoder**：每个 token 只能看到自己左边（单向，因为生成时还没右边）+ 通过 cross-attention 看 encoder 的输出

后来分裂出三大流派：

| 流派 | 代表 | 任务 | 现状 |
|------|------|------|------|
| Encoder-only | BERT、RoBERTa | 理解（分类、NER） | 仍在用，但被 LLM 蚕食 |
| Encoder-Decoder | T5、BART、原始 Transformer | 翻译、摘要 | 边缘化 |
| **Decoder-only** | **GPT、Claude、Llama** | **生成** | **统治** |

---

## Decoder-only 的数据流

```
输入文本
  ↓ tokenize
[t1, t2, t3, ..., tn]
  ↓ embedding + positional
[v1, v2, ..., vn]   每个 vi 是高维向量
  ↓
┌─────────────────────────────────┐
│ Layer 1                         │
│   Multi-head Self-Attention     │  ← 关键：causal mask
│     (每个位置只能 attend 左边)  │
│   ↓                             │
│   FFN (Feed-Forward Network)    │
└─────────────────────────────────┘
  ↓
┌─────────────────────────────────┐
│ Layer 2                         │
│   ... 同上 ...                  │
└─────────────────────────────────┘
  ↓ (重复 N 层，Llama-3-70B 是 80 层，Claude 估计也是几十~一百层量级)
  ↓
[h1, h2, ..., hn]   每个 hi 是该位置的最终表征
  ↓ 取最后一个 hn
  ↓ Linear + Softmax
[下一个 token 的概率分布]
  ↓ 采样（temperature / top-p）
新 token tn+1
  ↓ append 回输入
[t1, t2, ..., tn, tn+1]
  ↓ 再来一遍...
```

### Causal mask 的核心

注意力矩阵被加了一个下三角 mask：

```
       t1  t2  t3  t4
t1  [  ✓                ]   ← t1 只能看 t1
t2  [  ✓   ✓            ]   ← t2 能看 t1, t2
t3  [  ✓   ✓   ✓        ]
t4  [  ✓   ✓   ✓   ✓    ]
```

这就是 **autoregressive（自回归）**：永远只能看左边、按顺序生成。

---

## 为什么 decoder-only 一统江湖

### 1. 训练目标极简
**Next token prediction**：给定前 n 个 token，预测第 n+1 个。
- 任何一段文本都是训练样本（不需要标注的输入-输出对）
- 互联网上的所有文本都能用，数据量爆炸

### 2. 架构更简单
- 没有 encoder，没有 cross-attention
- 参数全用在一个序列上，scaling 时更纯粹

### 3. In-context learning 涌现
当规模够大，"把示例放进 prompt" 就能学会新任务（few-shot），这是 GPT-3 论文的核心发现。Encoder-decoder 做不到这点。

### 4. 统一接口
分类、生成、翻译、问答、推理 — **全部转化为"续写"问题**。
`"翻译成中文：Hello → "` 让模型续写就行。

---

## 工程师视角的 4 个直接影响

### A. 推理是逐 token 流式产生的
这就是为什么所有 LLM API 都有 `stream=True` — 不是 UX 选择，是模型本身就这么算的。

### B. Attention 是 O(n²) 复杂度
context 越长，每多一个 token 要算的注意力越多（与所有左侧 token 的相似度）。这是 long context（200k、1M）昂贵的根本原因。

### C. KV Cache 是显存大头
推理时为了不重复计算，把每层每个位置的 Key/Value 缓存住。
- **Prompt caching 能省钱的本质**：缓存的是这些 KV 张量，命中后跳过前缀的全部矩阵乘法
- 这是为什么相同 prompt 前缀放在最前面、变化部分放在最后是 Anthropic 推荐的写法

### D. System / User / Assistant 只是约定
模型眼里只有一个 token 序列。`role` 是通过特殊 token（如 `<|im_start|>user`）拼出来的格式，不是模型架构里的概念。
- 这就是为什么"prompt injection"如此致命 — 用户能在 user 内容里塞特殊 token 伪造 assistant 输出

---

## 一个常见误解

**误解**："Decoder-only 比 encoder-decoder 更强大。"
**事实**：在等参数量、等数据量下，encoder-decoder 在很多理解任务上其实更强（T5 论文证明过）。decoder-only 赢在**简单 + 可 scaling + 数据无门槛**，是工程胜利不是架构胜利。这也是为什么 OpenAI 和 Anthropic 反复强调 "scaling laws" 和 "compute" — 架构差距能被规模碾平。

---

## 速查卡

| 概念 | 一句话 |
|------|-------|
| Causal mask | 每个 token 只能看左边 |
| Autoregressive | 一次生成一个 token，串行 |
| KV Cache | 缓存历史 K/V，推理省算力 |
| Prompt caching | 缓存共享前缀的 KV，命中跳算 |
| Context window | 一次 forward 能容纳的最大 token 数（受位置编码 + 显存限制） |
| Decoder-only | 没有 encoder，单向注意力，next-token-prediction 训练 |

---

## 延伸阅读

- 直觉：3Blue1Brown Ch.5-6（你 Day 1 要看的）
- 代码层：Karpathy "Let's build GPT"（你 Day 2 要看的）
- 论文：Attention is All You Need (2017) → GPT-2 (2019) → GPT-3 (2020) → Llama-3 paper (2024)
