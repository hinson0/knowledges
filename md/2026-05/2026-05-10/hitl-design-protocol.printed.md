# Day 4 · HITL 设计协议(从 Why 到代码落地的完整轨迹)

> 来源:week2/0510 的 `1219.md` + `2121.md` + `2203.md` + `2210.md` + `2213.md` + `0901.md`。
> 这是 Day 4 HITL 工程化设计的**完整推理链**:为什么做 → 三条技术路线 → 设计三问 → 决策收窄 → 代码翻译 → 一致性闭环。

---

## 1. Why(先讲清楚为什么做)

到 Day 3 你已经会"机器自己跑完一长串 tool_calls"。但**生产场景里有两类操作不能让 LLM 自己拍板**:

| 类别 | 例子 | 为什么不能放 |
|---|---|---|
| 高破坏性 | `run_shell("rm -rf ...")` / `apply_patch` / 发 PR | 错一次很难回滚,代价远高于"问一句" |
| 高歧义性 | "改下登录逻辑" | LLM 可能误解需求,先让人 review plan 再 execute |

**HITL = checkpointer + interrupt 的乘法**:

- checkpoint 让"暂停后能重启"成为可能
- interrupt 让"在精确位置暂停"成为可能

**没有 checkpointer 的 interrupt 是耍流氓**(暂停后状态丢了),**没有 interrupt 的 checkpointer 是哑的**(只能机器决定停在哪)。

---

## 2. 技术路线对比(LangGraph 1.x 三条路)

| 路线 | 写法 | trade-off |
|---|---|---|
| **A · `interrupt()` 函数(LangGraph 1.x 主推)** | node 内 `value = interrupt({"question": ..., "preview": ...})`;client 收到 `GraphInterrupt` → 拿用户输入 → `app.invoke(Command(resume=v), config)` | ✅ 携 payload(向用户出示 plan / diff)<br>✅ 续跑能注入用户输入<br>⚠ 须在 checkpointer 之上才有意义 |
| **B · `interrupt_before=[node]` 静态中断** | `app = builder.compile(checkpointer=..., interrupt_before=["execute"])`;续跑 `app.invoke(None, config)` | ✅ 配置一行<br>❌ 不带 payload,客户端不知道在等什么<br>❌ 改中断点要重新 compile |
| **C · 自己造个"等待节点" + END** | should_continue 路由到 `wait_human` → END | ❌ 等于自己复刻一遍 LangGraph 已有的功能,违反"用框架"的初心 |

### 推荐打法

**A 为主,Day 4 故意先踩一遍 B 的坑再切 A** — 这样能体感到为什么 1.x 把 B 降级成"老 API、不推荐"。

具体步骤:

1. **30 分钟 · B 路线 baseline**:在 `should_continue` 之后、`tools` 节点之前加 `interrupt_before=["tools"]`,跑一次,观察:
   - 中断时 stream 抛什么?
   - `app.get_state(config).next` 是什么?
   - 续跑时 `app.invoke(None, config)` vs `app.invoke({"messages": [...]}, config)` 行为差异
2. **核心 90 分钟 · A 路线**:写一个 `human_review` 节点,内部 `decision = interrupt({"plan": ...})`,根据 decision 路由到 `tools` 或 `END`。client 端写一个 CLI 循环,捕 `GraphInterrupt`,`input()` 拿决定,`Command(resume=decision)` 续跑。
3. **故意踩坑 · 中断点设错位置**:故意把 `interrupt_before` 放在 `agent` 之前而不是 `tools` 之前 — 你会发现"确认完无法继续",因为已经停在 LLM 决策**之前**,resume 后 LLM 重新决策可能又给出新 tool_calls,陷入"批准一次又冒一次"的死循环。这个坑撞一次比看 10 篇博客都深。

### ★ Insight(路线选择)

- **"checkpoint 是 HITL 的地基"再次验证**:interrupt 抛 `GraphInterrupt` 时,LangGraph 做的不是"挂起协程",而是**把当前状态写入 checkpoint 然后退出 Python 调用**。下次 invoke 是**全新进程**从 checkpoint reload。所以 Day 3 的 SqliteSaver 跨进程实验是 Day 4 的前提 — 你已经把地基打好了。
- **A vs B 的本质差异是"信息流方向"**:B 是单向的 — 框架告诉你"停在这了,你要不要继续",但客户端不知道在等什么。A 是双向的 — node 主动 push 一个 payload(plan / diff / 风险评估),客户端基于 payload 决策,再 push 回去。这跟 RPC 的 "fire-and-forget" 与 "request-response" 是同一组对偶。
- **Day 4 真正考的不是 API,而是"中断点选位"**:中断点应该放在**副作用发生之前 + LLM 决策已完成之后**那个夹缝里。放早了(LLM 决策前)→ resume 后又生成新的 tool_calls,审批失效;放晚了(副作用已落)→ 审批等于事后追认。这个设计判断比代码本身重要。

---

## 3. 设计三问(协议设计的核心)

这三问不是抽象哲学,每个都有**外端代码的具体影响**。

### Q1 · payload 装什么?

**这是 `interrupt(payload)` 那个 dict**。LangGraph 把它写进 checkpoint,你的 client 通过 `chunk["__interrupt__"][0].value` 取出来。**外端 UI 看到什么 = payload 里有什么**,一一对应。

| 档位 | payload 写法 | 外端能渲染的内容 |
|---|---|---|
| 极简 | `{"tool": "read_file", "args": {...}}` | 只一行:"agent 想 read_file(/x.py),y/n?" |
| 标准 | `{"stage": "pre_tool", "preview": [{name, args}, ...]}` | 一次审批多个 tool_call(LLM 一次返回 N 个时) |
| 全息 | 上面 + `"reasoning": "..."` + `"risk": "high"` | UI 能展示"agent 为什么这么干" + 风险标签 |

**判断锚点**:你的外端是 CLI 还是 Web UI?CLI 信息越少越好(标准档刚好);Web UI 可以塞 reasoning 因为有空间。

### Q2 · decision schema 长啥样?

**这是外端通过 `Command(resume=decision)` 传回去的东西**。你 `interrupt()` 调用的返回值 = 这个 `decision`。节点函数后半段就用它判分支。**这是节点和外端之间唯一的契约**,定义不一致就崩。

| 档位 | decision 形态 | 外端要做什么 |
|---|---|---|
| 极简 | 字符串 `"yes"` / `"no"` | 只需一个二选一 prompt |
| 标准 | `{"action": "approve"}` / `{"action": "reject", "reason": "..."}` | 拒绝时让用户输理由 |
| 全息 | 加 `{"action": "edit", "patched_args": {...}}` | 让用户改 tool_call 参数再放行(Cursor 的 "Apply with edits" 模式) |

**判断锚点**:你的外端给"人"开几个按钮?二选一够用就极简,要支持改参数就要全息档。

### Q3 · reject 怎么回流?

你拒绝了,但 graph 不能直接 END —— LLM 应该重新想一个方案。**怎么让 LLM "知道"自己刚才被拒**?

| 方案 | 节点返回值 | LLM 怎么"看见" reject |
|---|---|---|
| **A · 消息总线** | `{"messages": [HumanMessage("[人工拒绝] reason")]}` | add_messages reducer append 后,下一轮 prompt 里自然出现这条对话,LLM 像"看到用户回复"一样吸收 |
| **B · 控制总线** | `{"rejected": True}`(改 AgentState 加字段) | LLM 默认看不到 state 字段 —— 你必须在 call_llm 里手动把 `if state["rejected"]: prompt += "..."` |

**对外端的影响**:几乎为零 —— 这俩方案 client 端代码完全一样,差异全在节点内部。但 `post_review` 路由判断要跟它一致:

- 选 A → `isinstance(state["messages"][-1], HumanMessage)` 判断要不要回 llm
- 选 B → `state.get("rejected")` 判断

**判断锚点**:LangGraph 的设计哲学是 messages 是"对话总线",AgentState 字段是"控制总线"。**reject 这条信号本质是给谁看的**?

- 给 LLM 看的语义反馈("你刚才那个调用被拒了,因为 X") → 它属于对话 → 选 A
- 给 graph 看的分支信号("出现 reject 时走特殊路径") → 它属于控制 → 选 B

A 更天然 —— 一条消息既是 LLM 上下文,也是 isinstance 路由依据,**一份数据两个用途**。B 更显式但要多写代码。

### ★ Insight(三问)

- **三问的因果链是 Q1 → Q2 → Q3**:payload 决定外端能展示什么,展示决定用户能给什么决策,决策决定 reject 是否需要回流(如果你 Q2 不支持 reject,Q3 就不存在)。所以不是三个独立选择题,是一条线 —— 越往后选项越多,但你想清楚 Q1 后,Q2 Q3 自然收窄。
- **外端代码 ≠ 节点代码**。三问里只有 Q2 是"双方约定";Q1 是节点单方面定义("我推什么给你");Q3 完全是节点内部决策(外端只管把 decision 传回来,不关心 LLM 怎么"看见")。理清这个边界,你写 client 时就知道"哪些 dict 字段是契约,哪些是节点自由发挥"。
- **新手最容易踩的坑是 Q3 选 B 但忘了改 call_llm**。LLM 不会自动看 state 字段,必须主动注入 prompt。这就是为什么 day4 默认推荐 A 路线 —— 它免疫这个 bug,因为 messages 是 LLM 调用的天然输入。

---

## 4. Q2 锁定 → Q1/Q3 收窄

Q2 标准档锁定 → `decision = {"action": "approve"} | {"action": "reject", "reason": str}`。这把 Q1 和 Q3 的可选范围都收窄了:

| 问 | Q2=标准 之后还剩什么选择 |
|---|---|
| Q1(payload 内容) | "edit" 路径已被砍掉 → payload 不需要带"可编辑参数提示";只剩**展示哪些信息**的取舍 |
| Q3(reject 回流) | reject + reason 已是契约 → reject 路径**必须**回流(不能 END);只剩 **A 消息总线 vs B 控制总线** |

### 决定 1 · payload 字段(Q1 收窄版)

外端要渲染审批界面,你给它**最少必需信息**就好。三个候选,按信息量排序:

```python
# 候选 ① 极简:只带 tool_calls
{"tool_calls": [{"name": "read_file", "args": {...}}, ...]}

# 候选 ② 标准:加上 stage 标签 + 当前 iter 数
{"stage": "pre_tool", "iter": 3, "tool_calls": [...]}

# 候选 ③ 加 reasoning(让人能看懂"agent 为啥这么干")
{"stage": "pre_tool", "tool_calls": [...], "reasoning": "<LLM 的 reasoning_content>"}
```

判断:你跑这个 demo 时,你自己作为审批人,**只看 tool 名 + args 能不能判断要不要批**?如果 LLM 偶尔会决策得很反直觉(比如 read 一个看起来不相关的文件),那 ③ 帮助大;如果都是直白调用,② 就够。

### 决定 2 · reject 回流走 A 还是 B

A 和 B 的差异**在 LLM 端可见性**上,不在外端:

| 选 A(消息) | 选 B(state 字段) |
|---|---|
| `return {"messages": [HumanMessage(f"[人工拒绝] {reason}")]}` | `return {"rejected": True}` + 改 AgentState schema |
| LLM 下一轮自然看见(messages 本来就是 prompt) | LLM 看不见 state 字段,必须改 `call_llm` 注入 prompt |
| `post_review` 用 `isinstance(last, HumanMessage)` 路由 | `post_review` 用 `state.get("rejected")` 路由 |
| 一份数据两个用途(LLM 上下文 + 路由信号) | 显式但啰嗦 |

判断:你这次 demo 想不想动 `infra/agent_graph.py` 的 `AgentState`?

- **不想** → 选 A,完全在 day4_hitl.py 里写完
- **想** → 选 B,顺便练 state schema 扩展

### ★ Insight(收窄)

- **设计三问的求解顺序不是 Q1→Q2→Q3,是 Q2 → Q1+Q3**。Q2(契约)定下来后,另外两问的可选空间会因连锁约束自动收窄。选完 Q2,Q3 的"是否需要回流"自动变成"必须回流",决策树砍掉一半。
- **A vs B 的本质对应到 OS 设计的 "in-band signaling vs out-of-band signaling"**。messages 是 in-band(数据流就是控制流),state 字段是 out-of-band(单独控制通道)。in-band 更省事但耦合,out-of-band 更解耦但要多接一根线。LangGraph 把 messages 当一等公民,等于鼓励 in-band。
- **这次决策直接影响 day5(长期记忆 / embedding 召回)**。如果你 day4 选 A 习惯了"把控制信号编码进 messages",day5 召回历史摘要时也会倾向"把摘要塞回 messages",而非"加 retrieved_context 字段"。设计风格是会传染的 —— 现在选好。

---

## 5. 设计三问最终锁定(本次实操选择)

| 问 | 选择 | 决策摘要 |
|---|---|---|
| Q1 | ③ | payload 含 `stage` / `tool_calls` / `reasoning` |
| Q2 | 标准 | `{"action": "approve"}` 或 `{"action": "reject", "reason": str}` |
| Q3 | A | reject 时追加 `HumanMessage("[人工拒绝] ...")`,走消息总线回流 |

### 三个落地提示(不写出来你会 grep 半天)

1. **`reasoning_content` 字段位置** — DeepSeek 思考模式的 reasoning 不在 `AIMessage.content`,而在 `last.additional_kwargs["reasoning_content"]`(可能为 `None`,要做 `or ""` 兜底)。Day 3 的 `day3_sqlite_resume.py` 末尾注释里有真实数据可对照。
2. **`last.tool_calls` 已是 LangChain 标准化格式** — 是 `list[dict]`,每个 dict 有 `{"name", "args", "id", "type"}`。你不需要再 `convert_to_openai_messages` 转换(那是给 LLM API 用的,这里给人看反而要保持 dict)。
3. **client 端拿到的 payload 形态** — `chunk["__interrupt__"][0].value` 直接就是你 `interrupt(...)` 传进去的那个 dict。`render_payload` 函数(已写好的胶水)目前只读 `payload["preview"]`,你如果改名叫 `tool_calls`,记得**同步改 render_payload**(契约一致性,用户决策的边界要自洽)。

### 两个建议测试场景

| 场景 | 输入 | 预期 |
|---|---|---|
| Happy | "读 math_utils.py,告诉我有哪些函数" + 全程按 `y` | 1 次审批 → tool 执行 → LLM 答 14 个函数 → END |
| Reject 回流 | 同上,第一次按 `r` 输 "别用 read_file,直接告诉我猜测" | LLM 应该收到"被拒"的消息,**不再调 read_file**,要么换工具要么直接编(后者会暴露其没记忆) |

跑完贴输出做 review。如果 reject 路径出现死循环(LLM 反复调同一个被拒的工具),那是 prompt 工程问题。

### ★ Insight(锁定)

- **你刚才两步选完三问,本质完成了一次"协议设计"**。payload + decision schema + 回流通道 = HITL 这个跨进程协议的 wire format 定义。这跟 gRPC 定义 `.proto` 文件是同一种活动 —— 协议想清楚后,两端实现各管各的。day4 真正在练的"理解 X" = "理解协议设计而非框架 API",这是为什么不能代笔的根本原因。
- **`render_payload` 故意用了 `payload["preview"]` 当 key**。你刚选 ③ 档后,字段叫 `tool_calls` 比 `preview` 更准确 —— 这是个**故意留的小一致性陷阱**:让你跑一次发现外端展示空白,自己回去把 render 同步改掉。这种"两端 schema 不一致"的 bug 是 HITL/RPC 协作里最常见的一类,撞一次比看 10 篇博客都深。
- **reject 路径**会让你撞到一个真问题:LLM 收到 "[人工拒绝] 别用 read_file" 后,可能仍然调 read_file(它"懂"被拒但 prompt 力度不够强)。这不是你的 bug,是 prompt 设计的 trade-off —— 你会自然产生疑问:"我是该把拒绝消息加粗?用 SystemMessage 而非 HumanMessage?"。把这个疑问留到跑完再答,不要预先优化。

---

## 6. 代码翻译 · `human_review`

把 ① / 标准 / A 的三个选择**翻译成代码**(设计是你的,代笔只是编码工作):

```python
def human_review(state: AgentState) -> dict:
    last = state["messages"][-1]

    # ── Q1 = ③ payload 结构 ──────────────────────────
    # tool_calls 已是 LangChain 标准化 dict 格式,直接挑两个字段给外端看
    tool_calls_view = [
        {"name": tc["name"], "args": tc["args"]}
        for tc in (last.tool_calls or [])
    ]
    # DeepSeek 思考模式的 reasoning_content 在 additional_kwargs 里,可能为 None
    reasoning = (last.additional_kwargs or {}).get("reasoning_content") or ""

    decision = interrupt({
        "stage": "pre_tool",
        "tool_calls": tool_calls_view,
        "reasoning": reasoning,
    })

    # ── Q2 = 标准 schema 解析 ────────────────────────
    # decision 形如 {"action": "approve"} 或 {"action": "reject", "reason": str}
    if isinstance(decision, dict) and decision.get("action") == "reject":
        reason = decision.get("reason", "(无理由)")
        # ── Q3 = A 回流:追加 HumanMessage,add_messages reducer 会 append ──
        return {
            "messages": [
                HumanMessage(
                    content=f"[人工拒绝] {reason}。请换个思路,不要再调刚才那些工具。"
                )
            ]
        }
    # approve 路径:state 不动,conditional edge 把控制权交给 tools
    return {}
```

### 每行对应哪个决策

| 代码行 | 对应决策 |
|---|---|
| `tool_calls_view = [...]` | Q1 = ③ 的 "tool_calls 字段" 部分 |
| `reasoning = last.additional_kwargs.get("reasoning_content")` | Q1 = ③ 的 "加 reasoning" 部分 |
| `interrupt({"stage": ..., "tool_calls": ..., "reasoning": ...})` | Q1 = ③ 的完整 payload |
| `decision.get("action") == "reject"` | Q2 = 标准 schema 的解析 |
| `decision.get("reason", ...)` | Q2 = 标准 schema 里的 reason 字段 |
| `return {"messages": [HumanMessage(...)]}` | Q3 = A 的消息总线回流 |
| `return {}`(approve) | Q2 = 标准 schema 的 approve 路径 |

### ★ Insight(代笔)

- **`human_review` 代笔 = 打破刚立的契约**。但你是契约制定者,主动放弃"自己写"这部分是你的权利。折中:用代码 + 决策映射表,把"代笔产物"变成"翻译产物" —— 你看映射表能反推出每个设计选择,知识不会因为没自己写而流失。这跟"老师写示范 + 注解每一行的设计意图"是同一种教学法。
- **`reasoning or ""` 的兜底很关键**。DeepSeek 思考模式开了才有 reasoning_content,没开是 None;非思考的 LLM(GPT-4o 等)根本没这个字段。`(last.additional_kwargs or {}).get(...) or ""` 双重兜底保证不崩 —— 三段防御对应三种 None 来源(additional_kwargs 字段不存在 / 字段是 None / 字段值是 None)。**这是 messages schema 跨模型兼容的一个微观但高频的坑**。
- **render_payload 的 key 不一致是教具,不该提前消除**。如果代笔时"贴心"地一并把 render_payload 也改对,你就失去了一次"跑 demo → 发现空白 → grep 找原因 → 修协议契约"的循环训练。这种循环 = 真正的 RPC/HITL 工程师肌肉。

---

## 7. 代码翻译 · `post_review`(Q3=A 闭环)

按 Q3=A 翻译。和 `human_review` 是同一份契约的另一半:

```python
def post_review(state: AgentState) -> str:
    last = state["messages"][-1]

    # ── Q3 = A 一致性判断 ──────────────────────────────
    # human_review 在 reject 时追加了 HumanMessage,在 approve 时返回 {}
    # 所以"末条是 HumanMessage" ⇔ 走过了 reject 路径
    if isinstance(last, HumanMessage):
        return "llm"   # 回 LLM 重新规划

    # 否则:末条仍是原来那个带 tool_calls 的 AIMessage(approve 路径)
    return "tools"     # 放行去执行工具
```

### 对应映射

| 代码行 | 对应决策 |
|---|---|
| `last = state["messages"][-1]` | 利用 Q3=A 选择消息总线后,reject 信号必然在末条 |
| `isinstance(last, HumanMessage)` | Q3=A 的"末条是不是被拒消息"判断方式 |
| `return "llm"` | 路由到 build_graph_hitl 的 mapping `{"llm": "llm"}` |
| `return "tools"` | 路由到 mapping `{"tools": "tools"}` |

### 一致性检查清单

| 项 | 应该是 | 备注 |
|---|---|---|
| `human_review` reject 追加什么 | `HumanMessage` | ✅ |
| `post_review` 用什么判 reject | `isinstance(last, HumanMessage)` | ✅ 对得上 |
| `post_review` 返回值 | `"tools"` 或 `"llm"` | ✅ 跟 mapping 字面一致 |
| build_graph_hitl mapping | `{"tools": "tools", "llm": "llm"}` | ✅ 已写好 |

四个齿轮咬合,Q3=A 闭环。

### ★ Insight(post_review)

- **`post_review` 只有 4 行 = Q3=A 的红利**。如果选了 B(state flag),这里得是 `if state.get("rejected"): state["rejected"] = False; return "llm"` —— 还得在某处把 flag 清零(否则下一轮 LLM 重新决策后,post_review 仍然看到 `rejected=True`,会无限回流到 llm)。**A 路线天然没有这个 reset 问题**,因为 messages 是 append-only,新一轮 LLM 调用产生新 AIMessage 自动覆盖"末条是不是 HumanMessage"的判断。这就是 in-band signaling 的另一个隐藏好处:**不需要 reset 状态**。
- **`isinstance(last, HumanMessage)` 这一行隐含了对 reducer 的信任**。如果 add_messages reducer 哪天升级让 dict 形态消息不被自动转 BaseMessage,这行会 silently 失效(dict 不是 HumanMessage 实例 → 永远走 tools)。**生产代码里更稳的写法是检查类型 + 内容前缀双保险**:`isinstance(last, HumanMessage) and last.content.startswith("[人工拒绝]")`。day4 教学版可以保持简洁,但 week6 mini-aider 上线时记得加这道防线。
- **路由函数的"单一返回 = 单一路由"约定**。LangGraph 的 conditional_edge 函数必须返回 mapping 里有的字符串,**不能 return list**(同时去 tools 又去 llm 是诡异语义)。这是 graph 必须保持"决策树而非决策图"的硬约束。要 fan-out 必须用 `Send` API(week5/6 才会接触),路由函数本身永远是 string → string。

---

## 8. 工程协议(后续踩坑提示)

实操中真实撞到的两个协议坑(在 day4_hitl.py 跑通后才浮现):

### 坑 1:`render_payload` key 不一致(故意陷阱)

`render_payload` 读 `payload["preview"]` 但 human_review 用的 key 是 `tool_calls` —— 第一次跑会发现外端审批界面 tool 列表空白。**这是协议两端 schema drift 的最小 reproducer**。修法:把 render_payload 的 key 同步改成 `tool_calls`。

### 坑 2:OpenAI 协议刚性

按 Q3=A 改完后,reject 时追加 HumanMessage,跑会撞:

```
BadRequestError: An assistant message with 'tool_calls' must be followed by tool messages
responding to each 'tool_call_id'
```

根因:AIMessage(tool_calls=[...]) 后**必须**接 ToolMessage(每个 tool_call_id 一条),不能直接接 HumanMessage。这是 OpenAI Chat Completions API 的协议刚性,LangChain 不替你绕。

修法:reject 时把 HumanMessage 改成 ToolMessage,每个 tool_call 一条:

```python
if isinstance(decision, dict) and decision.get("action") == "reject":
    reason = decision.get("reason", "(无理由)")
    return {
        "messages": [
            ToolMessage(
                content=f"[人工拒绝执行] 用户理由: {reason}。请换个思路,不要再调这个工具。",
                tool_call_id=tc["id"],
            )
            for tc in last.tool_calls
        ]
    }
```

post_review 同步改:

```python
if isinstance(last, ToolMessage) and last.content.startswith("[人工拒绝执行]"):
    return "llm"
```

**协议刚性比 reducer 灵活性优先级高**:LangChain 的 add_messages reducer 不在乎你 append 什么,但 OpenAI API 在乎。所以 wire format 的设计要考虑下游 LLM 的协议约束,不是只在 LangGraph 内部自洽就行。

---

## 关联

- `hitl-interrupt-mechanism.md` — interrupt + Command(resume) 机制本身(本文档的 mechanic 基础)
- `dangerous-op-gating.md` — 把这套设计应用到破坏性操作 gating 的范式
- `langgraph-state-vs-control-flow.md` — Q3=A 里 `return {}` 和 `return {"messages": [...]}` 的精确差异
- `langgraph-stream-chunks.md` — chunk 里 `__interrupt__` 形态对应 payload 取值路径
- `AIMessage-schema.md` — `last.tool_calls` / `additional_kwargs.reasoning_content` 的字段拆解
- `~/ai_agent_learning/week2/day4_hitl.py` — 真实工程实现
