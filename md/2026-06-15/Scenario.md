一句话概括：`ce-workflow` 的方向是对的，它把“多仓库开发”从临场摸索变成了有资产、有 worktree、有验证记录的流程；但现在还太依赖 agent 自觉，缺少硬校验和一键化脚本，所以我才会在 env、服务启动、skill 落点这些地方犯错。

**1. ce-workflow 流程**
标准流程应该是：

1. 解析需求：提取 feature 名、slug、涉及仓库、原型、截图、已有材料。
2. 检查 harness：读 `AGENTS.md`、`repos.json`、`scripts/harness.mjs`、模板和现有 skill。
3. 注册/clone 仓库：source clone 放到 `projects/<repo>`，必要时更新 `repos.json`。
4. 创建 feature worktree：业务代码放到 `worktrees/<feature>/<repo>`，分支统一用 `feature/<feature>`。
5. 理解仓库：分别进入每个子仓库读技术栈、路由、API、模型、测试入口。
6. 生成资产文档：写 `assets/<feature>/requirements.md` 和 `contracts_api.md`。
7. 编码前暂停：让用户确认需求和 API 契约。
8. 写 plan：确认后生成 `plan-YYYY-MM-DD-<topic>.md`。
9. TDD/实现：后端、前端分别在自己的 worktree 做实现。
10. 本地联调：使用 `$ce-docker` 起 MySQL/迁移/后端服务，使用 `$ce-env` 配前端 env。
11. 验证与 debug 沉淀：写 `verification.md`、`debug-YYYY-MM-DD-*.md`。
12. review/commit/PR：用 `$ce-review`、`$ce-commit`、`$ce-pr` 收尾。

**2. 当前 harness 目录结构**
当前结构大概是：

```text
ce-harness-cms/
  AGENTS.md
  repos.json
  scripts/
    harness.mjs

  .agents/skills/
    ce-workflow/
    ce-review/
    ce-debug/
    ce-api/
    ce-env/
    ce-docker/
    ce-commit/
    ce-pr/
    ce-km/
    agentsmd/
    agentsmd-update/

  projects/
    cms-center/
    ce-site-backend/

  worktrees/
    social-media-share/
      cms-center/
      ce-site-backend/

  assets/
    social-media-share/
      requirements.md
      contracts_api.md
      plan-2026-06-12-social-media-share.md
      verification.md
      debug-2026-06-13-login-session-cookie.md
```

关键点：`projects/` 是长期 source clone，`worktrees/` 是 feature 临时业务工作区，`assets/` 是长期知识资产，`.agents/skills/` 是项目内 Codex 工作流能力。

**3. 这套 workflow 的优势**
最大的优势是把多仓库工作分层了：

- 控制面和业务代码分离：harness 不混成 monorepo。
- feature 资产长期保留：需求、API、plan、debug、verification 不会随着 worktree 删除而丢。
- 多仓库隔离清楚：每个子仓库有自己的 branch、status、测试和提交边界。
- 契约先行：先写 `contracts_api.md`，减少前后端字段和 route 漂移。
- 能沉淀经验：这次 cookie、`.env`、Docker、migration 的坑已经变成 `$ce-env` / `$ce-docker`。
- 适合复用：下一个 CE feature 可以直接沿用 source clone、harness 脚本和 skill。

**4. 当前不足和待改进**
现在的问题也很明确：

- 流程偏“文档约束”，缺少硬性脚本校验。比如不该允许我把 skill 写到根目录 `skills/`，应该有检查直接失败。
- 本地联调启动不够一键化。应该有类似 `scripts/dev-up social-media-share`，自动起 MySQL、迁移、后端、前端并打印 URL。
- env 规则之前没有内建到 workflow，导致一开始误连 `.env.test` 的远端测试 API。
- 服务依赖没有 preflight。比如 MySQL、PHP 扩展、`pdo_sqlite`、端口占用、Vite mode 应该提前检查。
- TDD 和验证还会被环境问题打断。后端 PHPUnit 被 `pdo_sqlite`、`mysql-test`、compose app build context 阻塞，说明测试环境矩阵要标准化。
- 子代理审核机制还没有完全工具化，更多依赖主线程执行纪律。
- 浏览器端验证仍偏手动，应该沉淀 Playwright 登录脚本、cookie 检查脚本、菜单/API smoke test。
- skill 创建/更新也要有 CI 或本地 check：`quick_validate.py .agents/skills/*`，并检查没有根目录 `skills/`。

**5. 社媒场景分享实践结果**
已经自动化或半自动化的部分：

- 根据仓库 URL 建立 `projects/` source clone。
- 创建 `worktrees/social-media-share/{cms-center,ce-site-backend}`。
- 生成并维护 `assets/social-media-share/requirements.md`。
- 生成 API 契约 `contracts_api.md`。
- 生成实现计划 `plan-2026-06-12-social-media-share.md`。
- 用 `verification.md` 记录前后端测试、build、migration、route、服务启动结果。
- 用 debug 文档沉淀登录后 `get-menus 401` 的根因。
- 把本地联调经验沉淀成 `.agents/skills/ce-env`。
- 把 Docker/MySQL/migration 经验沉淀成 `.agents/skills/ce-docker`。
- 修正 `AGENTS.md`，把这些流程纳入 `$ce-workflow`。

结论：这套 workflow 已经能把一个多仓库需求从“口头需求”推进到“隔离工作区 + 契约 + 实现计划 + 本地联调 + debug 知识沉淀”。下一步要做的是把纪律变成脚本和检查，减少靠 agent 自觉。

---

## TODO

- ce-harness-cms 的worktree改造,即harness本身可以通过worktree的方式一并并行开发,当前并不支持.
- workflow的脚本强约束,而不是依赖当前的md的软约束
- 未来2周,在不同的需求中去迭代本ce harness framework,做到能更懂ce的开发workflow
