下面是我们目前统一下来的技术方案汇总。

**总体定位**
`codex-harness-cms` 不是 monorepo，也不是 submodule 管理仓库，而是一个 **AI coding harness / 多仓库开发控制面**。

它负责管理：

```text
AI 行为准则
跨仓库 feature 上下文
需求和契约文档
repo 清单
脚本入口
worktree 工作区
```

业务代码仍然属于各自独立 repo。

**推荐目录结构**

```text
codex-harness-cms/
  AGENTS.md
  README.md
  repos.json

  templates/
    requirements.md
    contracts_api.md

  rules/
  skills/
  hooks/
  subagents/

  scripts/
    harness.mjs
    harness.ps1
    harness.sh

  projects/
    ce-designer/
    ce-site-backend/
    cms-center/

  worktrees/
    template-publish-flow/
      requirements.md
      contracts_api.md
      ce-designer/
      ce-site-backend/
      cms-center/
```

**目录职责**

`projects/`

长期存在的 source clone。

```text
projects/ce-designer
projects/ce-site-backend
projects/cms-center
```

这些目录用于：

```text
保存 repo 的主 clone
fetch / sync 远程分支
创建 git worktree
作为每个 repo 的本地源
```

`worktrees/`

按 feature 聚合的真实开发工作区。

```text
worktrees/<feature-name>/
```

比如：

```text
worktrees/template-publish-flow/
  requirements.md
  contracts_api.md
  ce-designer/
  ce-site-backend/
  cms-center/
```

这里的设计重点是：**feature 文档和代码工作区放在一起**。

`templates/`

只放模板，不放具体 feature 内容。

```text
templates/
  requirements.md
  contracts_api.md
```

创建新 feature 时，脚本从这里复制模板到：

```text
worktrees/<feature>/requirements.md
worktrees/<feature>/contracts_api.md
```

**requirements 和 contracts 的定位**

`requirements.md`

记录这个 feature 为什么做、做什么、涉及哪些 repo、验收标准是什么。

`contracts_api.md`

记录跨 repo 协作边界，比如 API、事件、数据结构、错误码、权限约定。

也就是说：

```text
requirements.md  = 产品/工程目标
contracts_api.md = repo 之间如何对接
```

**Git 追踪策略**

父 harness 仓库应该追踪：

```text
templates/*
worktrees/<feature>/requirements.md
worktrees/<feature>/contracts_api.md
AGENTS.md
repos.json
scripts/*
rules/*
skills/*
hooks/*
subagents/*
```

父 harness 仓库不追踪：

```text
projects/<repo>/
worktrees/<feature>/<repo>/
```

因为这些是独立业务 repo。

`.gitignore` 大概是：

```gitignore
/projects/*

/worktrees/*/*
!/worktrees/*/requirements.md
!/worktrees/*/contracts_api.md
!/worktrees/*/README.md

!/projects/.gitkeep
!/worktrees/.gitkeep
```

**跨平台脚本方案**

不维护两套业务逻辑脚本。

推荐：

```text
scripts/harness.mjs   # 核心逻辑，只写一份
scripts/harness.ps1   # Windows wrapper
scripts/harness.sh    # Linux/macOS wrapper
```

Windows 用：

```powershell
.\scripts\harness.ps1 feature template-publish-flow ce-designer cms-center
```

Linux/macOS 用：

```bash
./scripts/harness.sh feature template-publish-flow ce-designer cms-center
```

底层统一调用：

```bash
node scripts/harness.mjs <command>
```

推荐支持命令：

```text
bootstrap       # clone projects 下缺失的 source repos
sync            # fetch / pull source repos
feature         # 创建 feature workspace 和各 repo worktree
status          # 查看所有 repo 状态
search          # 跨 repo 搜索
clean-worktree  # 清理某个 feature 的 repo worktrees，但保留文档
start-feature   # 启动某个 feature 的联调环境
```

**repos.json**

用它作为 repo 权威清单。

```json
{
  "repos": {
    "ce-designer": {
      "url": "git@github.com:your-org/ce-designer.git",
      "projectPath": "projects/ce-designer",
      "defaultBranch": "main"
    },
    "cms-center": {
      "url": "git@github.com:your-org/cms-center.git",
      "projectPath": "projects/cms-center",
      "defaultBranch": "main"
    }
  }
}
```

worktree 路径由规则生成：

```text
worktrees/<feature-name>/<repo-name>
```

**关于被 ignore 的子 repo**

可以读、可以改、可以跨 repo 工作。

`.gitignore` 只影响 Git 追踪和某些搜索工具默认行为，不代表 Codex 或脚本不能访问。

但有一个注意点：从 harness 根目录直接执行普通搜索时，工具可能跳过 ignored 目录。

所以规则应该写进 `AGENTS.md`：

```text
worktrees/<feature>/<repo> 是有效业务代码根目录。
即使被父仓库 .gitignore 忽略，也必须进入对应 repo 单独读取、搜索、修改和执行 git 命令。
不要只依赖 harness 根目录的 git status 或默认 rg 搜索。
```

必要时搜索要这样做：

```powershell
cd worktrees/template-publish-flow/ce-designer
rg "keyword"
```

或者：

```powershell
rg --no-ignore "keyword" worktrees/template-publish-flow/ce-designer
```

**最终结论**

我们现在的统一方案是：

```text
codex-harness-cms 是控制面
projects/ 放长期 source clone
worktrees/ 按 feature 放开发工作区
worktrees/<feature>/requirements.md 和 contracts_api.md 跟着 feature 走
templates/ 放模板
scripts/ 用 Node 写核心逻辑，ps1/sh 只做跨平台入口
业务 repo 被父仓库 ignore，但仍然可读、可改、可独立 git 操作
```

这个方案的优点是：上下文集中、根目录不臃肿、跨平台可维护、适合多 repo 并行开发，也适合 Codex 这类 coding agent 正确理解和执行。
