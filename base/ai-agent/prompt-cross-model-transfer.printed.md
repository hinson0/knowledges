# Prompt 工程的跨模型迁移性边界 —— Day 5 金矿

> 同一个 strong prompt,在大模型上锁死最短路径(σ=0),在小模型上变成"鼓励反复迭代修复"。
> 真实数据:30 次跑实验(2 模型 × 3 prompt 强度 × 5 次)证明 **prompt 强度有迁移性,但有边界——边界是模型能力**。
> 这是 Cursor / Aider 必须为不同模型分别做适配的根本原因。

## 1. 实验设计

任务:在 12 函数 `math_utils.py` 中新增 `fibonacci(n)` + 写 `test_fib.py` 验证 + 跑测试。

| 维度 | 配置 |
|---|---|
| 模型 1 | `deepseek-v4-flash`(DeepSeek 自家) |
| 模型 2 | `Qwen/Qwen3-8B`(Silicon Flow,8B 参数) |
| Prompt 1 | Weak("你是一个能够使用工具操作文件系统的智能助手...") |
| Prompt 2 | Strong V1(5 条正向 SOP 约束) |
| Prompt 3 | Strong V2(V1 + 第 6 条并行编排) |
| 重复次数 | 每组 5 次 |
| 总实验数 | 2 × 3 × 5 = **30 次跑**,JSONL 落盘 |
| 评估维度 | 3 个 trap × 5 子检查 + tool_calls / iterations / parallelism_ratio |

## 2. 顶层数据汇总

### DeepSeek V4 Flash(2026-05-03 ~ 05-05)

| 指标 | Weak | Strong V1 | Strong V2 |
|---|---|---|---|
| all_passed | 5/5 | 5/5 | 5/5 |
| tool_calls 平均 | 5.4 | 4.0 | **4.0** |
| tool_calls σ | 0.55 | 0.00 | **0.00** |
| iterations σ | 0.84 | 0.55 | **0.00** |
| 序列指纹种数 | 4 | 1 | **1** |
| terminated 全 completed | ✅ | ✅ | ✅ |

**结论**:DeepSeek V4 上,strong V2 实现完全确定性(σ=0,1 种序列)。

### Qwen3-8B(2026-05-06)

| 指标 | Weak | Strong V1 | **Strong V2** |
|---|---|---|---|
| trap_A_read_before_write | 2/5 | 5/5 | **5/5** ⭐ |
| trap_B_all_kept | 1/5 | 3/5 | **2/5** ⚠ |
| trap_B_import_kept | 2/5 | 3/5 | **2/5** ⚠ |
| trap_B_has_fibonacci | 4/5 | 2/5 | **5/5** |
| trap_C_verified | 3/5 | 3/5 | **5/5** |
| **all_passed** | **0/5** | **0/5** | **2/5** ⭐ |
| tool_calls 平均 | 2.4 | 3.4 | **7.4** 🔥 |
| tool_calls σ | 0.89 | 2.19 | **3.97** 🔥 |
| iterations 平均 | 2.6 | 2.8 | **5.4** |
| iterations σ | 0.89 | 0.84 | **3.13** |
| 序列指纹种数 | 4 | 3 | **5**(更发散!) |
| terminated_reason | 5 completed | 5 completed | **4 completed,1 max_iter** |
| parallelism_ratio | 1.80 | 1.73 | 2.14 |

**结论**:Qwen3-8B 上,strong V2 让 all_passed 从 0/5 → 2/5,但 tool_calls σ 反而从 0.89 升到 3.97,序列指纹种类从 4 变 5(**更发散**)。

## 3. 跨模型对比 —— 同 prompt,两种命运

| 指标 | DeepSeek V4 + V2 | Qwen3-8B + V2 | 差距 |
|---|---|---|---|
| all_passed | 5/5 | 2/5 | **-3 次 (-60%)** |
| tool_calls 平均 | 4.0 | 7.4 | **+3.4 次 (+85%)** |
| tool_calls σ | 0.00 | 3.97 | **+3.97 (完全失控)** |
| iterations σ | 0.00 | 3.13 | **+3.13** |
| 序列指纹种数 | 1 | 5 | **+4 种** |
| 触发护栏 | 0 次 | 1 次 max_iter | 出现 |

**同一个 prompt,在两个模型上效果完全相反**。

## 4. 三个反直觉发现

### 发现 1:trap_A 在 V2 下完美收敛(5/5)—— prompt **能**锁住"单一行为"

无论是 DeepSeek V4 还是 Qwen3-8B,V2 prompt 的"必须先 read 再 write"规则都被听话执行。

**机制**:这是 **单事件决策**(decide once at the start)——LLM 启动时看到"必须先 read"就执行。**单事件决策是 prompt 最容易锁住的**。

### 发现 2:trap_B 完美锁不住 —— prompt **锁不住**"持续注意力"

DeepSeek V4 在 V2 下 trap_B 命中 5/5,Qwen3-8B 在 V2 下只有 2/5。

**机制**:写 write_file 时把 12 个函数全保留 = 需要**长 context attention**。Qwen3-8B 的 attention 不够,就算 prompt 强调"原内容一个不能丢",它在生成 write_file 的 content 字符串时**仍然漏抄某些函数**。

**这不是 prompt 问题,是模型能力问题**。

> 真实数据:Qwen3-8B + V2 五次跑共漏抄 30 函数次(平均每次跑漏 6 个原函数)。最常被漏的是 `multiply / divide / is_even / is_prime` 这些"中间位置函数"——说明模型 attention 在长输出时**头尾记得清,中间易丢**。

### 发现 3:strong prompt 让小模型**自我纠错**而不是"锁死路径"

DeepSeek V4 + V2 = **一次到位,4 步终止**。
Qwen3-8B + V2 = **首次翻车 → 测试失败 → 反复修 → 最终(可能)通过**。

**Run 3 的 14 步迭代是教科书案例**:

```
Run 3 序列(成功 case):
[
  ['read_file', 'write_file', 'write_file', 'run_shell'],   ← 第 1 轮 4 个并行(听话)
  ['write_file', 'run_shell'],                              ← 第 2 轮 测试失败,自我修
  'write_file', 'run_shell',                                 ← 第 3-4 轮
  'write_file', 'run_shell',                                 ← 第 5-6 轮
  'write_file', 'run_shell',                                 ← 第 7-8 轮
  'write_file', 'run_shell',                                 ← 第 9-10 轮
  'write_file', 'run_shell'                                  ← 第 11-12 轮 终于通过
]
共 14 个工具调用,passed=True
```

LLM 听了"先 read"和"并行写",但首次写丢函数 → 测试失败 → **疯狂迭代写+跑测试 5 次** → 最终通过。

**这是另一种 SOP**——**"听话 + 能力不够 = 用迭代次数换正确性"**。

## 5. 核心洞察

### 5.1 Prompt 工程的能力边界 = 模型能力

Prompt 工程不是万能。**强 prompt 的极限被模型能力封顶**:

```
理想效果:LLM 知道该做 → LLM 做对 → 一次到位
小模型现实:LLM 知道该做 → LLM 试 → 错了再改 → 多次到位(或 max_iter)
```

### 5.2 单事件决策 vs 持续注意力

| 类型 | 例子 | prompt 锁不锁得住 |
|---|---|---|
| **单事件决策** | "先 read 再 write" / "环境已就绪不要探" | ✅ 容易锁(决定一次) |
| **持续注意力** | "write_file 时保留所有 12 个函数" | ❌ 难锁(需要每个 token 都保留) |
| **多步推理** | "测试失败时分析 stderr 是路径错还是参数错" | ⚠ 看模型 |

**这是 prompt 设计的核心心智模型**——把约束设计成"开场决定一次的事",最容易锁住。

### 5.3 σ 在小模型上变成"骰子"而不是"开关"

DeepSeek V4 上 σ 是"行为开关":strong prompt 一开,σ → 0。
Qwen3-8B 上 σ 是"骰子摇晃幅度":即使 strong prompt,LLM 每次"擦边"通过的尝试次数都不一样。

```
σ 含义随模型能力变化:
  大模型: σ → 0 = "完全收敛"
  小模型: σ 大 = "每次摇骰子的幅度"(每次试的次数不同)
```

### 5.4 这是 Cursor / Aider 必须分模型适配的根本原因

生产 Coding Agent 不能"一套 prompt 走天下"。同一个 system prompt:
- GPT-4 / Claude 4.7 上可能 σ=0 一次到位
- Qwen3-8B / Llama-8B 上变成"反复迭代修复"
- 还要给小模型加 **reflection / retry 兜底**(Week 6 任务)

## 6. 工程意义

### 6.1 评估系统必须**矩阵评估**(模型 × prompt)

不能只评估"prompt 在某一个模型上的效果"——必须做笛卡尔积:

```
| Prompt \ Model | gpt-4 | claude-4.7 | deepseek-v4 | qwen3-8b | qwen3-32b |
| weak           |  ?    |    ?       |     ?       |    ?     |    ?      |
| strong V1      |  ?    |    ?       |     ?       |    ?     |    ?      |
| strong V2      |  ?    |    ?       |     ?       |    ?     |    ?      |
```

每个格子是一组 5+ 次跑的统计。**这才是生产级 Eval Harness**(Week 7 任务)。

### 6.2 小模型场景下 prompt 设计要点变化

| 设计要点 | 大模型 | 小模型 |
|---|---|---|
| 防"过度并行" | 重要(避免浪费) | **不重要**(小模型自己很少并行) |
| 防"边界值额外验证" | 重要 | **不重要**(小模型很少自发验证) |
| **强调"长上下文保留"** | 中等(有时漏) | **核心**(频繁漏) |
| **加 reflection / retry 兜底** | 锦上添花 | **必需**(单次成功率低) |

### 6.3 简历句(真实数字)

> 在 Qwen/Qwen3-8B 跨模型迁移测试中:strong prompt V2 把 `trap_A_read_before_write` 命中率从 2/5 提升到 5/5,`trap_C_verified` 从 3/5 提升到 5/5,`all_passed` 从 0/5 提升到 2/5,但代价是 `tool_calls` 从 2.4 升至 7.4 (+5 次,+208%),`σ` 从 0.89 升至 3.97 (+3.08,+346%)。
>
> **证明 prompt 工程的迁移性边界:强 prompt 在大模型上锁死最短路径(σ=0),在小模型上转化为"鼓励反复迭代修复"——LLM 听话但能力不够时,以工具调用次数换最终正确性**。
>
> 通过 30 次跑实验(2 模型 × 3 prompt 强度 × 5 次)+ 21 字段 JSONL 落盘,建立 prompt 设计在不同模型上的差异化优化曲线,为生产部署的模型适配策略提供数据支撑。

## 7. 残余问题(Week 6/7 续)

- **Qwen3-14B / Qwen3-32B 数据缺失**:不知道 σ 何时随模型规模回到 0。中间规模的"过渡曲线"是 Week 7 评估系统的关键数据。
- **Run 3 的 14 步迭代成功**:这种"暴力迭代"成本远高于 V2 在 DeepSeek 上的 4 步,**每次大概多花 5-10x token**。Week 5 Context Caching 能不能压回来?
- **trap_B 的"模型能力问题"无解**:除非给 small 模型加 chunk-by-chunk 编辑工具(Week 6 apply_patch),否则 prompt 怎么写都无法保证小模型在长输出时不漏抄。

## 8. 与后续 Week 的连接

- **Week 5 工程化**:Context Caching + 重试 + 模型降级(从 v4-pro 降到 v4-flash 的策略)。今天的发现指明了"小模型必须配重试"。
- **Week 6 Multi-Agent + apply_patch**:apply_patch(unified diff)从根上消除 trap_B 翻车——LLM 不用再生成完整文件,只生成 diff,模型 attention 不够也不会丢函数。这是给小模型的工程救命方案。
- **Week 7 Eval Harness**:30 次跑只是开始。Week 7 要扩展成 50 例 × 多模型 × 多 prompt 的笛卡尔积评估,本文的"模型 × prompt"矩阵就是评估面板的雏形。

## 9. 与 `system-prompt-sop.md` / `parallel-function-calling.md` 的关系

| 文档 | 重点 | 模型范围 |
|---|---|---|
| `system-prompt-sop.md` | 单模型 prompt 5 要素设计 | DeepSeek V4 单模型 |
| `parallel-function-calling.md` | Parallel FC 节省 26.7% token | DeepSeek V4 单模型 |
| **本文** | **跨模型迁移性边界** | **DeepSeek V4 + Qwen3-8B 对比** |

三篇文档构成 Day 4-5 的完整知识闭环——从"prompt 怎么写"到"prompt 在不同模型上效果不同"。

## 10. 关键认知一句话总结

> **Prompt 工程是放大器,不是创造者**。
> 它把模型能力放大到极限,但永远无法超越模型能力本身。
> Strong prompt 在 GPT-4 上是 σ=0 的开关,在 Qwen3-8B 上是 σ=3.97 的迭代燃料。
