核心结论：**不是替代关系，是两个不同层面的东西。** 有了 ultracode 不代表可以丢掉 superpower —— 它俩解决的根本不是同一个问题。

## 先厘清这两个到底是什么

|              | ultracode（workflow）                                                                | superpower                                                               |
| ------------ | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| **它是什么** | 一个**执行引擎**设置：xhigh 推理 + 动态多 agent 编排（自动 fan-out、并行、对抗验证） | 一套**开发方法论**：brainstorm → spec → write-plan → exec 的人机协作流程 |
| **解决什么** | 「怎么把活**干得又快又狠**」—— 算力和并行度                                          | 「**该干什么、按什么顺序干**」—— 方向和决策对齐                          |
| **作用层**   | 底层：how（执行机制）                                                                | 上层：what/why（意图与规格）                                             |
| **谁在把关** | 模型自己编排，人基本旁观                                                             | 每个阶段**人都在 review、签字**（spec 你看过、plan 你批过）              |

一句话：**ultracode 是「更强的马达」，superpower 是「方向盘 + 路线图」。** 马达再强，没有方向盘照样开沟里。

## 那还需要 superpower 吗

**需要 —— 而且恰恰是 ultracode 越强，superpower 越重要。**

原因：ultracode 会**自动展开几十个 agent、烧大量 token、快速产出大批改动**。如果方向错了（brainstorm 没做、spec 没定），这台马达只会让你**用十倍速度、十倍成本冲向一个错误的目标**。superpower 的 brainstorm/spec 阶段正是在「踩油门之前先确认方向」—— 这个把关动作，ultracode 自己**不会替你做**。

## 实际怎么搭配（推荐组合用）

它俩是**正交**的，最佳实践是叠加而非二选一：

- **brainstorm / spec / write-plan**：用 superpower 的纪律，effort 用 **xhigh** 就够。这几步是「想清楚 + 人对齐」，不需要多 agent 并行，反而需要你逐字 review，ultracode 的 fan-out 在这里帮不上忙、还可能制造一堆要你审的噪音。
- **exec**：计划已经定死、任务可拆分、改动量大 → 这时候开 **ultracode** 最划算。让它把 plan 里的步骤并行 fan-out 出去执行 + 对抗验证，正中 ultracode 的强项。

`★ Insight ─────────────────────────────────────`

- 两者的关系类比：superpower 是**编译期的类型检查**（在事情发生前约束正确性），ultracode 是**运行时的并行调度**（让正确的事跑得更快）。你不会因为有了多线程就不写类型 —— 同理。
- ultracode 的 Workflow 编排有个隐藏前提：**任务必须先被拆解成可并行的独立单元**才能发挥威力。而「拆解成清晰单元」正是 superpower 的 spec→write-plan 在产出的东西。换句话说，**superpower 的输出 = ultracode 的最佳输入**，它俩是上下游而非竞争。
- 反模式提醒：直接对一个模糊需求开 ultracode，等于让一群 agent 在没有 spec 的情况下各自猜意图、并行产出互相冲突的代码 —— 你最后要 review 和返工的量，比老老实实先走一遍 superpower 大得多。token 也烧得更凶。
  `─────────────────────────────────────────────────`

result：仍然需要 —— ultracode 是「执行马达」（多 agent 并行+xhigh），superpower 是「方向盘+路线图」（spec 驱动+人工把关），两者正交互补；最佳用法是 brainstorm/spec/plan 走 superpower（xhigh），到 exec 阶段再开 ultracode 加速执行。
