# Worktrees / 工作树

In the Codex app, worktrees let Codex run multiple independent tasks in the same project without interfering with each other. For Git repositories, [automations](https://developers.openai.com/codex/app/automations) run on dedicated background worktrees so they don't conflict with your ongoing work. In non-version-controlled projects, automations run directly in the project directory. You can also start threads on a worktree manually, and use Handoff to move a thread between Local and Worktree.

在 Codex 应用中，工作树允许 Codex 在同一个项目里同时运行多个相互独立的任务，并且不会彼此干扰。对于 Git 仓库，[自动化任务](https://developers.openai.com/codex/app/automations) 会运行在专用的后台工作树中，因此不会和你当前正在做的工作冲突。在没有版本控制的项目中，自动化任务会直接在项目目录中运行。你也可以手动在某个工作树上启动线程，并使用 Handoff 在线程的 Local 和 Worktree 之间移动。

## What's a worktree / 什么是工作树

Worktrees only work in projects that are part of a Git repository since they use [Git worktrees](https://git-scm.com/docs/git-worktree) under the hood. A worktree allows you to create a second copy ("checkout") of your repository. Each worktree has its own copy of every file in your repo but they all share the same metadata (`.git` folder) about commits, branches, etc. This allows you to check out and work on multiple branches in parallel.

工作树只适用于 Git 仓库中的项目，因为它底层使用的是 [Git worktrees](https://git-scm.com/docs/git-worktree)。工作树允许你为仓库创建第二份副本，也就是一次新的「检出」。每个工作树都有仓库中所有文件的一份独立副本，但它们共享同一套关于提交、分支等信息的元数据，也就是 `.git` 文件夹。这样你就可以并行检出并处理多个分支。

## Terminology / 术语

- **Local checkout**: The repository that you created. Sometimes just referred to as **Local** in the Codex app.
- **Worktree**: A [Git worktree](https://git-scm.com/docs/git-worktree) that was created from your local checkout in the Codex app.
- **Handoff**: The flow that moves a thread between Local and Worktree. Codex handles the Git operations required to move your work safely between them.

- **本地检出（Local checkout）**：你自己创建的仓库。在 Codex 应用中，有时会简称为 **Local**。
- **工作树（Worktree）**：Codex 应用基于你的本地检出创建出来的 [Git worktree](https://git-scm.com/docs/git-worktree)。
- **Handoff**：在线程的 Local 和 Worktree 之间移动的流程。Codex 会处理必要的 Git 操作，确保你的工作能在两者之间安全转移。

## Why use a worktree / 为什么使用工作树

1. Work in parallel with Codex without disturbing your current Local setup.
2. Queue up background work while you stay focused on the foreground.
3. Move a thread into Local later when you're ready to inspect, test, or collaborate more directly.

1. 可以和 Codex 并行工作，同时不影响你当前的 Local 环境。
2. 你可以把任务排到后台执行，自己继续专注处理前台工作。
3. 当你准备好检查、测试或更直接地协作时，可以再把线程移动到 Local。

## Getting started / 开始使用

Worktrees require a Git repository. Make sure the project you selected lives in one.

工作树需要 Git 仓库。请确保你选择的项目位于一个 Git 仓库中。

### 1. Select "Worktree" / 选择 “Worktree”

In the new thread view, select **Worktree** under the composer. Optionally, choose a [local environment](https://developers.openai.com/codex/app/local-environments) to run setup scripts for the worktree.

在新线程视图中，在输入框下方选择 **Worktree**。你也可以选择一个 [local environment](https://developers.openai.com/codex/app/local-environments)，用于为该工作树运行初始化脚本。

### 2. Select the starting branch / 选择起始分支

Below the composer, choose the Git branch to base the worktree on. This can be your `main` / `master` branch, a feature branch, or your current branch with unstaged local changes.

在输入框下方，选择工作树要基于的 Git 分支。它可以是你的 `main` / `master` 分支、某个功能分支，或者带有未暂存本地修改的当前分支。

### 3. Submit your prompt / 提交你的提示词

Submit your task and Codex will create a Git worktree based on the branch you selected. By default, Codex works in a ["detached HEAD"](https://git-scm.com/docs/git-checkout#_detached_head).

提交任务后，Codex 会基于你选择的分支创建一个 Git worktree。默认情况下，Codex 会在 ["detached HEAD"](https://git-scm.com/docs/git-checkout#_detached_head) 状态下工作。

### 4. Choose where to keep working / 选择后续在哪里继续工作

When you're ready, you can either keep working directly on the worktree or hand the thread off to your local checkout. Handing off to or from local will move your thread _and_ code so you can continue in the other checkout.

当你准备好后，可以继续直接在工作树上工作，也可以把线程交接到本地检出。无论是交接到 Local，还是从 Local 交接出去，都会同时移动你的线程和代码，这样你就可以在另一个检出环境中继续工作。

## Working between Local and Worktree / 在 Local 和 Worktree 之间工作

Worktrees look and feel much like your local checkout. The difference is where they fit into your flow. You can think of Local as the foreground and Worktree as the background. Handoff lets you move a thread between them.

工作树看起来、用起来都很像你的本地检出。区别在于它们在工作流中的位置不同。你可以把 Local 理解为前台，把 Worktree 理解为后台。Handoff 可以让你在线程的两者之间移动。

Under the hood, Handoff handles the Git operations required to move work between two checkouts safely. This matters because **Git only allows a branch to be checked out in one place at a time**. If you check out a branch on a worktree, you **can't** check it out in your local checkout at the same time, and vice versa.

在底层，Handoff 会处理必要的 Git 操作，确保工作能够在两个检出环境之间安全移动。这一点很重要，因为 **Git 只允许同一个分支同时在一个地方被检出**。如果你在某个工作树上检出了一个分支，那么你 **不能** 同时在本地检出中检出同一个分支，反过来也一样。

In practice, there are two common paths:

实际使用中，常见路径有两种：

1. [Work exclusively on the worktree](#option-1-working-on-the-worktree). This path works best when you can verify changes directly on the worktree, for example because you have dependencies and tools installed using a [local environment setup script](https://developers.openai.com/codex/app/local-environments).
2. [Hand the thread off to Local](#option-2-handing-a-thread-off-to-local). Use this when you want to bring the thread into the foreground, for example because you want to inspect changes in your usual IDE or can run only one instance of your app.

1. [只在工作树上工作](#option-1-working-on-the-worktree)。当你可以直接在工作树上验证修改时，这种方式最合适。比如你已经通过 [local environment setup script](https://developers.openai.com/codex/app/local-environments) 安装好了依赖和工具。
2. [把线程交接到 Local](#option-2-handing-a-thread-off-to-local)。当你想把线程带到前台时使用这种方式。比如你想在常用 IDE 里检查修改，或者你的应用只能运行一个实例。

### Option 1: Working on the worktree / 方式一：在工作树上工作

If you want to stay exclusively on the worktree with your changes, turn your worktree into a branch using the **Create branch here** button in the header of your thread.

如果你想一直在这个工作树上处理这些修改，可以点击线程顶部的 **Create branch here**，把当前工作树变成一个分支。

From here you can commit your changes, push your branch to your remote repository, and open a pull request on GitHub.

之后你可以提交修改、把分支推送到远程仓库，并在 GitHub 上创建 Pull Request。

You can open your IDE to the worktree using the "Open" button in the header, use the integrated terminal, or anything else that you need to do from the worktree directory.

你可以点击顶部的 “Open” 按钮，在 IDE 中打开这个工作树；也可以使用集成终端，或者在工作树目录中执行其他需要的操作。

Remember, if you create a branch on a worktree, you can't check it out in any other worktree, including your local checkout.

注意，如果你在某个工作树上创建了一个分支，就不能在其他工作树中检出这个分支，包括你的本地检出。

### Option 2: Handing a thread off to Local / 方式二：把线程交接到 Local

If you want to bring a thread into the foreground, click **Hand off** in the header of your thread and move it to **Local**.

如果你想把一个线程带到前台，可以点击线程顶部的 **Hand off**，然后把它移动到 **Local**。

This path works well when you want to read the changes in your usual IDE window, run your existing development server, or validate the work in the same environment you already use day to day.

当你想在常用 IDE 窗口中查看修改、运行已有开发服务器，或者在日常使用的同一个环境中验证工作时，这种方式很合适。

Codex handles the Git steps required to move the thread safely between the worktree and your local checkout.

Codex 会处理所需的 Git 步骤，确保线程能够在工作树和本地检出之间安全移动。

Each thread keeps the same associated worktree over time. If you hand the thread back to a worktree later, Codex returns it to that same background environment so you can pick up where you left off.

每个线程会持续关联同一个工作树。如果之后你再把线程交接回工作树，Codex 会把它放回同一个后台环境，这样你可以从上次停止的地方继续。

You can also go the other direction. If you're already working in Local and want to free up the foreground, use **Hand off** to move the thread to a worktree. This is useful when you want Codex to keep working in the background while you switch your attention back to something else locally.

你也可以反向操作。如果你已经在 Local 中工作，并且想释放前台环境，可以使用 **Hand off** 把线程移动到工作树。当你希望 Codex 在后台继续工作，而自己切回本地处理其他事情时，这很有用。

Since Handoff uses Git operations, any files that are part of your `.gitignore` file won't move with the thread unless Codex copies them into a local managed worktree with `.worktreeinclude`.

由于 Handoff 使用 Git 操作，所以 `.gitignore` 中忽略的文件不会随线程一起移动，除非 Codex 根据 `.worktreeinclude` 把它们复制到本地托管工作树中。

## Advanced details / 高级细节

### Codex-managed and permanent worktrees / Codex 托管工作树和永久工作树

By default, threads use a Codex-managed worktree. These are meant to feel lightweight and disposable. A Codex-managed worktree is typically dedicated to one thread, and Codex returns that thread to the same worktree if you hand it back there later.

默认情况下，线程会使用 Codex 托管的工作树。这类工作树的定位是轻量、可丢弃。一个 Codex 托管工作树通常只服务于一个线程；如果你之后把该线程交接回工作树，Codex 会把它返回到同一个工作树。

If you want a long-lived environment, create a permanent worktree from the three-dot menu on a project in the sidebar. This creates a new permanent worktree as its own project. Permanent worktrees aren't automatically deleted, and you can start multiple threads from the same worktree.

如果你想要一个长期存在的环境，可以在侧边栏项目的三点菜单中创建永久工作树。这会把新的永久工作树作为一个独立项目创建出来。永久工作树不会被自动删除，你也可以从同一个工作树启动多个线程。

### How Codex manages worktrees for you / Codex 如何为你管理工作树

Codex creates worktrees in `$CODEX_HOME/worktrees`. The starting commit will be the `HEAD` commit of the branch selected when you start your thread. If you chose a branch with local changes, the uncommitted changes will be applied to the worktree as well. The worktree will _not_ be checked out as a branch. It will be in a [detached HEAD](https://git-scm.com/docs/git-checkout#_detached_head) state. This lets Codex create several worktrees without polluting your branches.

Codex 会在 `$CODEX_HOME/worktrees` 中创建工作树。起始提交会是你启动线程时选择的分支的 `HEAD` 提交。如果你选择的分支带有本地修改，未提交的修改也会被应用到工作树中。该工作树 _不会_ 以分支形式检出，而是处于 [detached HEAD](https://git-scm.com/docs/git-checkout#_detached_head) 状态。这样 Codex 就可以创建多个工作树，而不会污染你的分支列表。

### Copy ignored local files into managed worktrees / 把被忽略的本地文件复制到托管工作树

Local Codex-managed worktrees start from a Git checkout, so tracked files are already present. If your repository ignores local setup files that a new worktree needs, add a `.worktreeinclude` file to the repository root and list the ignored paths or `.gitignore`-style patterns to copy when Codex creates a managed worktree.

本地 Codex 托管工作树从 Git 检出开始创建，因此已被 Git 跟踪的文件会自动存在。如果你的仓库忽略了一些新工作树需要的本地配置文件，可以在仓库根目录添加 `.worktreeinclude` 文件，并列出要在 Codex 创建托管工作树时复制的被忽略路径或 `.gitignore` 风格的匹配模式。

Use this for files Git intentionally ignores, such as `.env`, `.env.local`, or `config/secrets.json`. Codex only copies ignored files that match `.worktreeinclude`; it doesn't copy other local files that Git doesn't track. Don't list tracked files.

这个机制适合用于 Git 有意忽略的文件，例如 `.env`、`.env.local` 或 `config/secrets.json`。Codex 只会复制匹配 `.worktreeinclude` 的被忽略文件；它不会复制其他未被 Git 跟踪的本地文件。不要把已跟踪文件列进去。

Codex automatically copies an ignored `AGENTS.override.md` into local managed worktrees, so you don't need to list it in `.worktreeinclude`.

Codex 会自动把被忽略的 `AGENTS.override.md` 复制到本地托管工作树中，因此你不需要把它写进 `.worktreeinclude`。

```text
# .worktreeinclude
.env
.env.local
config/secrets.json
```

Codex skips source symlinks and won't overwrite files that already exist in the new checkout. This behavior applies to local Codex app managed worktrees, not remote worktrees or Git worktrees you create yourself from the command line.

Codex 会跳过源符号链接，并且不会覆盖新检出环境中已经存在的文件。这个行为只适用于本地 Codex 应用托管的工作树，不适用于远程工作树，也不适用于你自己通过命令行创建的 Git worktree。

### Branch limitations / 分支限制

Suppose Codex finishes some work on a worktree and you choose to create a `feature/a` branch on it using **Create branch here**. Now, you want to try it on your local checkout. If you tried to check out the branch, you would get the following error:

假设 Codex 在某个工作树上完成了一些工作，然后你通过 **Create branch here** 在这个工作树上创建了 `feature/a` 分支。现在你想在本地检出中试一下这个分支。如果你尝试检出该分支，会看到下面的错误：

```text
fatal: 'feature/a' is already used by worktree at '<WORKTREE_PATH>'
```

To resolve this, you would need to check out another branch instead of `feature/a` on the worktree.

要解决这个问题，你需要在那个工作树上检出另一个分支，而不是继续检出 `feature/a`。

If you plan on checking out the branch locally, use Handoff to move the thread into Local instead of trying to keep the same branch checked out in both places at once.

如果你计划在本地检出该分支，请使用 Handoff 把线程移动到 Local，而不是尝试让同一个分支同时在两个地方被检出。

#### Why this limitation exists / 为什么会有这个限制

Git prevents the same branch from being checked out in more than one worktree at a time because a branch represents a single mutable reference (`refs/heads/<name>`) whose meaning is “the current checked-out state” of a working tree.

Git 不允许同一个分支同时在多个工作树中被检出，因为一个分支代表的是单个可变引用（`refs/heads/<name>`），它的含义是某个工作树的「当前检出状态」。

When a branch is checked out, Git treats its HEAD as owned by that worktree and expects operations like commits, resets, rebases, and merges to advance that reference in a well-defined, serialized way. Allowing multiple worktrees to simultaneously check out the same branch would create ambiguity and race conditions around which worktree's operations update the branch reference, potentially leading to lost commits, inconsistent indexes, or unclear conflict resolution.

当一个分支被检出时，Git 会认为它的 HEAD 归该工作树所有，并期望提交、重置、变基、合并等操作以明确且串行的方式推进这个引用。如果允许多个工作树同时检出同一个分支，就会产生歧义和竞态条件：到底哪个工作树的操作应该更新这个分支引用？这可能导致提交丢失、索引不一致，或者冲突解决过程不清晰。

By enforcing a one-branch-per-worktree rule, Git guarantees that each branch has a single authoritative working copy, while still allowing other worktrees to safely reference the same commits via detached HEADs or separate branches.

通过强制执行「一个分支只能对应一个工作树」的规则，Git 保证每个分支都有一个唯一权威的工作副本，同时仍允许其他工作树通过 detached HEAD 或独立分支安全地引用相同提交。

### Worktree cleanup / 工作树清理

Worktrees can take up a lot of disk space. Each one has its own set of repository files, dependencies, build caches, etc. As a result, the Codex app tries to keep the number of worktrees to a reasonable limit.

工作树可能占用大量磁盘空间。每个工作树都有自己的一套仓库文件、依赖、构建缓存等。因此，Codex 应用会尽量把工作树数量控制在合理范围内。

By default, Codex keeps your most recent 15 Codex-managed worktrees. You can change this limit or turn off automatic deletion in settings if you prefer to manage disk usage yourself.

默认情况下，Codex 会保留最近的 15 个 Codex 托管工作树。如果你想自己管理磁盘占用，可以在设置中修改这个限制，或者关闭自动删除。

Codex tries to avoid deleting worktrees that are still important. Codex-managed worktrees won't be deleted automatically if:

Codex 会尽量避免删除仍然重要的工作树。在以下情况下，Codex 托管工作树不会被自动删除：

- A pinned conversation is tied to it
- The thread is still in progress
- The worktree is a permanent worktree

- 有置顶会话绑定到它
- 线程仍在进行中
- 该工作树是永久工作树

Codex-managed worktrees are deleted automatically when:

Codex 托管工作树会在以下情况下被自动删除：

- You archive the associated thread
- Codex needs to delete older worktrees to stay within your configured limit

- 你归档了关联的线程
- Codex 需要删除较旧的工作树，以保持在你配置的数量限制内

Before deleting a Codex-managed worktree, Codex saves a snapshot of the work on it. If you open a conversation after its worktree was deleted, you'll see the option to restore it.

在删除 Codex 托管工作树之前，Codex 会保存该工作树上的工作快照。如果你在工作树被删除后重新打开对应会话，会看到恢复它的选项。

## Frequently asked questions / 常见问题

### Can I control where worktrees are created? / 我可以控制工作树创建在哪里吗？

Not today. Codex creates worktrees under `$CODEX_HOME/worktrees` so it can manage them consistently.

目前不可以。Codex 会在 `$CODEX_HOME/worktrees` 下创建工作树，以便统一管理。

### Can I move a thread between Local and Worktree? / 我可以在线程的 Local 和 Worktree 之间移动吗？

Yes. Use **Hand off** in the thread header to move a thread between your local checkout and a worktree. Codex handles the Git operations needed to move the thread safely between environments. If you hand a thread back to a worktree later, Codex returns it to the same associated worktree.

可以。使用线程顶部的 **Hand off**，就可以在本地检出和工作树之间移动线程。Codex 会处理必要的 Git 操作，确保线程在两个环境之间安全移动。如果你之后把线程交接回工作树，Codex 会把它返回到同一个关联工作树。

### What happens to threads if a worktree is deleted? / 如果工作树被删除，线程会怎样？

Threads can remain in your history even if the underlying worktree directory is deleted. For Codex-managed worktrees, Codex saves a snapshot before deleting the worktree and offers to restore it if you reopen the associated thread. Permanent worktrees are not automatically deleted when you archive their threads.

即使底层工作树目录被删除，线程仍可以保留在你的历史记录中。对于 Codex 托管工作树，Codex 会在删除工作树之前保存快照；如果你重新打开关联线程，它会提供恢复选项。永久工作树不会在你归档线程时被自动删除。
