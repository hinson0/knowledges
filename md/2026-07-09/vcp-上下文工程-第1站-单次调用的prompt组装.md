# VCP 上下文工程 · 第 1 站：单次调用的 prompt 组装

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 前置环境：Node 24（`nvm use 24`）+ 仓库根执行过 `pnpm install`。

## 0. 本站要解决的问题

LLM 无状态：**每次调用，你发什么它就只知道什么**。最简单的场景是"单次调用"——没有历史、没有工具循环，一问一答（VCP 的 Clarify agent 就是这样：输入 brief，输出结构化澄清问题）。

即便这么简单，裸写 prompt 也会立刻遇到三个问题：

1. **规则漂移**：安全红线这类规则要出现在多个 agent 的 prompt 里。如果每处手写一遍，改一处漏一处，没有任何机制能发现。
2. **缓存全废**：Anthropic 的 prompt caching 按**最长公共前缀**匹配计费（读缓存只要 0.1x 价钱）。如果把每次都不同的内容（brief）混在固定规则前面，公共前缀从第一个字节就分叉，缓存彻底失效。
3. **模型分不清哪些是规则、哪些是本次输入**：规则和输入搅在一起，模型容易把某个 brief 里的措辞当成通用指令。

VCP 的答案是一个不到 110 行的文件：`apps/agent/src/agents/prompt-redlines.ts`。它是整个上下文工程体系的**最小内核**——后面每一站的机制都建立在它的三个原语上。

## 1. 核心代码导读

### 1.1 规则 = 导出常量（不是散落的字符串）

`apps/agent/src/agents/prompt-redlines.ts:6-7`：

```ts
export const SECURITY_REDLINE =
  "NEVER output secrets, tokens, Authorization headers, Cloudflare account or gateway paths, ...";
```

同文件还有 `WORKSPACE_WRITE_REDLINE`（:12，只许通过 `apply_patch_batch` 写代码）、`CONTENT_INTEGRITY_REDLINE`（:24，禁止编造 brief 没给的业务事实）、`CONTENT_INTEGRITY_SELF_VERIFY`（:31，要求模型输出前回扫自检每条业务事实）、`FORM_VALIDATION_CONTRACT_LINES`（:42，表单校验契约，是一个**字符串数组**，每行一条规则）。

要点：
- 每个常量上方有中文 JSDoc，写明**谁消费它**（"所有 agent 系统提示词身份句之后第一条"）——规则有归属，不是漂在文档里；
- 需要多行的契约用 `readonly string[]`，拼装端用 `...` 展开，测试端可以逐行断言；
- 任何 agent 要用规则就 import 常量。改规则只改一处，所有消费方同步更新。

### 1.2 PROMPT_DYNAMIC_BOUNDARY：一行文本的双重作用

`prompt-redlines.ts:79-80`：

```ts
export const PROMPT_DYNAMIC_BOUNDARY =
  "=== DYNAMIC RUN CONTEXT (request-specific; nothing below is cached) ===";
```

作用一：**缓存分界的可读标记**——它上面的内容跨请求字节一致（可缓存），下面每次都不同。
作用二：**模型注意力信号**——明确告诉模型"这条线以下是本次请求的具体输入，不是通用规则"。

### 1.3 composeUserPrompt：静态/动态强制拆分

`prompt-redlines.ts:98-103`：

```ts
export function composeUserPrompt(parts: {
  staticPrefix: string;
  dynamicSuffix: string;
}): string {
  return `${parts.staticPrefix}\n${PROMPT_DYNAMIC_BOUNDARY}\n${parts.dynamicSuffix}`;
}
```

这个函数刻意用**对象参数强制调用方做分类**：你必须想清楚哪些内容是"每次请求都一样的"（staticPrefix）、哪些是"本次独有的"（dynamicSuffix），才能调用它。类型签名本身就是设计约束。

### 1.4 cacheableSystem：给 system 打缓存断点

`prompt-redlines.ts:85-93`：

```ts
export function cacheableSystem(content: string): SystemModelMessage {
  return {
    role: "system",
    content,
    providerOptions: {
      anthropic: { cacheControl: { type: "ephemeral" } },
    },
  };
}
```

AI SDK 允许在消息上挂 `providerOptions`；`anthropic.cacheControl = { type: "ephemeral" }` 就是 Anthropic prompt caching 的断点标记——"缓存到此为止的全部前缀"。所有 agent 的 system prompt 都经这个函数包装，这是每次调用的**第 0 个断点**（缓存断点的完整玩法在第 5 站）。

### 1.5 最简完整实例：buildClarifyPrompt

`apps/agent/src/agents/clarify/clarify.service.ts:1135-1150`（摘录）：

```ts
export function buildClarifyPrompt(input: ClarifyRunInput): string {
  const staticPrefix =
    "Return questions that help decide audience, visual tone, conversion goal, ...";
  // 站点产出语种指令：放在动态段（不进可缓存 staticPrefix），仅当调用方传入
  // site_default_locale 时追加，并钉在 brief 之后压轴。
  const localeDirective = input.site_default_locale
    ? [ "", `- Output language (authoritative): write EVERY natural-language string ... in the "${input.site_default_locale}" locale (BCP-47) ... This overrides the Language rule in the system prompt.` ].join("\n")
    : "";
  const dynamicSuffix = ["Brief:", input.brief].join("\n") + localeDirective;
  return composeUserPrompt({ staticPrefix, dynamicSuffix });
}
```

三个值得咀嚼的决策：

1. **brief 放 dynamicSuffix**：brief 每个站点都不同。放静态前缀会让缓存前缀分叉（见第 0 节问题 2）。
2. **localeDirective 也放动态段**：它含具体 locale 值（`"zh"`/`"en"`...），有值就不是跨请求恒定的，进 staticPrefix 会把缓存按 locale 分裂。
3. **localeDirective 钉在 brief 之后压轴**：源码注释写明原因——澄清问题的输出语言只由站点语种决定，**brief 本身的语言不能改变输出语言**。把权威指令放在 brief 后面（离模型生成位置最近），并显式声明 "This overrides the Language rule in the system prompt"，是在对抗"模型跟着最近看到的大段文本（brief）的语言走"的偏置。**位置即权重**：越靠后的指令对生成的影响越强。

再看 system 侧 `buildClarifySystemPrompt`（`clarify.service.ts:1168` 起）：`base` 字符串的身份句之后第一条就是拼接的 `SECURITY_REDLINE`（:1174）——1.1 节的常量在这里被消费。它还有条件段（catalog 数量 ≥2 或 ≤1 时**切换措辞**而不是增删大段），这个"条件=措辞切换、按参数分桶"的手法在第 4 站会看到完整版。

## 2. 动手实践（命令均已实机验证）

### 实践 A：直接调用组装原语，观察产物

把下面的脚本存到任意目录（示例：`~/tmp/station1-demo.ts`；脚本可放仓库外，用绝对路径导入源码，tsx 能直接加载 .ts）：

```ts
import {
  composeUserPrompt,
  cacheableSystem,
  PROMPT_DYNAMIC_BOUNDARY,
  SECURITY_REDLINE,
} from "/Users/a114514/ce_repos/vcp/apps/agent/src/agents/prompt-redlines.ts";

console.log("=== 1) composeUserPrompt：静态前缀 + 边界 + 动态尾部 ===\n");
console.log(composeUserPrompt({
  staticPrefix: "Return questions that help decide audience, visual tone, conversion goal.",
  dynamicSuffix: "Brief:\n一家开在杭州的手冲咖啡店，主打单一产地豆子。",
}));

console.log("\n=== 2) 边界标记本体 ===\n");
console.log(PROMPT_DYNAMIC_BOUNDARY);

console.log("\n=== 3) cacheableSystem：带缓存断点的 system 消息结构 ===\n");
console.log(JSON.stringify(cacheableSystem("You are a helpful agent. " + SECURITY_REDLINE.slice(0, 60) + "..."), null, 2));
```

在**仓库根**运行（`--filter @vcp/agent` 借用 agent 包里装好的 tsx）：

```bash
pnpm --filter @vcp/agent exec tsx ~/tmp/station1-demo.ts
```

实测输出（节选）：

```
Return questions that help decide audience, visual tone, conversion goal.
=== DYNAMIC RUN CONTEXT (request-specific; nothing below is cached) ===
Brief:
一家开在杭州的手冲咖啡店，主打单一产地豆子。

{
  "role": "system",
  "content": "You are a helpful agent. NEVER output secrets, tokens, ...",
  "providerOptions": {
    "anthropic": { "cacheControl": { "type": "ephemeral" } }
  }
}
```

观察点：边界标记把 prompt 切成上下两段；system 消息是一个带 `providerOptions` 的对象，不只是字符串。

### 实践 B：跑 Clarify 的单测，看规则如何被测试消费

```bash
pnpm vitest run apps/agent/src/agents/clarify/clarify.service.test.ts
```

实测：39 个测试全绿，约 1 秒。打开这个测试文件，找找哪些断言在锁 prompt 的内容（比如对 buildClarifyPrompt/System 输出的 `toContain` 断言）——这是第 4 站"守卫测试"的前菜。

### 实践 C（自由探索）

改一下实践 A 脚本：把 brief 放进 staticPrefix、把规则放进 dynamicSuffix，打印出来对比。问自己：如果两个不同站点各调一次，这两次请求的"公共前缀"到哪个字节为止？

## 3. 自测题

1. 为什么 brief 原文必须放 dynamicSuffix、规则说明放 staticPrefix？
2. `PROMPT_DYNAMIC_BOUNDARY` 除了标记缓存分界，还有什么作用？
3. localeDirective 为什么钉在 brief **之后**而不是之前？
4. `cacheableSystem` 返回的对象比裸字符串多了什么？这个"多出来的东西"是给谁看的？

## 4. 与下一站的衔接

单次调用只需要"组装一次"。但 Workspace agent 是多轮对话 + 工具循环：第二轮时，模型怎么知道第一轮改了哪些文件、问过什么问题？"记忆"从哪来？这是第 2 站（事件溯源与消息重建）要解决的问题——也是整个体系里最重要的一站。

---

## 自测题答案

1. brief 每次请求都不同。缓存按最长公共前缀匹配，动态内容放前面会让前缀从第一个字节就分叉，后面的固定规则再一致也无法命中缓存。规则放前面则所有请求共享同一段可缓存前缀。
2. 注意力信号：显式告诉模型"这条线以下是本次请求的具体输入，不是通用规则"，防止模型把某次 brief 里的措辞泛化成指令。
3. 两个原因：(a) 它含具体 locale 值，不是跨请求恒定内容，放前面会污染静态前缀；(b) 位置即权重——钉在 brief 之后离生成位置最近，配合 "This overrides..." 声明，对抗模型跟随 brief 语言的偏置（源码注释 `clarify.service.ts:1138-1141` 写明了这一点）。
4. 多了 `providerOptions.anthropic.cacheControl = { type: "ephemeral" }`。这不是给模型看的——模型看到的文本完全一样；它是给 **Anthropic API 计费/缓存层**看的标记："请把到此为止的前缀写入/读取缓存"。
