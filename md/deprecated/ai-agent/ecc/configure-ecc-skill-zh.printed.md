# Configure ECC 技能中文翻译

> 原文：`everything-claude-code/skills/configure-ecc/SKILL.md`

---

```yaml
name: configure-ecc
description: Everything Claude Code 的交互式安装向导 — 引导用户选择并安装技能和规则到用户级或项目级目录，验证路径，并可选优化已安装文件。
origin: ECC
```

# 配置 Everything Claude Code (ECC)

一个交互式、分步安装向导，用于 Everything Claude Code 项目。使用 `AskUserQuestion` 引导用户有选择地安装技能和规则，随后验证正确性并提供优化选项。

## 何时激活

- 用户说"配置 ecc"、"安装 ecc"、"设置 everything claude code"或类似表述
- 用户想从本项目中有选择地安装技能或规则
- 用户想验证或修复现有的 ECC 安装
- 用户想为其项目优化已安装的技能或规则

## 前提条件

此技能必须在激活前对 Claude Code 可访问。两种引导方式：
1. **通过插件**：`/plugin install ecc@ecc` — 插件会自动加载此技能
2. **手动方式**：仅将此技能复制到 `~/.claude/skills/configure-ecc/SKILL.md`，然后说"配置 ecc"来激活

---

## 第 0 步：克隆 ECC 仓库

在任何安装操作之前，将最新 ECC 源码克隆到 `/tmp`：

```bash
rm -rf /tmp/everything-claude-code
git clone https://github.com/affaan-m/everything-claude-code.git /tmp/everything-claude-code
```

将 `ECC_ROOT=/tmp/everything-claude-code` 设为后续所有复制操作的源路径。

如果克隆失败（网络问题等），使用 `AskUserQuestion` 请用户提供现有 ECC 克隆的本地路径。

---

## 第 1 步：选择安装级别

使用 `AskUserQuestion` 询问用户安装位置：

```
问题："ECC 组件应安装到哪里？"
选项：
  - "用户级 (~/.claude/)" — "适用于你所有的 Claude Code 项目"
  - "项目级 (.claude/)" — "仅适用于当前项目"
  - "两者都装" — "通用/共享项目装用户级，项目特定内容装项目级"
```

将选择存储为 `INSTALL_LEVEL`。设置目标目录：
- 用户级：`TARGET=~/.claude`
- 项目级：`TARGET=.claude`（相对于当前项目根目录）
- 两者：`TARGET_USER=~/.claude`，`TARGET_PROJECT=.claude`

如目标目录不存在则创建：
```bash
mkdir -p $TARGET/skills $TARGET/rules
```

---

## 第 2 步：选择并安装技能

### 2a：选择范围（核心 vs 细分领域）

默认选择**核心（推荐新用户使用）**— 复制 `.agents/skills/*` 加上 `skills/search-first/` 以启用研究优先工作流。此套件涵盖工程、评估、验证、安全、策略性上下文压缩、前端设计，以及 Anthropic 跨职能技能（文章写作、内容引擎、市场研究、前端幻灯片）。

使用 `AskUserQuestion`（单选）：
```
问题："仅安装核心技能，还是包含细分领域/框架包？"
选项：
  - "仅核心（推荐）" — "TDD、E2E、评估、验证、研究优先、安全、前端模式、上下文压缩、跨职能 Anthropic 技能"
  - "核心 + 选定细分领域" — "在核心基础上添加框架/领域特定技能"
  - "仅细分领域" — "跳过核心，安装特定框架/领域技能"
默认：仅核心
```

如果用户选择细分领域或核心 + 细分领域，继续下方的分类选择，仅包含用户选择的细分领域技能。

### 2b：选择技能分类

以下有 7 个可选分类组。后续的详细确认列表涵盖 8 个分类共 45 个技能，外加 1 个独立模板。使用 `AskUserQuestion` 并启用 `multiSelect: true`：

```
问题："你想安装哪些技能分类？"
选项：
  - "框架与语言" — "Django、Laravel、Spring Boot、Go、Python、Java、前端、后端模式"
  - "数据库" — "PostgreSQL、ClickHouse、JPA/Hibernate 模式"
  - "工作流与质量" — "TDD、验证、学习、安全审查、上下文压缩"
  - "研究与 API" — "深度研究、Exa 搜索、Claude API 模式"
  - "社交与内容分发" — "X/Twitter API、跨平台发布（配合内容引擎）"
  - "媒体生成" — "fal.ai 图片/视频/音频（配合 VideoDB）"
  - "编排" — "dmux 多代理工作流"
  - "全部技能" — "安装所有可用技能"
```

### 2c：确认具体技能

对于每个已选分类，打印下方完整技能列表并请用户确认或取消选择特定项。如列表超过 4 项，以文本形式打印列表，并使用 `AskUserQuestion` 提供"安装全部列出的"选项加上"其他"选项让用户粘贴特定名称。

**分类：框架与语言（21 个技能）**

| 技能 | 描述 |
|------|------|
| `backend-patterns` | 后端架构、API 设计、Node.js/Express/Next.js 服务端最佳实践 |
| `coding-standards` | TypeScript、JavaScript、React、Node.js 通用编码标准 |
| `django-patterns` | Django 架构、DRF REST API、ORM、缓存、信号、中间件 |
| `django-security` | Django 安全：认证、CSRF、SQL 注入、XSS 防护 |
| `django-tdd` | Django 测试：pytest-django、factory_boy、模拟、覆盖率 |
| `django-verification` | Django 验证循环：迁移、静态检查、测试、安全扫描 |
| `laravel-patterns` | Laravel 架构模式：路由、控制器、Eloquent、队列、缓存 |
| `laravel-security` | Laravel 安全：认证、策略、CSRF、批量赋值、频率限制 |
| `laravel-tdd` | Laravel 测试：PHPUnit 和 Pest、工厂、假对象、覆盖率 |
| `laravel-verification` | Laravel 验证：静态检查、静态分析、测试、安全扫描 |
| `frontend-patterns` | React、Next.js、状态管理、性能、UI 模式 |
| `frontend-slides` | 零依赖 HTML 演示文稿、风格预览、PPTX 转 Web |
| `golang-patterns` | 地道的 Go 模式、构建健壮 Go 应用的惯例 |
| `golang-testing` | Go 测试：表驱动测试、子测试、基准测试、模糊测试 |
| `java-coding-standards` | Spring Boot 的 Java 编码标准：命名、不可变性、Optional、流 |
| `python-patterns` | Pythonic 习语、PEP 8、类型提示、最佳实践 |
| `python-testing` | Python 测试：pytest、TDD、夹具、模拟、参数化 |
| `springboot-patterns` | Spring Boot 架构、REST API、分层服务、缓存、异步 |
| `springboot-security` | Spring Security：认证/授权、验证、CSRF、密钥、频率限制 |
| `springboot-tdd` | Spring Boot TDD：JUnit 5、Mockito、MockMvc、Testcontainers |
| `springboot-verification` | Spring Boot 验证：构建、静态分析、测试、安全扫描 |

**分类：数据库（3 个技能）**

| 技能 | 描述 |
|------|------|
| `clickhouse-io` | ClickHouse 模式、查询优化、分析、数据工程 |
| `jpa-patterns` | JPA/Hibernate 实体设计、关联关系、查询优化、事务 |
| `postgres-patterns` | PostgreSQL 查询优化、模式设计、索引、安全 |

**分类：工作流与质量（8 个技能）**

| 技能 | 描述 |
|------|------|
| `continuous-learning` | 旧版 v1 Stop-hook 会话模式提取；新安装建议使用 `continuous-learning-v2` |
| `continuous-learning-v2` | 基于直觉的学习系统，带置信度评分，可演化为技能、代理和可选的旧版命令垫片 |
| `eval-harness` | 评估驱动开发（EDD）的正式评估框架 |
| `iterative-retrieval` | 用于解决子代理上下文问题的渐进式上下文细化 |
| `security-review` | 安全检查清单：认证、输入、密钥、API、支付功能 |
| `strategic-compact` | 在逻辑间歇点建议手动上下文压缩 |
| `tdd-workflow` | 强制 TDD 并确保 80%+ 覆盖率：单元、集成、E2E |
| `verification-loop` | 验证和质量循环模式 |

**分类：商业与内容（5 个技能）**

| 技能 | 描述 |
|------|------|
| `article-writing` | 使用提供的文风，基于笔记、示例或源文档进行长文写作 |
| `content-engine` | 多平台社交内容、脚本和内容复用工作流 |
| `market-research` | 带来源标注的市场、竞品、基金和技术研究 |
| `investor-materials` | 路演幻灯片、单页概要、投资人备忘录和财务模型 |
| `investor-outreach` | 个性化投资人冷邮件、热推荐和跟进邮件 |

**分类：研究与 API（3 个技能）**

| 技能 | 描述 |
|------|------|
| `deep-research` | 使用 firecrawl 和 exa MCP 的多源深度研究，附引用报告 |
| `exa-search` | 通过 Exa MCP 进行神经搜索，覆盖网页、代码、公司和人物研究 |
| `claude-api` | Anthropic Claude API 模式：消息、流式传输、工具调用、视觉、批处理、Agent SDK |

**分类：社交与内容分发（2 个技能）**

| 技能 | 描述 |
|------|------|
| `x-api` | X/Twitter API 集成：发帖、线程、搜索和分析 |
| `crosspost` | 多平台内容分发，按平台原生风格适配 |

**分类：媒体生成（2 个技能）**

| 技能 | 描述 |
|------|------|
| `fal-ai-media` | 通过 fal.ai MCP 统一 AI 媒体生成（图片、视频、音频） |
| `video-editing` | AI 辅助视频编辑：剪辑、结构编排和素材增强 |

**分类：编排（1 个技能）**

| 技能 | 描述 |
|------|------|
| `dmux-workflows` | 使用 dmux 进行多代理编排，实现并行代理会话 |

**独立项**

| 技能 | 描述 |
|------|------|
| `docs/examples/project-guidelines-template.md` | 用于创建项目专属技能的模板 |

### 2d：执行安装

对于每个已选技能，复制整个技能目录：
```bash
cp -r $ECC_ROOT/skills/<技能名称> $TARGET/skills/
```

注意：`continuous-learning` 和 `continuous-learning-v2` 有额外文件（config.json、hooks、scripts）— 确保复制整个目录，而不仅仅是 SKILL.md。

---

## 第 3 步：选择并安装规则

使用 `AskUserQuestion` 并启用 `multiSelect: true`：

```
问题："你想安装哪些规则集？"
选项：
  - "通用规则（推荐）" — "语言无关的通用原则：编码风格、Git 工作流、测试、安全等（8 个文件）"
  - "TypeScript/JavaScript" — "TS/JS 模式、钩子、Playwright 测试（5 个文件）"
  - "Python" — "Python 模式、pytest、black/ruff 格式化（5 个文件）"
  - "Go" — "Go 模式、表驱动测试、gofmt/staticcheck（5 个文件）"
```

执行安装：
```bash
# 通用规则（平铺复制到 rules/）
cp -r $ECC_ROOT/rules/common/* $TARGET/rules/

# 语言特定规则（平铺复制到 rules/）
cp -r $ECC_ROOT/rules/typescript/* $TARGET/rules/   # 如已选择
cp -r $ECC_ROOT/rules/python/* $TARGET/rules/        # 如已选择
cp -r $ECC_ROOT/rules/golang/* $TARGET/rules/        # 如已选择
```

**重要提示**：如果用户选择了任何语言特定规则但**未选择**通用规则，需警告：
> "语言特定规则是对通用规则的扩展。不安装通用规则可能导致覆盖不完整。是否也安装通用规则？"

---

## 第 4 步：安装后验证

安装完成后，执行以下自动检查：

### 4a：验证文件存在

列出所有已安装文件并确认它们存在于目标位置：
```bash
ls -la $TARGET/skills/
ls -la $TARGET/rules/
```

### 4b：检查路径引用

扫描所有已安装的 `.md` 文件中的路径引用：
```bash
grep -rn "~/.claude/" $TARGET/skills/ $TARGET/rules/
grep -rn "../common/" $TARGET/rules/
grep -rn "skills/" $TARGET/skills/
```

**对于项目级安装**，标记所有引用 `~/.claude/` 路径的内容：
- 如果技能引用 `~/.claude/settings.json` — 通常没问题（设置始终是用户级的）
- 如果技能引用 `~/.claude/skills/` 或 `~/.claude/rules/` — 如果仅安装在项目级，这可能会失效
- 如果技能通过名称引用另一个技能 — 检查被引用的技能是否也已安装

### 4c：检查技能间的交叉引用

一些技能会引用其他技能。验证以下依赖关系：
- `django-tdd` 可能引用 `django-patterns`
- `laravel-tdd` 可能引用 `laravel-patterns`
- `springboot-tdd` 可能引用 `springboot-patterns`
- `continuous-learning-v2` 引用 `~/.claude/homunculus/` 目录
- `python-testing` 可能引用 `python-patterns`
- `golang-testing` 可能引用 `golang-patterns`
- `crosspost` 引用 `content-engine` 和 `x-api`
- `deep-research` 引用 `exa-search`（互补的 MCP 工具）
- `fal-ai-media` 引用 `videodb`（互补的媒体技能）
- `x-api` 引用 `content-engine` 和 `crosspost`
- 语言特定规则引用 `common/` 对应文件

### 4d：报告问题

对于发现的每个问题，报告：
1. **文件**：包含问题引用的文件
2. **行号**：行号
3. **问题**：出了什么问题（例如："引用了 ~/.claude/skills/python-patterns 但 python-patterns 未安装"）
4. **建议修复**：应如何处理（例如："安装 python-patterns 技能"或"将路径更新为 .claude/skills/"）

---

## 第 5 步：优化已安装文件（可选）

使用 `AskUserQuestion`：

```
问题："是否要为你的项目优化已安装的文件？"
选项：
  - "优化技能" — "移除无关章节、调整路径、根据你的技术栈定制"
  - "优化规则" — "调整覆盖率目标、添加项目特定模式、自定义工具配置"
  - "两者都优化" — "对所有已安装文件进行全面优化"
  - "跳过" — "保持原样"
```

### 如果优化技能：
1. 读取每个已安装的 SKILL.md
2. 询问用户项目的技术栈（如尚未知晓）
3. 对每个技能，建议移除无关章节
4. 在安装目标位置就地编辑 SKILL.md 文件（**不是**源仓库）
5. 修复第 4 步中发现的任何路径问题

### 如果优化规则：
1. 读取每个已安装的规则 .md 文件
2. 询问用户的偏好：
   - 测试覆盖率目标（默认 80%）
   - 首选格式化工具
   - Git 工作流惯例
   - 安全要求
3. 在安装目标位置就地编辑规则文件

**关键提示**：只修改安装目标（`$TARGET/`）中的文件，**绝不**修改源 ECC 仓库（`$ECC_ROOT/`）中的文件。

---

## 第 6 步：安装摘要

清理 `/tmp` 中克隆的仓库：

```bash
rm -rf /tmp/everything-claude-code
```

然后打印摘要报告：

```
## ECC 安装完成

### 安装目标
- 级别：[用户级 / 项目级 / 两者都有]
- 路径：[目标路径]

### 已安装技能（[数量]）
- 技能1、技能2、技能3……

### 已安装规则（[数量]）
- 通用（8 个文件）
- TypeScript（5 个文件）
- ……

### 验证结果
- 发现 [数量] 个问题，已修复 [数量] 个
- [列出剩余问题]

### 已应用的优化
- [列出所做更改，或"无"]
```

---

## 故障排除

### "技能未被 Claude Code 识别"
- 确认技能目录包含 `SKILL.md` 文件（不是散落的 .md 文件）
- 用户级：检查 `~/.claude/skills/<技能名称>/SKILL.md` 是否存在
- 项目级：检查 `.claude/skills/<技能名称>/SKILL.md` 是否存在

### "规则不生效"
- 规则是平铺文件，不在子目录中：`$TARGET/rules/coding-style.md`（正确）vs `$TARGET/rules/common/coding-style.md`（平铺安装时不正确）
- 安装规则后需重启 Claude Code

### "项目级安装后出现路径引用错误"
- 一些技能默认使用 `~/.claude/` 路径。运行第 4 步验证来查找并修复这些问题。
- 对于 `continuous-learning-v2`，`~/.claude/homunculus/` 目录始终是用户级的 — 这是预期行为，不是错误。
