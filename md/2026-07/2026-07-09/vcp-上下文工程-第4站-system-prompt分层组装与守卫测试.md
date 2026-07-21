# VCP 上下文工程 · 第 4 站：system prompt 分层组装与守卫测试

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 前置环境：Node 24（`nvm use 24`）+ 仓库根执行过 `pnpm install`。
> 前置阅读：第 1 站（红线常量、composeUserPrompt、cacheableSystem）。

## 0. 本站要解决的问题

Workspace agent 有**两条生成路径**共用同一批硬规则：

- 首轮全量建站（`TEMPLATE_GENERATION_CONTRACT`，在 `workspace-initial-generation.service.ts`）
- 后续迭代编辑（`buildWorkspaceSystemPrompt`，在 `workspace-websocket.service.ts`）

如果规则各写一份，改一处漏一处——首轮生成守规矩、迭代却违规（或反之），而且**没人会发现**，直到线上某个 run 产出坏代码。此外 system prompt 还要按站点状态变化（有没有绑定 CMS、站点语种、功能开关），变化如果处理不当，要么规则该在场时缺席，要么缓存被无意义地切成碎片。

VCP 的答案分三层：**单一事实源常量** + **分层拼装函数** + **守卫测试**。核心思想一句话：**把 prompt 当代码管理——规则是常量、拼装是函数、一致性是测试用例**。

## 1. 核心代码导读

### 1.1 Tier 1 硬规则常量：单一事实源

`apps/agent/src/agents/workspace/workspace-domain-contract.ts` 开头的文件级注释就是设计说明（:1-15，摘录）：

```
仅承载"违反就坏、跨轮必须常驻"的断言式硬规则：单一 CSS 源、App Router
Server Component 边界、文件结构与路由身份、header/footer shell 外壳、导航
数据口径、媒体清单系统文件禁手改。这些常量同时被首轮全量生成
(TEMPLATE_GENERATION_CONTRACT) 与迭代编辑 (buildWorkspaceSystemPrompt) 引用。

设计 how-to（motion 选型、scroll 编排、chrome silhouette、媒体策略、SEO 写法）
不在这里——它们是 Tier 3 的 model_invocable skill（skills/page-editing/*），按需 load。
```

注意这个**准入标准**：只有"违反就坏、跨轮必须常驻"的规则才配常驻 system prompt；"怎么做更好"的 how-to 知识走 skill 按需加载（第 3 站）。这就是 token 预算的分层治理——不是所有重要的东西都值得常驻。

三个常量（:18-96）：
- `STRUCTURE_CSS_ROUTE_CONTRACT_LINES`（4 行）：单一 CSS 源 / Server Component 边界 / 路由身份
- `CHROME_SHELL_CONTRACT_LINES`（3 行）：header/footer 外壳 + `NAV_ITEMS` 数据驱动导航
- `MEDIA_MANIFEST_REDLINE`（单字符串）：媒体清单系统文件禁手改

`MEDIA_MANIFEST_REDLINE` 上方的注释（:84-90）值得细读：它要求措辞**逐字等于**某个历史断言，"改本常量措辞前必须同步这两处断言"——措辞本身是被版本化管理的契约。

### 1.2 buildWorkspaceSystemPrompt：分层拼装

`apps/agent/src/agents/workspace/workspace-websocket.service.ts:8839-8940`。函数签名即**缓存分桶键**：

```ts
export function buildWorkspaceSystemPrompt(
  strReplaceEnabled = isStrReplaceEditEnabled(),  // 功能开关：patch 协议形态
  siteDefaultLocale?: SiteLocale,                 // 站点语种
  cmsSiteId?: string | null,                      // 是否绑定 CMS
  oneFilePerCall = isIterationOneFilePerCallEnabled(), // 功能开关：一文件一调用
): string {
```

四个参数是 system prompt 的**全部**变化维度。相同参数组合 → 字节一致的 prompt → 命中同一缓存前缀。变化维度被显式收口在签名里，而不是散落在函数体的 if 里。

主体是一个字符串数组 `.join(" ")`，**拼装顺序分层**（:8878-8938）：

```ts
return ([
  "You are an expert frontend engineer iterating on a live Next.js App Router website.",
  SECURITY_REDLINE,                    // ── 第 1 层：跨 agent 共享红线（第 1 站的常量）
  WORKSPACE_WRITE_REDLINE,
  CONTENT_INTEGRITY_REDLINE,
  ...FORM_VALIDATION_CONTRACT_LINES,   // ── 第 2 层：Tier 1 领域硬规则（1.1 节常量展开）
  ...STRUCTURE_CSS_ROUTE_CONTRACT_LINES,
  ...CHROME_SHELL_CONTRACT_LINES,
  MEDIA_MANIFEST_REDLINE,
  languageDirective,                   // ── 第 3 层：按参数二选一的"措辞切换"
  conversationLanguageDirective,
  /* ...固定指令行、Decision rules、REFUSAL_COPY 模板... */
  CONTENT_INTEGRITY_SELF_VERIFY,
].join(" ")
  + cmsDynamicDataGuide.buildSkillIndexSection()  // ── 第 4 层：末尾追加段（无条件）
  + cmsDynamicDataGuide.buildSection(cmsSiteId)   //            （条件：绑定 CMS 才有）
);
```

**第 3 层的手法：条件 = 措辞切换，不是加减大段。** 例如语言行（:8850-8852）：有 locale → "exclusively in the \"zh\" locale (BCP-47)..."；无 locale → "in the same language as the user's brief and messages"。两种状态**都有一条语言规则在场**，只是措辞不同。规则永远不缺席，缓存按参数整齐分桶。

还有一个业务无关但很有启发的细节：`conversationLanguageDirective`（:8858-8859）把**聊天叙述语言**（跟随用户最新消息）和**站点文案语言**（跟随站点 locale）声明为两条互相独立的规则——注释里记着一次真实回归（全英文 prompt 上下文把模型的中文叙述带偏成英文）。教训：prompt 自身的语言会对输出语言产生引力，需要显式规则对抗。

**第 4 层的手法：内容参数化，但值不进段落。** `buildSection(cmsSiteId)` 用 `cmsSiteId` 判断注入与否，但段落内容**不含 id 值**（源码注释 :8930-8935 明确写着"两段都不含 cms_site_id 值，命中同一缓存前缀"）。如果把 id 写进段落，缓存分桶数 = 站点数；不写，分桶数 = 2（绑定/未绑定）。

### 1.3 守卫测试：把 prompt 漂移变成测试期缺陷

**三类守卫**，全在 `apps/agent/src/agents/workspace/` 下：

**(a) 措辞锁**（`workspace-domain-contract.test.ts:92-98`）——锁常量内容本身：

```ts
describe("MEDIA_MANIFEST_REDLINE", () => {
  it("媒体清单系统文件禁手改，改图走 media_requests", () => {
    expect(MEDIA_MANIFEST_REDLINE).toContain("lib/generated/media-assets.ts");
    expect(MEDIA_MANIFEST_REDLINE).toContain("media_requests");
    expect(MEDIA_MANIFEST_REDLINE).toContain("NEVER");
  });
});
```

同文件还锁**行数上限**（:42-44 `toBeLessThanOrEqual(4)`）——防止常量悄悄膨胀吃掉 token 预算；以及**负断言**（:81-85 `not.toContain("silhouette")`）——防止 Tier 3 的设计 how-to 混进 Tier 1 常量。

**(b) 双端一致性守卫**（`workspace-domain-contract.test.ts:100-124`）——本站最核心的机制：

```ts
const ITERATION_PROMPT = buildWorkspaceSystemPrompt();
const TEMPLATE_JOINED = TEMPLATE_GENERATION_CONTRACT.join("\n");

describe("Tier 1 硬规则常量首轮+迭代双向下沉一致性（防漂移单一守卫）", () => {
  it("STRUCTURE_CSS_ROUTE_CONTRACT_LINES 每行同时在首轮模板契约与迭代 prompt", () => {
    for (const line of STRUCTURE_CSS_ROUTE_CONTRACT_LINES) {
      expect(TEMPLATE_JOINED).toContain(line);
      expect(ITERATION_PROMPT).toContain(line);
    }
  });
  // CHROME_SHELL_CONTRACT_LINES、MEDIA_MANIFEST_REDLINE 同款
});
```

它**真实调用**两端的拼装函数，逐行断言每条硬规则同时出现在两个产物里。任何一端漏注入（比如有人重构时删掉了数组里的一项）立刻红，且红到具体常量。

**(c) 双态/结构断言**（`workspace-system-prompt.test.ts`）——锁条件逻辑的每个分支。代表性的 CMS 三连（:136-195）：

```ts
// 绑定 CMS：两段都在
const prompt = buildWorkspaceSystemPrompt(true, "en", "cms_site_123");
expect(prompt).toContain("[Dynamic data (CMS)]");
expect(prompt).toContain("Available skills (load with the load_skill tool):");

// 未绑定：always-on 索引在，CMS wrapper 不在
expect(prompt).not.toContain("[Dynamic data (CMS)]");

// 索引头只出现一次 + 顺序：索引段在 CMS 段之前
expect(prompt.split("Available skills (...):").length - 1).toBe(1);
expect(prompt.indexOf("Available skills")).toBeLessThan(prompt.indexOf("[Dynamic data (CMS)]"));
```

细节亮点（:168-171 注释）：未绑定态**不能**断言 `connect_dynamic_collection` 缺席——这个词逐字出现在 skill 索引行的 description 里，非 CMS prompt 也含它。断言粒度必须精确到"wrapper 标记"而不是"关键词"。写守卫测试的功力就在这种地方。

另外注意很多用例的注释直接引用**真实 run 事故**（"真实 run 教训：该规则缺位时 LLM 把访客 JSX 直接写进新建 page.tsx…"）——每条守卫背后是一次真实翻车，测试是事故的疫苗。

## 2. 动手实践（旗舰实验，全流程已实机验证）

### 2.0 基线：确认守卫全绿

仓库根运行：

```bash
pnpm vitest run apps/agent/src/agents/workspace/workspace-domain-contract.test.ts apps/agent/src/agents/workspace/workspace-system-prompt.test.ts
```

实测输出：

```
 ✓ apps/agent/src/agents/workspace/workspace-domain-contract.test.ts (13 tests) 3ms
 ✓ apps/agent/src/agents/workspace/workspace-system-prompt.test.ts (14 tests) 13ms
 Test Files  2 passed (2)
      Tests  27 passed (27)
```

### 2.1 实验 A：改红线一个词 → 措辞锁变红

编辑 `apps/agent/src/agents/workspace/workspace-domain-contract.ts` 第 92 行，把 `NEVER create` 改成 `Never create`（就改这一个词），然后重跑：

```bash
pnpm vitest run apps/agent/src/agents/workspace/workspace-domain-contract.test.ts
```

实测结果——**13 个测试里精准红了 1 个**，且直指措辞锁：

```
 ❯ workspace-domain-contract.test.ts (13 tests | 1 failed)
   × MEDIA_MANIFEST_REDLINE > 媒体清单系统文件禁手改，改图走 media_requests
     → expected 'The media manifest lib/generated/medi…' to contain 'NEVER'
```

**关键观察**：双端一致性守卫（那三个"同时在首轮…与迭代 prompt"用例）**仍然是绿的**——因为两端引用的是同一个常量，常量改了两端跟着一起改，一致性没破坏。红的只有内容锁。两类守卫各管各的失效模式。

恢复现场：

```bash
git checkout -- apps/agent/src/agents/workspace/workspace-domain-contract.ts
git status --short   # 确认无残留改动
```

### 2.2 实验 B：模拟"一端漏注入" → 双端守卫变红

这次不改常量，改**消费端**：编辑 `apps/agent/src/agents/workspace/workspace-websocket.service.ts`，在 `buildWorkspaceSystemPrompt` 的拼装数组里（约 :8887）删掉 `MEDIA_MANIFEST_REDLINE,` 这一行（模拟重构时手滑漏掉一项）。重跑同一测试，实测：

```
 ❯ workspace-domain-contract.test.ts (13 tests | 1 failed)
   × Tier 1 硬规则常量首轮+迭代双向下沉一致性（防漂移单一守卫）
     > MEDIA_MANIFEST_REDLINE 同时在首轮模板契约与迭代 prompt
     → expected 'You are an expert frontend engineer i…' to contain 'The media manifest lib/generated/medi…'
```

这次红的是**双端一致性守卫**（措辞锁仍绿——常量本身没变）。对照实验 A：同一份测试文件，两种不同的破坏方式，各自被对应的守卫接住。

**附赠观察**：这次失败输出会把**完整拼装后的迭代 system prompt** 整段打印出来（vitest 的 diff 展示 actual 值）——这是免费的"看最终产物"机会，你能看到 1.2 节的分层顺序在真实产物里的样子：身份句 → 三红线 → 表单契约 → CSS/路由契约 → chrome 契约 → 语言双行 → Decision rules → 拒绝模板 → 自检行。

恢复现场并复验：

```bash
git checkout -- apps/agent/src/agents/workspace/workspace-websocket.service.ts
git status --short
pnpm vitest run apps/agent/src/agents/workspace/workspace-domain-contract.test.ts
# 实测：Tests  13 passed (13)
```

### 2.3 实验 C：打印四种分桶的 prompt 差异（自由探索）

写个临时脚本（放任意目录，参考第 1 站实践 A 的方式运行）：

```ts
import { buildWorkspaceSystemPrompt } from "/Users/a114514/ce_repos/vcp/apps/agent/src/agents/workspace/workspace-websocket.service.ts";

const a = buildWorkspaceSystemPrompt(true, "en", null);
const b = buildWorkspaceSystemPrompt(true, "en", "cms_site_123");
console.log("无 CMS 长度:", a.length, "有 CMS 长度:", b.length);
console.log("差异段:", b.slice(a.indexOf("Available skills")));
```

对比：CMS 段追加了什么？两个不同的 `cmsSiteId` 值（`"cms_a"` vs `"cms_b"`）产出的 prompt 是否**字节一致**？（应当一致——这就是"值不进段落"。）

## 3. 自测题

1. 什么样的规则才有资格进 Tier 1 常量常驻 system prompt？不够格的去哪了？
2. 四个函数参数为什么被称为"缓存分桶键"？多加一个参数的代价是什么？
3. 实验 A 和实验 B 分别触发了哪类守卫？为什么实验 A 里双端一致性守卫不红？
4. CMS 段"内容参数化但值不进段落"具体避免了什么？
5. 为什么未绑定 CMS 的断言不能写 `expect(prompt).not.toContain("connect_dynamic_collection")`？

## 4. 与下一站的衔接

本站看到 `cacheableSystem` 给 system 打了断点、参数分桶保住了 system 的字节一致性——但 system 只是缓存前缀的开头。多轮迭代里真正贵的是**messages 数组**：折叠的历史、每轮的注入块，在工具循环里每个 step 都会重发。断点该打在 messages 的哪两条消息上、并发 fan-out 时怎么避免缓存踩踏，是第 5 站（缓存断点与成本工程）的内容。

---

## 自测题答案

1. "违反就坏、跨轮必须常驻"的断言式硬规则（安全、写入协议、结构契约）。"怎么做更好"的设计 how-to 是 Tier 3 skill（`skills/page-editing/*`），按需 `load_skill` 加载——常驻位是稀缺的 token 预算，准入标准写在 `workspace-domain-contract.ts:1-15` 的文件注释里。
2. 参数组合唯一决定 prompt 字节内容：相同组合 → 相同字符串 → 命中同一 Anthropic 缓存前缀。每加一个参数，缓存桶数按该参数的取值数相乘；参数失控 = 缓存碎片化。
3. 实验 A（改常量措辞）红的是措辞锁；双端守卫不红，因为两端引用同一常量、同步变化，一致性未破坏。实验 B（消费端漏注入）红的是双端一致性守卫；措辞锁不红，因为常量本身未变。两类守卫正交，各接住一种失效模式。
4. 避免缓存按站点分裂。段内含 id 则每个站点的 system prompt 字节都不同，缓存桶数 = 站点数、命中率趋零；不含 id 则所有绑定 CMS 的站点共享同一段字节。
5. 因为这个词逐字出现在 skill 索引行（`- webhub-collections: <description>`）的 description 里，而索引段是无条件 always-on 的——非 CMS prompt 也包含该词，这样断言会误红。必须改判 wrapper 标记 `[Dynamic data (CMS)]` 的缺席（`workspace-system-prompt.test.ts:168-173` 的注释记录了这个坑）。
