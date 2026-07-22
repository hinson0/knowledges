# ngrok-linux-binary-install

## Trigger Question

> 很卡 apt install ngrok

## Key Takeaways

- `apt install ngrok` 长时间无进展时，可以中止并改装官方独立二进制
- 下载前先用 `uname -m` 区分 AMD64 和 ARM64
- AMD64 压缩包解压到 `/usr/local/bin` 后即可运行，无额外运行时依赖
- Authtoken 属于敏感凭据，只能使用占位符记录，不能提交到 Git
- 不再采用会话早期给出的旧 `buster` apt 软件源建议

## Concept

ngrok Linux Agent 可以直接使用官方发布的单文件二进制。该路径绕过 apt 索引更新和仓库下载，适合 `apt install ngrok` 很慢、镜像不可达或发行版软件源不匹配的情况。

## Code Example

先确认 CPU 架构：

```bash
uname -m
```

如果输出为 `x86_64`，本次会话使用的 AMD64 安装方式是：

```bash
wget "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
sudo tar xvzf ngrok-v3-stable-linux-amd64.tgz -C /usr/local/bin
ngrok version
```

如果输出为 `aarch64` 或 `arm64`，不要使用 AMD64 包；应从 ngrok 官方 Linux 下载页选择 ARM64 构建。

配置新 Authtoken 并启动到 DevSpace 本机端口：

```bash
ngrok config add-authtoken "<NEW_AUTHTOKEN>"
ngrok http 7676
```

## Pitfall / Why

### apt 安装卡住

**Conclusion**: apt 安装持续卡住时，可以按 `Ctrl+C` 中止并改用官方独立二进制，不必继续等待。

**Why**: 卡顿通常发生在软件源访问、索引更新或网络链路上；ngrok 本身可作为单文件 Agent 运行。

**How to apply**: 先确认架构，再从官方来源下载匹配的压缩包，解压到 PATH 中并用 `ngrok version` 验证。

### 旧发行版软件源

**Conclusion**: 不保留或复用会话早期的 `buster` apt 软件源安装建议。

**Why**: 固定到旧发行版的软件源可能与当前系统不匹配，也正是本次建议后来改为官方二进制的原因。

**How to apply**: 优先参考 ngrok 当前官方 Linux 下载页；若仍选择 apt，应使用与当前发行版和 ngrok 官方文档一致的软件源配置。

### 架构不匹配

**Conclusion**: AMD64 和 ARM64 二进制不可混用。

**Why**: 压缩包包含针对特定 CPU 指令集编译的可执行文件，下载错误会出现无法执行或格式错误。

**How to apply**: `x86_64` 选择 AMD64；`aarch64` 或 `arm64` 选择 ARM64，并在安装后立即运行 `ngrok version`。

### Authtoken 安全

**Conclusion**: Authtoken 不应出现在聊天、截图、Shell 历史分享或仓库文件中。

**Why**: 拿到 Token 的人可能以账号身份启动 ngrok Agent；本次会话后续确实发生了真实 Token 暴露。

**How to apply**: 命令文档统一写 `<NEW_AUTHTOKEN>`；若已暴露，立即在 Dashboard 撤销旧 Token、生成新 Token，再更新本机配置。

## Related

- [devspace-chatgpt-mcp-setup.md](./devspace-chatgpt-mcp-setup.md) — 使用 ngrok 将 DevSpace 的 `7676` 端口提供给 ChatGPT
- [ngrok-proxy-err-ngrok-9009.md](./ngrok-proxy-err-ngrok-9009.md) — 安装完成后因 HTTP/S 代理触发的免费套餐限制
- [ngrok Linux download](https://ngrok.com/download/linux) — 按当前架构选择官方 Agent

---
Source: distill from CC session
Date: 2026-07-22
Rounds covered: round #4 - #5
