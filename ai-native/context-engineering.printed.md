# Context Engineering（上下文工程）

## 定义

**Context Engineering** 是 2024 年下半年在 LLM 工程圈逐渐成型的新领域，可简单定义为：

> 在有限的上下文窗口内，精确地提供 AI 完成任务所需的全部信息——不多不少。

它是 **Prompt Engineering** 的进化版：

- **Prompt Engineering** 关注"**怎么问**"
- **Context Engineering** 关注"**让模型看到什么**"

## 为什么比 Prompt Engineering 更根本

现代 LLM 的能力上限主要不是被"不会提问"限制，而是被两种情况限制：

1. **看不到关键信息**（缺失必要上下文）
2. **被无关信息淹没**（注意力稀释）

即使是 200k / 1M 上下文的模型，塞进去的信息越多，**注意力稀释越严重**——即 **Lost in the Middle** 现象：前半/后半位置的信息会被重点关注，中间的容易被遗忘。

所以 Context Engineering 的核心矛盾是：

> **放进去 vs. 放出来**——什么必须有、什么必须删。

这比"写一个好 prompt"重要一个量级。

## 核心四手段

### 1. 分层加载（Progressive Disclosure）

不一股脑塞所有信息，而是按需加载：

- **总是加载**：系统提示 + CLAUDE.md + 当前对话
- **按需加载**：文档通过 skill 触发、代码通过 Read 工具拉取、API 文档通过 Context7 查询

典型实现：Claude Code 的 skill 机制——skill 的元数据（名字+描述）常驻上下文，body 只在被触发时加载。

### 2. 上下文压缩（Compaction / Summarization）

对话太长时，把早期的交互**总结**成简短摘要，保留结论丢弃过程。

典型实现：

- Claude Code 的 `/compact` 命令
- Anthropic SDK 的 prompt caching 分段缓存
- 定期把"失败尝试+修正结果"压缩成"经验教训"

### 3. 精准检索（RAG / Tool Use）

不把整个代码库塞给模型，而是让模型**按需调用**工具搜索：

- 让模型自己决定要看什么（基于 Grep/Glob/WebSearch 等工具）
- 而不是人类猜它要看什么

这是 Agentic 架构比纯 RAG 更强的根本原因——决策权下放给模型本身。

### 4. 上下文路由（Routing）

不同任务走不同的"上下文配置"：

| 任务类型   | 加载的上下文                 |
| ---------- | ---------------------------- |
| 写代码     | 项目结构 + 相关文件          |
| 回答问题   | 文档 + 历史对话              |
| 重构       | 多文件 + 测试用例            |
| 代码审查   | 变更 diff + 项目约定（CLAUDE.md） |

## 三大反模式

| 反模式               | 问题                                                           |
| -------------------- | -------------------------------------------------------------- |
| **塞进整个仓库**     | 模型注意力稀释，找不到重点，反而性能下降                       |
| **零上下文**         | 只给 "写个登录功能" 这种干巴巴的 prompt，模型只能编造细节      |
| **污染上下文**       | 让失败的尝试、错误的输出留在历史里，模型会被带偏复现这些错误   |

## 实际场景示例（Claude Code 工作流）

使用 Claude Code 的过程处处体现 Context Engineering：

- **CLAUDE.md**（项目约定）→ 让每次对话自动拥有项目背景，无需每次重复
- **`.claude/settings.json` 的 `enabledPlugins`** → 禁用不相关插件，节省 token 给真正有用的 skill
- **smart 插件的 skill 体系** → 把"怎么 commit""怎么推送"这些重复流程封装成 skill，不占用日常对话的 token
- **Read 而非 dump 整个文件** → 用 `offset + limit` 只读相关部分
- **Agent 子任务** → 大型搜索交给 Explore 子 agent，结果汇总回主线，避免把大量搜索结果污染主上下文

## 心智模型：工作记忆 vs. 长期记忆

**把上下文窗口当作"工作记忆"，而不是"长期记忆"：**

- **工作记忆**（上下文窗口）：容量有限、关注度会衰减——所以要不断剔除已用完的信息
- **长期记忆**（外部存储）：CLAUDE.md、memory 文件、文档库、skill references——需要时再调入

优秀的 Context Engineer 像一个认知科学家：**设计信息的流入流出路径**，而不是堆积信息。

## 与 AI Native 的关系

Context Engineering 是 AI Native 工程思维的**核心落地技能**之一。

参见同目录下 [`what-is-ai-native.md`](./what-is-ai-native.md)。
