# VCP 上下文工程 · 第 3 站：skill 系统——索引常驻 + 按需加载 + 跨轮补偿

> 代码仓库：`~/ce_repos/vcp`（下文路径相对仓库根）；本文自包含，含关键代码摘录，无需对话历史即可学习。
> 环境要求：Node 24（可 `nvm use 24`）+ `pnpm install --frozen-lockfile` 已执行。
> 本文所有命令均已在 2026-07-09 实际验证通过。

## 0. 本站要解决的问题

Workspace agent 需要大量"领域 how-to"知识：动效怎么加、移动端怎么修、SEO 怎么写、CMS 集合怎么接……仓库里有 13 个 `SKILL.md`，每个正文约 900 词。如果全部塞进 system prompt：

1. **token 成本爆炸**：每轮迭代、每个 step 都重发上万 token 的 how-to，而单次任务通常只用得上其中一个；
2. **淹没硬规则**：真正"违反就坏"的红线（第 4 站的 Tier 1 常量）会被大段 how-to 稀释，模型注意力被摊薄；
3. **知识更新僵化**：改一个 skill 就得改 prompt 拼装代码。

VCP 的解法是 **Claude Code 范式**的完整复刻，三段式：

| 段 | 做什么 | 解决什么 |
|---|---|---|
| **索引常驻** | system prompt 里每个 skill 只占一行 `- <name>: <description>` | 模型永远"知道有什么可用"，成本只有几百 token |
| **全文按需** | 模型调 `load_skill` 工具，全文进入**本轮**上下文 | 只为命中的任务付全文成本 |
| **跨轮补偿** | 全文不落库；下一轮从磁盘**重读**并注入 | 持久层不膨胀，模型跨轮也不"失忆" |

## 1. 核心代码导读（按数据流顺序）

### 1.1 知识的载体：SKILL.md 的写法

`skills/page-editing/motion-and-scroll/SKILL.md:1-5`：

```markdown
---
name: motion-and-scroll
description: Add, intensify, or calm down animation and scroll motion on a generated site — entrance reveals, hover lift, parallax, staggered grids, count-up stat numbers, pinned/horizontal scroll moments. Use when the page feels flat, too plain, or generic, when the user wants it to feel more modern, polished, or impactful, wants elements to move or reveal as the visitor scrolls, wants stat numbers to count up, or asks for parallax. Do NOT use for CMS data, forms, or copywriting.
model_invocable: true
---
```

三个要点：

- **frontmatter 只有三件事**：`name`（索引键）、`description`（触发判据）、`model_invocable: true`（准入开关）。
- **description 是写给模型做匹配判断的**，所以它是一段长触发句，固定套路：`能做什么 — 具体场景枚举。Use when <正向触发，含用户的口语措辞如 "feels flat / too plain">。Do NOT use for <反向排除>`。正反向都写，是为了防止模型拿着锤子找钉子。
- **正文是 how-to**（`## When to use`、操作规范、禁手），不进索引，只在 load 后可见。

### 1.2 读取层：`FsSkillSource`

`apps/agent/src/knowledge/skills/fs-skill-source.ts`。

**根目录三级解析**（`defaultSkillsRoot()` :18-30）：`VCP_SKILLS_ROOT` 环境变量 → 从 cwd 向上找含 `pnpm-workspace.yaml` 的仓库根拼 `/skills` → 兜底 `<cwd>/skills`。为容器部署（skills 拍平到非仓库根）留了显式指路口。

**准入语义严格**（`parseFrontmatter` :133）：

```ts
if (parsed.model_invocable === true) out.modelInvocable = true;
```

只有字面量 `true` 才进按需加载索引——缺失、`"true"` 字符串、`1` 都不算。首轮生成专用的 page-generation skill 不标这个字段，所以不会暴露给迭代循环。

**索引扫描：缓存 + fail-soft**（`listModelInvocableSkills()` :181-198）：

```ts
listModelInvocableSkills(): ModelInvocableSkill[] {
  if (this.cachedModelInvocable !== null) return this.cachedModelInvocable;
  const skills: ModelInvocableSkill[] = [];
  this.walkSkillFiles((category, raw) => {
    try {
      const fm = parseFrontmatter(raw);
      if (fm.modelInvocable === true) {
        skills.push({ name: fm.name, category, description: fm.description });
      }
    } catch {
      // fail-soft：跳过损坏文件，剩余 skill 照常入列。
    }
  });
  this.cachedModelInvocable = skills;
  return skills;
}
```

两个刻意的设计：**进程级 lazy 缓存**（首次扫盘、后续零 IO，skill 文件不热更新）；**单文件损坏跳过**。对比同文件 `readSkillFiles()`（:155-173，全量目录读，损坏**直接抛错**）——同一份数据两条路径容错策略不同：索引/加载路径服务模型迭代，绝不允许一个坏文件阻断整个 agent；全量路径服务平台功能，坏文件必须炸出来修。

**路径守卫**（`readSkill` :200-211）：

```ts
if (!/^[a-z0-9-]+$/.test(category) || !/^[a-z0-9-]+$/.test(name)) {
  return "";
}
```

category/name 只允许 kebab-case——skill 名是模型给的输入，这层闸门杜绝 `../` 路径穿越把任意文件读进 prompt（纵深防御：上游还有 catalog 白名单校验）。

### 1.3 索引注入 system prompt

`apps/agent/src/agents/workspace/cms-dynamic-data-guide.ts:55-80`，`buildSkillIndexSection()`：

```ts
skillLines = this.skillSource
  .listModelInvocableSkills()
  .map((s) => `- ${s.name}: ${s.description}`);
// ...
this.cachedIndexSection = `\n\n${[
  SKILL_INDEX_HEADER,      // "Available skills (load with the load_skill tool):"
  ...skillLines,
  SKILL_BLOCKING_LINE,     // "...this is a BLOCKING REQUIREMENT: load it with load_skill BEFORE doing the work it covers."
].join("\n")}`;
```

- **无条件注入**（Tier 2 always-on）：与站点是否绑定 CMS、用户语言完全无关；拼接点在 `workspace-websocket.service.ts:8937`。
- **动态清单**：新增一个 SKILL.md 文件，自动入列，不用改任何注册代码（下面实验一验证）。
- **fail-soft 降级**：目录读失败/清单为空 → 注入空串 + `warn` 一次（:67-73），索引缺失不阻断迭代。
- 同文件的 `buildSection(cmsSiteId)`（:87-92）是另一段（CMS 硬规则），只在绑定 CMS 时注入——注意它**不含 skill 索引**，两段解耦。

### 1.4 按需加载：`load_skill` 工具

`apps/agent/src/agents/workspace/tools/load-skill.tool.ts`。

**返回结构是整个 transient 机制的锚点**（:26-35）：

```ts
/**
 * `summary` 走 summarizeWorkspaceToolResult → tool.finished.result_summary：
 * 前端 timeline 可见，且是跨 turn 回放唯一存留（build-model-messages 折叠
 * tool 结果只剩 result_summary）——skill 全文天然 transient，不膨胀后续轮次。
 * `content` 是本 turn 模型可见的 skill 全文（成功）或软错误指引（失败）。
 */
export interface LoadSkillResult {
  summary: string;   // → 落库："Launching skill: <name>"
  content: string;   // → 只活在本轮：skill 全文
}
```

**软错误全家桶**（全程不抛错，每种失败都返回带指引的 `{summary, content}`）：

| 失败场景 | summary | content 给模型的指引 |
|---|---|---|
| 目录读失败 (:78-88) | `load_skill failed: skill catalog unavailable` | 继续干活，遵守 system prompt 既有规则 |
| 未知名 (:94-99) | `...unknown skill "X"` | 附完整可用清单 |
| 多匹配歧义 (:101-109) | `...ambiguous skill "X"` | 要求用 `category/name` 形式重调 |
| 正文读失败/为空 (:127-132) | `...could not be read` | 继续干活，不带 skill |

**正文缓存只缓存成功**（:123-124）：`if (body !== "") cache.set(key, body)` ——瞬时 IO 失败不会被永久钉死成"这个 skill 读不到"。

**producer/consumer 共享前缀常量**（:13-18）：

```ts
export const LOADING_SKILL_SUMMARY_PREFIX = "Launching skill: ";
```

这行摘要是跨轮回放后**唯一存留**的"已加载哪个 skill"信号。producer（本工具 :135）与 consumer（下节的 `collectLoadedSkillNames`）import 同一个常量——如果两边各写各的字符串，某次改文案（比如改成 `Loaded skill: `）只改了一边，跨轮重注入就会**静默失效**：不报错、不告警，只是模型悄悄失去 skill 记忆。共享常量把这种"格式漂移事故"消灭在编译期。

### 1.5 跨轮补偿：`workspace-loaded-skills.ts`

先看根因（文件头注释 :7-18 写得很清楚）：

> load_skill 的正文是 per-turn transient——成功结果只把 `Launching skill: <name>` 落进 result_summary，跨轮折叠后正文消失，**模型看到历史里"已 launch"就以为装备齐全、跳过重载**，于是在无 skill 指引下编辑。

补偿三步：

**① 识别**（`collectLoadedSkillNames` :64-78）：从折叠用 events 尾部向前扫 `load_skill` 的 `tool.finished`，按前缀常量解析 skill 名，去重、最近优先。加载失败的（summary 非该前缀）不计入。

**② fresh 重读 + 截断**（`readLoadedSkillBodies` :91-135）：

- **不依赖有损的事件持久化**，按名从 `FsSkillSource` 重读磁盘正文——磁盘是权威源，落库副本反而会过期；
- 上限：最多 3 个 skill（`DEFAULT_MAX_SKILLS`），每个 8000 字符头部截断（`truncateHead` :132-135，截断时附提示"re-run load_skill to read the full skill"）；
- 品牌改名兼容（:47-50）：`LEGACY_SKILL_NAME_ALIASES` 把历史事件里的旧名 `cms-collections` 映射到新目录 `webhub-collections`——老站点的 agent_events 是不可变历史，兼容只能做在读取端。

**③ 注入**（`injectLoadedSkillsReminder` :142-179）：把正文包成

```
[Loaded skills — already in effect this session]
These skills were already loaded earlier in this session and remain in effect. ...
### Skill: <name>
<body>
[/Loaded skills]
```

前置到**最新一条 user 消息**的首个 text part——不新增 message、不改 turn 结构、**只进内存 messages、绝不回写 agent_events**，所以天然 per-turn transient，不会被下一轮二次折叠。

闭环的最后一块在 system prompt 里（`workspace-websocket.service.ts:8892`）：明确告诉模型这个块的语义——"列在里面的 skill 仍然生效，不要重复 load；**没列在里面**但命中任务的 skill 依然是 BLOCKING 要求，必须先 load"。

### 1.6 一图总结数据流

```
skills/<category>/<name>/SKILL.md          （权威源：磁盘）
        │ 扫盘（进程级缓存、损坏 fail-soft）
        ▼
listModelInvocableSkills() ──► buildSkillIndexSection() ──► system prompt（每 skill 一行，常驻）
        │
        │ 模型判断任务命中索引行 → 调 load_skill
        ▼
{ summary: "Launching skill: X",  content: <全文> }
        │                              │
        │ 落库（唯一存留）              │ 只进本轮上下文
        ▼                              ▼
agent_events.tool.finished        本轮模型照 skill 干活
        │
        │ 下一轮：collectLoadedSkillNames(events) 解析出 "X"
        ▼
readLoadedSkillBodies() 从磁盘 fresh 重读（≤3 个、各 ≤8000 字符）
        │
        ▼
injectLoadedSkillsReminder() 前置注入最新 user 消息（只进内存）
```

## 2. 动手实践（命令均已验证）

前置：Node 24 在 PATH 中；仓库根执行过 `pnpm install --frozen-lockfile`。

### 实验一：亲手驱动索引扫描

在你自己的临时目录（如 `~/tmp`）建脚本 `list-skills.ts`：

```ts
import { FsSkillSource } from "/Users/a114514/ce_repos/vcp/apps/agent/src/knowledge/skills/fs-skill-source.ts";

const source = new FsSkillSource();
const skills = source.listModelInvocableSkills();
console.log(`model_invocable skill 总数: ${skills.length}`);
for (const s of skills) {
  console.log(`- [${s.category}] ${s.name}: ${s.description.slice(0, 80)}...`);
}
```

运行（tsx 是 apps/agent 的 devDependency，要在该目录下 `pnpm exec`）：

```bash
cd ~/ce_repos/vcp/apps/agent && pnpm exec tsx ~/tmp/list-skills.ts
```

实测输出：`model_invocable skill 总数: 7`，两个 `dynamic-data`（webhub-collections/forms）+ 五个 `page-editing`（media/motion/responsive/seo/site-chrome）。注意：`skills/page-generation/` 下的 skill **不在列**——它们没标 `model_invocable: true`，这就是 :133 那行严格判等的效果。

### 实验二：索引是动态扫盘的（新增 skill 零注册）

```bash
# 1. 建临时 skill
mkdir -p ~/ce_repos/vcp/skills/page-editing/my-test-skill
cat > ~/ce_repos/vcp/skills/page-editing/my-test-skill/SKILL.md <<'EOF'
---
name: my-test-skill
description: A temporary experiment skill to verify the index is scanned dynamically from disk. Do NOT use for real work.
model_invocable: true
---

# my-test-skill

This body would be returned by the load_skill tool.
EOF

# 2. 再跑一次实验一的脚本 → 实测：总数 8，my-test-skill 入列
cd ~/ce_repos/vcp/apps/agent && pnpm exec tsx ~/tmp/list-skills.ts | grep -E '总数|my-test'

# 3. 删除并复查 → 实测：总数 7，my-test-skill 消失
rm -rf ~/ce_repos/vcp/skills/page-editing/my-test-skill
cd ~/ce_repos/vcp/apps/agent && pnpm exec tsx ~/tmp/list-skills.ts | grep -E '总数|my-test'
```

**为什么两次运行都能看到变化？** `cachedModelInvocable` 是**进程级**缓存——每次 `tsx` 都是新进程，自然重新扫盘。反过来推论：生产上 agent 进程长驻，新增 skill 要重启进程才生效（文件头注释明说"skill 文件不热更新"）。

**实验后务必确认现场干净**：`git -C ~/ce_repos/vcp status --porcelain` 里不应有 `skills/` 相关条目。

### 实验三：用单测看 fail-soft 路径

```bash
cd ~/ce_repos/vcp && pnpm vitest run \
  apps/agent/src/agents/workspace/workspace-loaded-skills.test.ts \
  apps/agent/src/agents/workspace/tools/load-skill.tool.test.ts \
  apps/agent/src/knowledge/skills/fs-skill-source.test.ts
```

实测：3 个文件 38 个测试全绿，约 0.6s。留意输出里的两行 WARN 日志——

```
WARN [WorkspaceLoadSkillTool] load_skill read failed skill=dynamic-data/webhub-collections: EACCES: permission denied
WARN [WorkspaceLoadSkillTool] load_skill catalog unavailable: boom
```

这不是测试出错，而是测试**故意制造 IO 失败/目录不可用**来验证软错误路径：工具 warn 一声后返回可指引的结果，不抛错。读这两个测试用例（`load-skill.tool.test.ts`）是理解 fail-soft 设计的捷径。

### 实验四（纯阅读）：你来当模型——按 description 判断该 load 哪个 skill

对照 1.3 节索引行（7 个 skill 的 description 全文见 `skills/*/*/SKILL.md` frontmatter），判断以下用户请求各命中哪个 skill：

1. "首页太死板了，能不能滚动的时候让各个板块动起来，数字滚动跳一下"
2. "手机上导航挤成一团，按钮小得点不到"
3. "我想加一个新闻栏目，以后我自己能不断发新文章的那种"

（答案在文末）

## 3. 自测题（先自己答，再看文末答案)

1. skill 全文为什么不落库？下一轮模型还"记得"skill 吗，靠什么？
2. `LOADING_SKILL_SUMMARY_PREFIX` 为什么必须是 producer/consumer 共享常量？不共享会发生什么样的故障（关键词：静默）？
3. `listModelInvocableSkills`（损坏跳过）和 `readSkillFiles`（损坏抛错）为什么容错策略相反？
4. `readLoadedSkillBodies` 为什么设"最多 3 个、每个 8000 字符"上限？截断时为什么要附一句提示？
5. 索引段注入失败（skills 目录读不到）时系统怎么表现？为什么选择这样而不是抛错？
6. 如果把 frontmatter 写成 `model_invocable: "true"`（字符串），这个 skill 会出现在索引里吗？

## 4. 与下一站的衔接

本站反复出现"只落库 `result_summary`""跨轮折叠后正文消失"——这些依赖**第 2 站**讲的事件溯源与 `buildModelMessages` 折叠机制（skill 只是其中一类工具结果的特例）。而索引段拼进 system prompt 的位置与顺序、以及"为什么两段都不含 cms_site_id 值"，在**第 4 站**（system prompt 分层组装）与**第 5 站**（缓存断点：稳定前缀）会合拢成完整图景。

---

## 答案

**实验四**：1 → `motion-and-scroll`（"feels flat"、count-up、scroll motion 全命中正向触发）；2 → `responsive-and-touch`（"squished navigation, tap targets too small"）；3 → `webhub-collections`（"repeating content they can keep adding to... news or blog feed"；注意不是 site-chrome——用户要的是持续发布的内容集合，不是导航结构）。

**自测题**：

1. 磁盘上的 SKILL.md 才是权威源，落库全文=第二事实源（会过期）+ 存储/回放膨胀。模型的"记忆"不靠持久化：下一轮由 `collectLoadedSkillNames` 从摘要识别 → `readLoadedSkillBodies` 磁盘 fresh 重读 → 注入最新 user 消息（只进内存）。
2. 该前缀是跨轮"已加载"信号的唯一编码格式。若不共享，任一边单独改文案后，`parseLoadedSkillName` 解析失败返回 null → 重注入静默失效：无报错、无告警，模型只是悄悄在无 skill 指引下编辑——最难排查的一类故障。
3. 面向的调用方不同：索引/加载路径在模型迭代主链路上，一个坏文件不能拖垮全部 skill（可用性优先）；全量读路径是平台侧功能，坏文件必须尽早炸出来修（正确性优先）。
4. 注入目标是最新 user 消息，无上限会把多 skill 会话的每轮上下文撑爆（3×8000 字符封顶 ≈ 可控常数）；截断提示让模型知道"这是节选、全文可以再 load_skill 拿"，把有损变成模型可行动的显式状态（与第 2 站 stale 占位符同一哲学）。
5. 降级为空串 + warn 一次，迭代照常（fail-soft）。skill 是增强件不是必需品：没有索引模型仍能按 system prompt 硬规则干活；抛错则会把整个 agent 可用性绑在一个知识目录的 IO 上。
6. 不会。`parseFrontmatter` :133 是 `parsed.model_invocable === true` 严格判等，字符串 `"true"` 不满足——宽松真值判断会让 YAML 各种写法（`yes`/`1`）意外把 skill 暴露给模型。
