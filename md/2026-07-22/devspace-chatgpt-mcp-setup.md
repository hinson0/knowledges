# devspace-chatgpt-mcp-setup

## Trigger Question

> https://github.com/Waishnav/devspace 阅读下这个仓库 然后告诉我 怎么配置 然后在网页版本 ChatGPT 又要怎么操作设置。

## Key Takeaways

- DevSpace 在本机提供 MCP Server，通过 HTTPS 隧道把文件和终端工具连接到 ChatGPT
- `publicBaseUrl` 只填公网根地址；ChatGPT 的 MCP Endpoint 才追加 `/mcp`
- 网页端创建自定义 App，选择 OAuth、扫描工具，并用 Owner password 完成授权
- 修改代码应使用普通 ChatGPT 对话并显式选择 DevSpace；不同套餐和模式的能力不同
- `allowedRoots` 只限制文件工具，`bash` 仍按本机运行账号权限执行

## Concept

DevSpace 是运行在开发者电脑上的 MCP Server。项目文件不需要预先上传到额外托管平台；当 ChatGPT 调用工具时，所请求的文件内容、命令和命令输出仍会经过网络传输。

典型链路：

```text
ChatGPT 网页版
    │ HTTPS / OAuth
    ▼
公网隧道地址 /mcp
    │
    ▼
本机 DevSpace :7676
    ├── 文件工具 → allowedRoots 内的项目
    └── bash 工具 → 本机运行账号的系统权限
```

### 本机前提

本次会话记录的仓库要求为：

- Node.js `>=22.19 <27`，优先使用 Node 22
- npm、Git、Bash
- Windows 使用 Git Bash 或 WSL
- 一个能够转发到本机 `7676` 的 HTTPS 公网地址

### ChatGPT 网页端入口

截至 2026-07-22，本次会话记录的入口和能力如下：

| 套餐 / 工作区 | 设置入口或能力 |
|------|------|
| Business | 管理员或 Owner 在 Workspace settings → Apps → Create；必要时先开启 Developer mode |
| Enterprise / Edu | 管理员先在 Permissions & Roles → Connected Data 授权创建自定义 MCP，再由用户开启 Developer mode |
| Pro | 记录中仅支持 read/fetch 类 MCP 操作，不能完整使用 DevSpace 的写文件和终端能力 |
| Plus / Free | 记录中未列入完整自定义 MCP 支持范围 |

界面更新后，入口也可能显示为 `Settings → Plugins → +`。

创建 App 时填写：

| Field | Type | Required | Semantics | Example |
|------|------|------|------|------|
| `Name` | `str` | ✓ | 自定义 App 名称 | `"DevSpace"` |
| `MCP URL` | `str` | ✓ | DevSpace 的完整 MCP Endpoint | `"https://<PUBLIC_HOST>/mcp"` |
| `Authentication` | `str` | ✓ | DevSpace 授权方式 | `"OAuth"` |
| `Owner password` | `str` | ✓ | `devspace init` 生成，仅在授权页面输入 | `"<OWNER_PASSWORD>"` |

随后点击 `Scan Tools`，在 DevSpace 授权页输入 Owner password，完成后创建 App。个人测试可使用带 `Dev` 标记的草稿；团队使用时再由管理员发布。

## Field Table

| Field | Type | Required | Semantics | Example |
|------|------|------|------|------|
| `allowedRoots` | `list[path]` | ✓ | DevSpace 文件工具允许访问的根目录 | `["/path/to/project"]` |
| `port` | `int` | ✓ | 本机 MCP Server 监听端口 | `7676` |
| `publicBaseUrl` | `str` | ✓ | HTTPS 公网根地址，不带 `/mcp` | `"https://<PUBLIC_HOST>"` |
| MCP Endpoint | `str` | ✓ | ChatGPT 扫描和调用工具的地址 | `"https://<PUBLIC_HOST>/mcp"` |
| Owner password | `str` | ✓ | DevSpace OAuth 授权凭据 | `"<OWNER_PASSWORD>"` |

## Code Example

### 安装并初始化

```bash
node --version
npm --version
git --version
bash --version

npm install -g @waishnav/devspace
npx @waishnav/devspace init
```

初始化时使用类似配置：

```text
Allowed project root: /path/to/project
Local port: 7676
Public Base URL: https://<PUBLIC_HOST>
```

`Public Base URL` 不追加 `/mcp`。

### 检查并启动

```bash
npx @waishnav/devspace doctor
npx @waishnav/devspace serve
```

另一个终端保持 HTTPS 隧道运行：

```bash
ngrok http 7676
```

健康检查：

```bash
curl "https://<PUBLIC_HOST>/healthz"
```

预期响应类似：

```json
{"ok":true,"name":"devspace"}
```

### 在普通聊天中调用

```text
请使用 DevSpace，以 checkout 模式打开：

/path/to/project

先读取 AGENTS.md 和项目结构，只做检查，不要修改文件。
```

确认读取正常后，再明确授权修改和验证：

```text
请修复登录接口的问题。
修改文件后运行测试，并总结修改过的文件和验证结果。
```

需要隔离工作区时可要求使用 worktree；项目必须是 Git 仓库且至少有一个 commit，未提交改动不会自动复制到新 worktree。

## Pitfall / Why

### 公网根地址与 MCP Endpoint

**Conclusion**: DevSpace 的 `publicBaseUrl` 不带 `/mcp`，ChatGPT 创建 App 时填写的 Endpoint 必须带 `/mcp`。

**Why**: 两者用途不同；前者用于 DevSpace 生成公开地址，后者是 MCP 协议入口。混用会导致扫描工具或 OAuth 回调失败。

**How to apply**: 初始化填写 `https://<PUBLIC_HOST>`，网页端填写 `https://<PUBLIC_HOST>/mcp`，健康检查使用 `https://<PUBLIC_HOST>/healthz`。

### 套餐和聊天模式限制

**Conclusion**: 完整的读写和终端操作需要支持自定义 MCP 写操作的工作区，并应从普通聊天选择 DevSpace。

**Why**: 本次记录中，Pro 仅有 read/fetch；Agent mode 不调用自定义 App，Deep Research 对自定义 App 也偏向只读。

**How to apply**: 先确认工作区权限和 Developer mode，再在普通对话的 Tools / Apps 中选择 DevSpace；若只能读取，优先排查套餐和模式限制。

### 安全边界

**Conclusion**: 不要把 worktree 或 `allowedRoots` 当作完整安全沙箱。

**Why**: `allowedRoots` 约束的是文件工具，而 DevSpace 的 `bash` 按本机用户权限执行，可能访问允许目录以外的 SSH Key、云凭据或其他文件。

**How to apply**: 使用专门的低权限账号，只开放具体项目目录，不让该账号持有生产凭据，默认要求修改前确认，不用时关闭 DevSpace 和隧道。

### 临时隧道地址

**Conclusion**: 免费临时公网地址变化后，需要同步更新 DevSpace 和 ChatGPT App。

**Why**: ChatGPT 会继续连接创建 App 时保存的旧 Endpoint；只重启本机服务不会自动更新网页端配置。

**How to apply**: 地址变化后运行 `npx @waishnav/devspace config set publicBaseUrl https://<NEW_PUBLIC_HOST>`，重启服务，并更新或重建 ChatGPT App。

## Related

- [ngrok-linux-binary-install.md](./ngrok-linux-binary-install.md) — apt 安装较慢时直接安装 ngrok 官方二进制
- [ngrok-proxy-err-ngrok-9009.md](./ngrok-proxy-err-ngrok-9009.md) — ngrok 免费版因代理环境触发 `ERR_NGROK_9009` 的处理
- [DevSpace setup](https://github.com/Waishnav/devspace/blob/main/docs/setup.md) — 仓库安装和启动说明
- [DevSpace configuration](https://github.com/Waishnav/devspace/blob/main/docs/configuration.md) — 配置字段说明
- [DevSpace security](https://github.com/Waishnav/devspace/blob/main/docs/security.md) — 文件工具与终端权限边界
- [ChatGPT coding workflow](https://github.com/Waishnav/devspace/blob/main/docs/chatgpt-coding-workflow.md) — checkout 和 worktree 工作流

---
Source: distill from CC session
Date: 2026-07-22
Rounds covered: round #1
