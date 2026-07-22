# ngrok-proxy-err-ngrok-9009

## Trigger Question

> `ngrok http 7676` 报错：`ERR_NGROK_9009`，提示 “Running the agent with an http/s proxy is a Pay-as-you-go feature.”
>
> 为什么之前 `ngrok http 7676` 不可以？

## Key Takeaways

- `ERR_NGROK_9009` 的根因是 ngrok 检测到 HTTP/S 代理，不是本机 `7676` 端口错误
- 代理可能来自 Shell 环境变量，也可能来自 `~/.config/ngrok/ngrok.yml` 的 `proxy_url`
- ngrok 免费套餐不允许 Agent 经 HTTP/S proxy 连接云端
- 用 `env -u` 临时移除代理变量后，本次 ngrok 成功直连并显示 `Session Status online`
- 会话中暴露过真实 Authtoken；旧 Token 必须撤销并轮换

## Concept

失败链路：

```text
ngrok Agent → 本地 HTTP/S 代理 → ngrok 云端
                                 └─ 免费套餐拒绝，ERR_NGROK_9009
```

成功链路：

```text
ngrok Agent ────────────────────→ ngrok 云端
             直接连接
```

错误文本中的 `authentication failed` 容易误导。结合 `ERR_NGROK_9009` 和后续直连成功，本次根因是代理套餐限制，而不是 `7676`、安装或 Token 格式本身。

## Field Table

| Field | Type | Required | Semantics | Example |
|------|------|------|------|------|
| `http_proxy` / `HTTP_PROXY` | `str \| None` | ✗ | HTTP 代理环境变量 | `"http://127.0.0.1:<PORT>"` |
| `https_proxy` / `HTTPS_PROXY` | `str \| None` | ✗ | HTTPS 代理环境变量 | `"http://127.0.0.1:<PORT>"` |
| `all_proxy` / `ALL_PROXY` | `str \| None` | ✗ | 全协议代理环境变量 | `"socks5://127.0.0.1:<PORT>"` |
| `proxy_url` | `str \| None` | ✗ | ngrok 配置文件里的显式代理 | `"http://127.0.0.1:<PORT>"` |
| `Authtoken` | `str` | ✓ | ngrok Agent 账号凭据 | `"<NEW_AUTHTOKEN>"` |

## Code Example

### 检查 Shell 代理变量

```bash
env | rg -i '^(http|https|all)_proxy='
```

### 检查 ngrok 配置

```bash
rg -n 'proxy_url|http_proxy' ~/.config/ngrok/ngrok.yml
ngrok config edit
```

如果配置中存在 `proxy_url:` 或 `http_proxy:`，删除相应代理项并保存。

### 临时绕过代理启动

```bash
env \
  -u http_proxy \
  -u https_proxy \
  -u HTTP_PROXY \
  -u HTTPS_PROXY \
  -u all_proxy \
  -u ALL_PROXY \
  ngrok http 7676
```

本次修复后的成功状态已去除账号和真实临时 URL：

```text
Session Status                online
Version                       3.39.9
Region                        Japan (jp)
Latency                       193ms
Web Interface                 http://127.0.0.1:4040
Forwarding                    https://<RANDOM>.ngrok-free.dev -> http://localhost:7676
```

### 轮换已暴露的 Authtoken

先在 ngrok Dashboard 撤销旧 Token 并生成新 Token，再执行：

```bash
ngrok config add-authtoken "<NEW_AUTHTOKEN>"
```

本文不保存会话中出现过的真实 Token、账号邮箱或临时公网地址。

## Pitfall / Why

### `ERR_NGROK_9009`

**Conclusion**: 看到 `ERR_NGROK_9009` 时，优先排查代理环境和 `ngrok.yml`，不要先怀疑 `7676` 端口。

**Why**: ngrok 免费套餐拒绝 Agent 经 HTTP/S proxy 连接；本机端口只决定流量转发目的地，不决定 Agent 如何连接 ngrok 云端。

**How to apply**: 检查六组大小写代理环境变量和配置文件代理项，再用 `env -u` 做一次无代理启动验证。

### `authentication failed` 的误导性

**Conclusion**: 错误首行写 `authentication failed` 不代表 Authtoken 一定无效，必须结合具体错误码判断。

**Why**: 本次同一个 Agent 清除代理后成功上线，说明失败发生在账号套餐对代理能力的授权检查。

**How to apply**: 以 `ERR_NGROK_9009` 为主要诊断信号；只有代理排除后仍报 Token 相关错误，才重新检查 Token 配置。

### 网络必须依赖代理

**Conclusion**: 如果清除代理后变成超时，且当前网络无法直连 ngrok，免费 ngrok 方案可能不可用。

**Why**: 免费套餐不允许 HTTP/S proxy，而本地网络又要求代理，两个条件无法同时满足。

**How to apply**: 改用支持当前网络条件的隧道方案，例如 Cloudflare Tunnel，或升级到允许代理的 ngrok 付费套餐。

### 凭据暴露

**Conclusion**: 本次会话中粘贴的真实 Authtoken 应视为已泄露，必须撤销，而不是只从聊天记录中删掉。

**Why**: 已暴露凭据可能被复制和滥用；重新执行 `add-authtoken` 并不会自动使旧 Token 失效。

**How to apply**: 在 Dashboard 撤销旧 Token、创建新 Token、更新本机配置，并避免将新 Token 放进命令截图或可分享的 Shell 输出。

## Related

- [ngrok-linux-binary-install.md](./ngrok-linux-binary-install.md) — apt 安装慢时使用官方二进制
- [devspace-chatgpt-mcp-setup.md](./devspace-chatgpt-mcp-setup.md) — ngrok 成功上线后配置 DevSpace 和 ChatGPT MCP Endpoint
- [ERR_NGROK_9009](https://ngrok.com/docs/errors/err_ngrok_9009) — ngrok 对该错误码的说明

---
Source: distill from CC session
Date: 2026-07-22
Rounds covered: round #6 - #9
