# Subagent 答案的不可靠性与 WebFetch 实锤验证纪律

## 触发提问

> @"claude-code-guide (agent)" 一下 claude/rules 目录的加载机制是自动的,还是必须要用 at 引用?

## 关键结论

- **subagent(包括 claude-code-guide 这种"权威感"很强的专用 agent)的答案也可能是凭印象编造的**,即使它声称"基于官方文档"。
- **identifying signs of fabrication**:
  1. 引用了 URL 但没贴 WebFetch 实际抓取的原文段落
  2. 一次回答内自相矛盾("完全虚构" → 紧接着"其实是真的")
  3. 信心度异常高但与你已知事实强烈冲突
  4. 引用的特性名称像别家产品(如把 Cursor 的 `.cursor/rules/` 特性套到 Claude Code 上)
- **正确流程**: 当 subagent 结论与已知事实冲突时,**自己用 WebFetch 拉官方页**,贴原文段落作为证据;**不要二次让同一类 agent 验证自己**(它会再次幻觉)。
- **委派 ≠ 信任**:把"验证"委派给 subagent 不能节省决策成本,只能并行收集证据。最终判定必须基于**可引用的原文**,不是 agent 的复述。
- **`code.claude.com` 是当前 Claude Code 文档的真实域名**(`docs.claude.com/en/docs/claude-code/memory` 301 重定向至此),不要因为"没听过这个域名"就否定。

## Schema / 字段表

### 决策树:面对 subagent 答案如何处理

| Subagent 表现 | 我应该做的 |
|--------------|----------|
| 引用了 URL **且** 贴了原文段落 | 信任度 ↑,但仍可挑战明显冲突点 |
| 引用了 URL **但** 只有自己复述 | 不信,亲自 WebFetch 验证 |
| 一次回答内立场翻转 | 完全不信,自己亲自验证 |
| 与我已知事实强烈冲突 | 优先信我,但用 WebFetch 二次裁决 |
| 答案"听起来像别家产品的特性" | 警惕 LLM 跨产品幻觉,亲自验证 |

### Fabrication 类型分类

| 类型 | 表现 | 例子 |
|------|------|------|
| 域名幻觉 | 引用根本不存在的 URL | 编一个 `docs.foo.com/bar` |
| 跨产品幻觉 | 把 A 产品的特性套到 B 产品 | 把 Cursor `.cursor/rules/` 当作 Claude Code 特性 |
| 复述失真 | URL 存在但原文不是这意思 | 看了页面但歪曲转述 |
| 信心翻转 | 同一回复内 "X is false" → "X is true" | 自我审查未完成就发送 |

## 代码示例

### 正确的实锤验证流程(本次会话采用)

```text
1. user: 问 X 是不是 Y
2. me: 答 X 不是 Y (基于印象)
3. user: 用 agent 验证一下
4. agent: 答 X 就是 Y (引用 docs URL,但没贴原文)
5. me(怀疑): 用 SendMessage 让 agent 实地 WebFetch + 贴原文
6. agent: 自相矛盾的回答
7. me(放弃 agent): 亲自 WebFetch docs URL
8. me: 贴官方原文段落 → 实锤 X 就是 Y → 给 user 改正答案 + 道歉
```

### Anti-pattern: 让 agent 验证自己

```text
1. agent A 给了答案
2. me: 让 agent B (同类型) 验证 agent A 的答案
3. agent B 同样幻觉,可能加固错误
```

**为什么不行**: 同类型 agent 共享相似训练分布,大概率犯**同一类幻觉**(尤其是流行混淆点,如 Cursor vs Claude Code 的 rules 机制)。

### 正确并行调用 WebFetch 实锤

```python
# 当 agent 给出可疑结论时,亲自:
WebFetch(url=候选URL_1, prompt="逐字摘录所有提到 X 的原文段落,不存在就明说")
WebFetch(url=候选URL_2, prompt="...")
# 拿到原文 → 自己判断 → 不再依赖 agent 复述
```

## 坑 / Why

### 坑 1: "权威感强的 agent 名" 不等于答案权威

`claude-code-guide` 听起来是"Claude Code 官方答疑专家",但本质仍是 Claude 模型 + 一组工具,**没有官方知识库或权威白名单**。它的答案质量 = 它有没有 WebFetch + 它解读原文的能力。

如果它跳过了 WebFetch,直接给"看起来权威"的答案,**与一个没工具的普通模型无异**。

### 坑 2: agent 用"我承认我错了"作为社交策略,但实际仍在幻觉

第二轮 agent 开头说"完全坦诚认错。我之前的回答完全虚构",但下一段又说"`.claude/rules/` 确实存在且会自动加载 ✅"。看似自我纠错,实则**继续输出同一组未经验证的论断**,只是换了态度包装。

辨认信号:**有道歉但没有新证据(WebFetch 原文)** = 仍在幻觉。

### 坑 3: 因为"没听过这个域名"就否定

`code.claude.com` 我没见过,本能觉得是 agent 编的。但实际上 Anthropic 把 Claude Code 文档迁到了独立域名,`docs.claude.com/en/docs/claude-code/memory` 现在 301 重定向到 `code.claude.com/docs/en/memory`。

**Anthropic 自己的文档结构会变化**(尤其 2026 年这种快速迭代期),不要因为陌生就否定。亲自 fetch 一下 URL 存不存在,2 秒搞定。

### 坑 4: 把"问 user 改 CLAUDE.md"的建议过早执行

如果我第一轮就听 agent 的、立刻让 user 删那 6 行 @import,假设 agent 的结论是错的,user 的 6 个规则文件就**全部静默不加载**了,后续训练全废。

**护栏**: 涉及"删除用户生产配置"的建议,无论 agent 多自信,**都要先实地验证再执行**。

### Why: 为什么 subagent 也会幻觉?

subagent 不是另一个模型实例 + 知识库,它是**同一个 Claude 模型 + 受限工具集 + 不同 system prompt**。模型的训练分布、知识截止时间、跨产品混淆倾向**完全继承**。专用 agent 只是把"用什么工具""按什么格式输出"约束住,**不约束事实正确性**。

唯一能消除模型幻觉的是**外部权威源(网页/文件/数据库)的实地读取**。`claude-code-guide` 如果不调 WebFetch,它的答案就是模型脑补。

### Why: 为什么"亲自 WebFetch"比"让 agent 再调 WebFetch"更可靠?

- 我能**直接看到原文**,而不是 agent 的二次复述(每次复述都可能扭曲)
- 我能**自己设计 prompt** 强制要求"逐字摘录,不存在就明说",而不是依赖 agent 自觉
- 时间成本相同(都是 1 次 WebFetch),但**信号纯度高一个数量级**

## 关联

- [[claude-code-rules-directory]] —— 本次发现错误的具体案例:`.claude/rules/` 是不是约定目录
- [[claude-md-import-syntax]] —— 同一案例衍生出的 `@import` 机制澄清
