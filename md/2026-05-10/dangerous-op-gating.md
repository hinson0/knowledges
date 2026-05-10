# 破坏性操作的 HITL gating 范式

> 高破坏性 = 错一次很难回滚,代价远高于"问一句"。
> 例:`run_shell("rm -rf ...")` / `apply_patch` / `git push --force` / 发 PR / 发邮件 / DB DDL。

## 核心原则:gating 靠图拓扑,不靠 prompt

❌ 错误做法:在 system prompt 里写 "危险时请先问用户"。
- LLM 会忘、被绕过、冒险
- 不可审计 / 不可单测

✅ 正确做法:**execute 节点的入边只有一条,来自 review**。审批不通过,在拓扑结构上就到不了 execute。

## 三层防御范式

```
第 1 层:边路由(gate 函数)         危险工具 → review,无路绕过
第 2 层:节点内审批(review)        interrupt 把决定权交宿主
第 3 层:execute 内置断言            未审批不动手(防误连边 / 防被绕过)
```

任一层守住就不会发生破坏。**多个独立守门人比一个聪明大门可靠**。

## 关键 UX:payload 必须塞预览

审批不是"按 y/n",是"看到将要发生什么再决定":

| 操作 | preview 内容 |
|---|---|
| `delete_file(p)` | 文件前 200 字 + 行数 + size |
| `apply_patch(diff)` | unified diff 全文 |
| `run_shell(cmd)` | 命令全文 + 工作目录 |
| 发 PR | 标题 + body 摘要 + base/head |
| 发邮件 | to/subject/body 摘要 |

生产 HITL 80% 的价值在这里。

## 危险工具白名单

```python
DANGEROUS_TOOLS = {"delete_file", "run_shell", "apply_patch", "send_email"}
```

简单的 set membership 比"风险评分模型"更可靠 —— 可审计、可回归测试、可静态扫。

## 最小 demo:删文件前必审

```python
import operator
from typing import Annotated, Literal, TypedDict

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import START, END, StateGraph
from langgraph.types import Command, interrupt


FAKE_FS = {"a.txt": "hello", "secret.key": "DO_NOT_DELETE_PROD_KEY"}
DANGEROUS_TOOLS = {"delete_file", "run_shell", "apply_patch"}


class State(TypedDict):
    plan: list
    approved: bool
    log: Annotated[list, operator.add]


def propose(state: State) -> dict:
    """模拟 agent 决定删 secret.key —— 真实场景这是 call_llm 节点。"""
    return {
        "plan": [{"name": "delete_file", "args": {"path": "secret.key"}}],
        "log": ["[propose] 决定: delete_file(secret.key)"],
    }


def gate(state: State) -> Literal["review", "execute", "__end__"]:
    """第 1 层:边路由 —— 含危险工具 → review。"""
    plan = state.get("plan") or []
    if not plan:
        return END
    if any(c["name"] in DANGEROUS_TOOLS for c in plan):
        return "review"
    return "execute"


def review(state: State) -> dict:
    """第 2 层:HITL 审批 —— payload 含预览。"""
    plan = state["plan"]
    danger = [c for c in plan if c["name"] in DANGEROUS_TOOLS]
    previews = {}
    for c in danger:
        if c["name"] == "delete_file":
            path = c["args"]["path"]
            previews[path] = FAKE_FS.get(path, "(不存在)")[:200]

    decision = interrupt({
        "prompt": "以下破坏性操作需要审批",
        "danger_calls": danger,
        "previews": previews,
    })

    if decision.get("action") == "approve":
        return {"approved": True, "log": [f"[review] 通过: {decision.get('reason', '')}"]}
    return {
        "approved": False,
        "plan": [],   # 拒绝时清空 plan,execute 即使被错连也无事可干
        "log": [f"[review] 拒绝: {decision.get('reason', '')}"],
    }


def execute(state: State) -> dict:
    """第 3 层:防御性断言 —— 未审批不动手。"""
    if not state.get("approved"):
        return {"log": ["[execute] 未审批,跳过"]}
    logs = []
    for c in state["plan"]:
        if c["name"] == "delete_file":
            FAKE_FS.pop(c["args"]["path"], None)
            logs.append(f"[execute] 已删除 {c['args']['path']}")
    return {"log": logs}


def build():
    g = StateGraph(State)
    g.add_node("propose", propose)
    g.add_node("review", review)
    g.add_node("execute", execute)
    g.add_edge(START, "propose")
    g.add_conditional_edges("propose", gate, {
        "review": "review", "execute": "execute", END: END,
    })
    g.add_edge("review", "execute")   # review 后必走 execute,execute 内部再判 approved
    g.add_edge("execute", END)
    return g.compile(checkpointer=InMemorySaver())
```

## 设计选择记录

| 选择 | 这里的方案 | 替代 / 何时切换 |
|---|---|---|
| 危险判定 | DANGEROUS_TOOLS 集合 | 单工具内部二级判断(`rm -rf` vs `rm 单文件`) |
| 审批粒度 | 整 plan approve/reject | 子集 approve(payload 加 `only: [...]` 字段) |
| 拒绝后 | 清 plan + execute 跳过 | 反馈给 LLM 让它换思路(参考 day4 ToolMessage 协议) |
| preview 截断 | 200 字 | 大文件分页 / 仅 head+tail |

## 与 week2 day4 的对照

day4 是把这个范式加到工具调用 agent 上的真实工程版:

- `gate` ≈ `should_continue` 路由到 `human_review`
- `review` ≈ `human_review` 节点
- `execute` ≈ `tools` 节点
- 拒绝路径多了一条:塞 ToolMessage 给 LLM 让它换思路(OpenAI 协议要求 `tool_calls` 后必须跟 `tool_call_id` 对应的 ToolMessage)

## 关联

- `hitl-interrupt-mechanism.md` — interrupt + Command(resume) 机制本身
- `~/ai_agent_learning/week2/day4_hitl.py` — 工具调用 agent 上的真实实现
- week6 计划:`apply_patch` + Docker sandbox + `run_tests` 都要套这个范式
