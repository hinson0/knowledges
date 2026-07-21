# Codex 前后端开发的 Skills / Plugins / Rules 分层策略

## 触发问题

> 用 Codex 做前后端开发时，不要一上来狂装 skill。正确顺序是：先掌握 Codex 基础工作流，再装官方 curated skills，最后沉淀自己的 Harness skills / rules。

## 关键结论

- **正确顺序**：先掌握 Codex 基础工作流 → 再按需安装官方 curated skills → 最后沉淀自己的 Harness skills / rules。
- **不要全量安装 skills**：skill 列表会占用上下文预算；装太多会导致描述被截断，甚至部分 skills 被省略。
- **skill 是任务工作流说明书**：适合沉淀某类任务怎么做，例如前端实现、修 bug、API 契约、测试验证。
- **plugin 是可安装分发包**：skill 是 authoring format，plugin 是 installable distribution unit；一个 plugin 可以包含多个 skills、app integrations、MCP servers。
- **Rules / AGENTS.md 是项目长期约束**：适合放永远生效的工程纪律，例如 worktree、测试、依赖、安全、分支规范。
- **真正值钱的是自己的工程闭环**：官方 skill 提供工具能力；自己的 Harness skill 规定“怎么干活”。

## 三个概念

### Skill：工作流说明书

Codex skill 用来给 Codex 增加特定任务能力。一个 skill 本质是一个目录，里面有 `SKILL.md`，也可以带脚本、参考资料、模板等。Codex 会在任务匹配时加载它。

示例结构：

```text
frontend-implementation/
  SKILL.md
  references/
  scripts/
  assets/
```

调用方式：

```text
$skill-name
```

也可以让 Codex 根据 skill description 自动触发。CLI / IDE 里可以用 `/skills` 或输入 `$` mention 一个 skill。

### Plugin：可安装包

官方区分：

```text
skill  = authoring format
plugin = installable distribution unit
```

也就是说，skill 是写工作流的格式；plugin 是把 skill、app integrations、MCP servers 打包给别人安装的分发单位。

从 Claude Code 迁移时可以这样理解：

```text
Claude Code /skill-name
Codex      $skill-name
```

但 Codex 多了一层：一个 plugin 可以包含多个 skills。

### Rules / AGENTS.md：项目长期约束

Rules 不是某个任务的临时技能，而是项目级工程制度。例如：

```text
不能直接在 master/main 上开发
必须使用 worktree
改后端必须补测试
改 API 必须同步更新前端类型
提交前必须跑 pnpm test / lint
```

这类内容更适合沉淀到：

```text
AGENTS.md
.codex/
docs/harness/
```

一句话判断：

```text
经常触发的任务流程 → skill
永远生效的工程纪律 → AGENTS.md / rules
可分发给团队安装 → plugin
```

## 官方系统 skills

OpenAI `openai/skills` 仓库里：

- `.system`：最新版 Codex 通常会自动安装。
- `.curated` / `.experimental`：可以用 `$skill-installer` 安装。

官方系统 skills 通常不需要手动安装：

```text
imagegen
openai-docs
plugin-creator
skill-creator
skill-installer
```

最常用的是：

```text
$skill-creator     创建自己的 skill
$skill-installer   安装官方 curated / experimental skill
$plugin-creator    把 skill 打包成 plugin
```

## 前后端开发建议安装的官方 curated skills

### 第一批：前后端开发必装

#### `playwright` / `playwright-interactive`

用途：端到端测试、浏览器自动化、验证页面行为。

适合场景：

```text
实现登录页后，让 Codex 用浏览器跑一遍
检查按钮是否可点击
检查 API 返回后页面是否正常渲染
做 E2E 回归
```

建议：

```text
$skill-installer playwright
$skill-installer playwright-interactive
```

原因：没有浏览器验证，Codex 容易“代码看起来写完了”，但页面实际挂了。

#### `screenshot`

用途：让 Codex 看页面截图、对比 UI、检查布局。

适合场景：

```text
页面错位
按钮颜色不对
移动端布局崩了
根据截图修复 UI
```

建议：

```text
$skill-installer screenshot
```

#### `security-best-practices`

用途：基础安全检查。

适合场景：

```text
检查 API 鉴权
检查前端 token 存储
检查 SQL 注入风险
检查敏感信息泄露
检查上传接口安全
```

建议先装：

```text
$skill-installer security-best-practices
```

做正式产品后再考虑：

```text
$skill-installer security-threat-model
```

#### `gh-fix-ci`

用途：修 GitHub Actions / CI。

适合场景：

```text
GitHub Actions 挂了
lint/test/build failed
让 Codex 根据 CI 日志修复
```

建议：

```text
$skill-installer gh-fix-ci
```

#### `gh-address-comments`

用途：处理 GitHub PR review comments。

适合场景：

```text
根据 reviewer comments 批量修改
逐条解决 PR 评论
生成回复说明
```

建议：

```text
$skill-installer gh-address-comments
```

### 第二批：部署相关，按技术栈选择

官方 curated 里有这些部署 skills：

```text
vercel-deploy
netlify-deploy
cloudflare-deploy
render-deploy
```

不要全装，按项目部署平台选：

```text
Next.js / React 前端        → vercel-deploy
纯前端站点                 → netlify-deploy
Cloudflare Pages / Workers → cloudflare-deploy
后端 API / 全栈小服务       → render-deploy
```

前期建议只在 `vercel-deploy` 或 `render-deploy` 中二选一。当前重点是 Harness 工程制度，不是部署平台集邮。

### 第三批：Figma 到前端实现，按需安装

如果当前只有 HTML 原型，而不是 Figma 源文件，可以先不装。

如果后面要从 Figma 到前端代码，建议装：

```text
$skill-installer figma
$skill-installer figma-implement-design
$skill-installer figma-create-design-system-rules
```

相关 Figma skills 还包括：

```text
figma-use
figma-generate-design
figma-code-connect-components
```

## 自己应该沉淀的 Harness skills

目标不是单纯“用 Codex 写代码”，而是建立一套 Codex Harness 工程制度。建议沉淀 8 个项目级 skills。

### `feature-dev`

核心 skill，负责从需求到实现的标准开发流程：

```text
读需求
建分支 / worktree
识别前后端影响范围
制定计划
实现代码
补测试
跑验证
生成变更说明
```

它不只是“写功能”，而应该像 mini 项目经理 + 工程师。

触发词：

```text
开发一个功能
实现 feature
新增页面
新增接口
前后端联调
```

### `bug-fix`

职责：

```text
复现 bug
定位前端 / 后端 / 数据库 / 配置问题
最小改动修复
补回归测试
说明根因
```

它要和 `feature-dev` 分开，因为修 bug 的原则是“少改动、先复现、后修复”，不是大范围重构。

### `api-contract`

前后端开发最容易炸的是 API 契约。

职责：

```text
设计 REST / RPC API
更新 OpenAPI / 类型定义
同步前端 client
检查字段命名
检查错误码
检查鉴权
```

规则可以写死：

```text
后端 API 变更后，必须同步：
1. API 文档
2. 前端类型
3. mock 数据
4. 集成测试
```

### `db-change`

职责：

```text
设计表结构
写 migration
检查索引
检查慢查询风险
检查回滚方案
同步 ORM schema
```

这个适合沉淀数据库慢查询、性能瓶颈、索引设计等经验。

### `frontend-ui`

职责：

```text
根据 HTML 原型实现页面
拆组件
处理状态管理
接 API
做响应式
跑浏览器检查
```

它应该强制配合 `playwright` / `screenshot` 使用。

规则：

```text
实现 UI 后必须启动本地服务
必须用浏览器打开目标页面
必须截图检查布局
不得只凭代码判断完成
```

### `test-and-verify`

职责：

```text
识别应该跑哪些测试
补单测 / 集成测试 / E2E
运行 lint / typecheck / build
整理验证结果
```

这个 skill 可以作为所有开发任务的最后一关。

### `code-review`

职责：

```text
自查 diff
检查安全
检查性能
检查可维护性
检查是否违反 Harness 规则
生成 PR review 风格反馈
```

建议做成严格 gatekeeper。Codex 写完代码后，另起一轮用这个 skill 审查会更稳。

### `harness-governance`

这是“工程制度大脑”，不直接写业务代码，专门维护制度：

```text
维护 AGENTS.md
维护项目开发规范
维护 worktree 规则
维护分支命名规则
维护提交规范
维护前后端目录约束
维护禁止事项
```

## 不要写成 skill 的内容

这些应该写进 `AGENTS.md` 或 rules，作为项目常驻规则：

```text
不能在 master/main 上直接开发
必须使用 feature branch / worktree
每次改动前先看项目结构
不要随意重构无关代码
不要引入未批准的新依赖
前后端接口变更必须同步类型
提交前必须跑 lint/typecheck/test/build
敏感配置不能写入代码
```

## 推荐落地清单

### 立即安装

```bash
$skill-installer playwright
$skill-installer playwright-interactive
$skill-installer screenshot
$skill-installer security-best-practices
$skill-installer gh-fix-ci
$skill-installer gh-address-comments
```

安装后重启 Codex，让新 skills 生效。

### 按部署平台选一个

```bash
$skill-installer vercel-deploy
```

或：

```bash
$skill-installer render-deploy
```

或：

```bash
$skill-installer cloudflare-deploy
```

### 接 Figma 后再装

```bash
$skill-installer figma
$skill-installer figma-implement-design
$skill-installer figma-create-design-system-rules
```

### 自己创建

最终建议：

```text
feature-dev
bug-fix
api-contract
db-change
frontend-ui
test-and-verify
code-review
harness-governance
```

最先做：

```text
feature-dev
frontend-ui
test-and-verify
```

### 最小可落地版本

```text
官方安装：
- playwright
- screenshot
- security-best-practices
- gh-fix-ci

自己创建：
- feature-dev
- frontend-ui
- test-and-verify

项目规则：
- AGENTS.md
```

## 判断

Codex 不是缺 skill，真正缺的是自己的工程闭环。官方 skill 负责工具能力，Harness skill 负责“怎么干活”。两者合起来，才像一套能复用到 A/B/C 项目的制度。

## 关联来源

- [Agent Skills - Codex | OpenAI Developers](https://developers.openai.com/codex/skills)
- [openai/skills: Skills Catalog for Codex](https://github.com/openai/skills)
- [skills/.system](https://github.com/openai/skills/tree/main/skills/.system)
- [skills/.curated](https://github.com/openai/skills/tree/main/skills/.curated)
