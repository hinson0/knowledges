# 阶段 0：心智模型校准 — 第 1 周逐日 Checklist

> 总时长：28h（7 天 × 4h）
> 起始日期：2026-04-29（明天）
> 目标：建立 LLM / Agent 工程师视角，能用一句话讲清 Agent / Workflow / Chain 的差异，并产出第一个可跑的最小 Agent。

---

## 通用约定

- **学习目录**：`~/LangGraph/learning/stage-0/` （建议建一个，每天的代码/笔记进去）
- **每日笔记**：`~/knowledges/ai-agent/daily/2026-04-29.md` 这种命名，记录"学到了什么 + 卡在哪"
- **每天 4h 拆分**：
  - 段 1（60 min）输入：看视频/读论文
  - 段 2（90 min）动手：跟做/敲代码
  - 段 3（60 min）输入或动手（继续）
  - 段 4（30 min）复盘：写当日笔记、自测、勾选 checklist

---

## Day 1（周一）：Transformer 直觉

**今天的目标**：知道 token、embedding、attention 在做什么；不需要会推导，但要能画出数据流图。

### 任务
- [ ] **(60 min)** 3Blue1Brown Ch.5 — "Transformers, the tech behind LLMs"
      https://www.youtube.com/watch?v=wjZofJX0v4M (27 min)
- [ ] **(60 min)** 3Blue1Brown Ch.6 — "Attention in transformers, visually explained"
      https://www.youtube.com/watch?v=eMlx5fFNoYc (26 min)
- [ ] **(60 min)** 3Blue1Brown Ch.7 — "How might LLMs store facts"
      https://www.youtube.com/watch?v=9-Jl0dxWQs8 (22 min)
- [ ] **(60 min)** 动手实验：用 `tiktoken` 把一段中文 + 英文 + 代码分别 tokenize，观察 token 数量差异
  ```python
  import tiktoken
  enc = tiktoken.encoding_for_model("gpt-4")
  # 试试不同输入：英文短句、中文长句、Python 代码
  ```

### 产出物
- [ ] `~/knowledges/ai-agent/daily/2026-04-29.md`：用自己的话画一张 "prompt → token → embedding → attention → next token" 的数据流图（手画拍照贴进去也行）

### 自测（合上视频回答）
- [ ] 为什么中文比英文消耗更多 token？
- [ ] Attention 的 Q、K、V 各自代表什么直觉？
- [ ] context window 是 200k 是指什么的 200k？

---

## Day 2（周二）：Karpathy "Let's build GPT"

**今天的目标**：从代码层理解 GPT，不要求训练成功，只要看懂 forward 是怎么算的。

### 任务
- [ ] **(120 min)** 看 Karpathy "Let's build GPT: from scratch, in code, spelled out"（前半段，0~1h 视频内容）
- [ ] **(90 min)** 跟做：把视频里的 bigram 模型 + self-attention 块敲一遍（不用追求训练效果，跑通即可）
- [ ] **(30 min)** 速看后半段（不跟做），重点理解 multi-head 与 layer norm 在哪

### 产出物
- [ ] `~/LangGraph/learning/stage-0/day2_gpt_from_scratch.py`：能 `python day2_gpt_from_scratch.py` 跑起来不报错

### 自测
- [ ] 为什么需要 causal mask？去掉会怎样？
- [ ] 你写的代码里，`B, T, C` 三个维度分别是什么？

> 💡 时间不够就跳过 multi-head 部分，single-head 跑通比 multi-head 卡死有价值。

---

## Day 3（周三）：Anthropic Prompt Engineering 课（上半）

**今天的目标**：摆脱"凭感觉写 prompt"，学会工程化的 prompt 结构。

### 任务
- [ ] **(60 min)** Anthropic Interactive Prompt Engineering Tutorial — Lesson 1-3（基础结构、role、direct vs indirect）
- [ ] **(60 min)** Lesson 4-5（examples / few-shot, avoiding hallucinations）
- [ ] **(90 min)** 动手：拿你最近写过的某个 prompt（公司业务的或者自己的），按学到的结构重写一版，用 Claude API 对比效果
- [ ] **(30 min)** 笔记：记录改写前后的 token 数和效果差异

### 产出物
- [ ] `~/LangGraph/learning/stage-0/day3_prompt_rewrite.py`：包含改写前后两个 prompt + 调用代码 + 输出对比

### 自测
- [ ] 什么时候用 system prompt，什么时候用 user prompt 里的指令？
- [ ] `<example>` 这种 XML tag 为什么对 Claude 特别有效？

---

## Day 4（周四）：Anthropic Prompt Engineering 课（下半）

**今天的目标**：掌握 chain-of-thought、tool use 风格的 prompt、复杂任务拆解。

### 任务
- [ ] **(60 min)** Lesson 6-7（CoT, structured output）
- [ ] **(60 min)** Lesson 8-9（complex prompts, prompt chaining）
- [ ] **(90 min)** 实战：用 prompt chaining 解决一个具体问题（推荐：给定一段中文长文，先抽要点 → 再翻译要点 → 再生成英文摘要）
- [ ] **(30 min)** 总结：写一份"我的 Prompt 工程 checklist"，5-10 条，存到 `~/knowledges/ai-agent/prompt-engineering-checklist.md`

### 产出物
- [ ] `~/LangGraph/learning/stage-0/day4_prompt_chain.py`
- [ ] `~/knowledges/ai-agent/prompt-engineering-checklist.md`（你自己的精炼版）

### 自测
- [ ] CoT 在哪些场景**反而**会让结果变差？
- [ ] 让模型输出 JSON 时，最稳的 3 种做法是什么？

---

## Day 5（周五）：ReAct + Reflexion 论文

**今天的目标**：理解 Agent 圈最核心的两个范式 — "推理-行动循环"和"自我反思"。

### 任务
- [ ] **(90 min)** 读 ReAct 论文（"ReAct: Synergizing Reasoning and Acting in Language Models"）
  - 重点：Figure 1（Reasoning only / Acting only / ReAct 三者对比）
  - 重点：HotpotQA 与 ALFWorld 实验设定
- [ ] **(30 min)** 找一篇中文解读对照看，确认理解无偏差
- [ ] **(90 min)** 读 Reflexion 论文（"Reflexion: Language Agents with Verbal Reinforcement Learning"）
  - 重点：self-reflection 是怎么 prompt 实现的（不是真正的 RL）
- [ ] **(30 min)** 笔记：用伪代码把 ReAct 循环和 Reflexion 循环各写一遍

### 产出物
- [ ] `~/knowledges/ai-agent/papers/react.md`：含一句话总结 + 伪代码 + 一个你能想到的应用场景
- [ ] `~/knowledges/ai-agent/papers/reflexion.md`：同上

### 自测
- [ ] ReAct 中 Thought / Action / Observation 三种事件分别由谁产生？
- [ ] Reflexion 的 "memory" 跟你理解的"记忆"有什么不同？

---

## Day 6（周六）：Toolformer + Building Effective Agents

**今天的目标**：理解工具使用的训练视角（Toolformer），以及 Anthropic 官方推荐的工程范式（Building Effective Agents 是路线图级别的文章，必读 3 遍）。

### 任务
- [ ] **(90 min)** 读 Toolformer 论文（"Toolformer: Language Models Can Teach Themselves to Use Tools"）
  - 重点：self-supervised 数据生成思路（这是和 ReAct 完全不同的路径）
- [ ] **(60 min)** **第 1 遍**读 Anthropic "Building Effective Agents"（粗读，建立全貌）
  - https://www.anthropic.com/research/building-effective-agents
- [ ] **(60 min)** **第 2 遍**精读，重点划出：
  - "When (and when not) to use agents"
  - 5 种 workflow 模式（prompt chaining / routing / parallelization / orchestrator-workers / evaluator-optimizer）
  - Agent 与 Workflow 的区别
- [ ] **(30 min)** **第 3 遍**速读，做一张脑图

### 产出物
- [ ] `~/knowledges/ai-agent/papers/toolformer.md`
- [ ] `~/knowledges/ai-agent/anthropic-building-effective-agents.md`：你的精读笔记 + 脑图（可以是 mermaid 文本）

### 自测（合上文章回答）
- [ ] 5 种 workflow 模式各自适合什么场景？举一个你熟悉业务的例子。
- [ ] Anthropic 的核心观点："何时**不应该**用 Agent"是什么？

---

## Day 7（周日）：手写最小 Agent — 整周收官

**今天的目标**：不用任何框架，纯 `anthropic` SDK + while 循环，写一个能调用工具的 Agent。这是整个学习路径的"第一个真东西"。

### 任务
- [ ] **(30 min)** 申请/确认 Anthropic API key，配置环境变量 `ANTHROPIC_API_KEY`
- [ ] **(30 min)** 读 Anthropic Tool Use 文档：https://docs.anthropic.com/en/docs/build-with-claude/tool-use
- [ ] **(150 min)** 编码 — 实现 `~/LangGraph/learning/stage-0/day7_minimal_agent.py`，要求：
  - [ ] 使用 `claude-sonnet-4-6` 或 `claude-opus-4-7`
  - [ ] 注册 2 个工具：`read_file(path)` 和 `list_dir(path)`
  - [ ] 主循环：while 循环直到模型不再返回 tool_use
  - [ ] 把 user 问题、assistant 回复、tool_use、tool_result 全部 append 到 `messages` 历史里
  - [ ] 命令行交互：用户输入问题 → Agent 回答 → 继续输入
  - [ ] 测试 case："这个目录里都有什么？" → "读一下其中的 X 文件给我总结"
- [ ] **(30 min)** 收官笔记：在 `~/knowledges/ai-agent/daily/2026-05-05.md` 总结整周收获 + 下周（阶段 1）目标

### 产出物（本周最重要的交付）
- [ ] `~/LangGraph/learning/stage-0/day7_minimal_agent.py`：能跑、能多轮、能用工具
- [ ] 录一个 30 秒终端 demo（自己看的，不用发出去）

### 自测（这是阶段 0 的"出师题"）
- [ ] 用一句话说清 Agent / Workflow / Chain 的区别
- [ ] 你的 Agent 在什么情况下会无限循环？怎么防御？
- [ ] 如果同一个工具被调用 10 次返回相同结果，模型为什么还是会再调？怎么避免？

---

## 整周收尾：阶段 0 通过的标志

完成以下三件事，就可以进入阶段 1：

1. ✅ Day 7 的 minimal_agent.py 能跑起来并完成至少一个多步任务
2. ✅ `~/knowledges/ai-agent/` 下至少 6 篇笔记（每天一篇 + checklist）
3. ✅ 能口头讲清楚：Token、Attention、ReAct、Workflow vs Agent 这 4 个概念

---

## 时间表速览（贴在桌前）

| 日期 | 主题 | 关键产出 |
|------|------|---------|
| 4-29 周一 | Transformer 直觉 | tiktoken 实验 + 数据流图 |
| 4-30 周二 | Karpathy GPT | bigram + attention 跑通 |
| 5-01 周三 | Prompt 工程 上 | 改写一个旧 prompt |
| 5-02 周四 | Prompt 工程 下 | prompt chain 实战 + 个人 checklist |
| 5-03 周五 | ReAct + Reflexion | 2 篇论文笔记 + 伪代码 |
| 5-04 周六 | Toolformer + Anthropic 路线图 | 读 3 遍 + 脑图 |
| 5-05 周日 | 最小 Agent | 可跑的多轮工具调用 Agent |

---

## 卡壳应对

- **如果某天没完成**：不要补，跳过未完成项继续下一天，周日有 buffer。
- **如果觉得太简单**：用英文写当日笔记，并多读 1 篇相关 blog（推荐 Simon Willison）。
- **如果觉得太难**：跳过 Karpathy 视频中的训练部分，只看到 self-attention 实现就够了；论文先读摘要 + 图就行。
