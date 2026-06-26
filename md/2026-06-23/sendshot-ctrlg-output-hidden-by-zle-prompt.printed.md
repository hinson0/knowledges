# sendshot 按 Ctrl+G 路径不显示：ZLE widget 输出被多行提示符覆盖

> 日期：2026-06-23　环境：macOS + iTerm2 + zsh 5.9 + oh-my-zsh `ys` 主题
> 相关仓库：`hinson0/smart-claude-code-plugins`（PR #16，已合并，版本 3.24.0 → 3.24.1）

## 现象

`smart:sendshot` 装好后，在 macOS/iTerm2 按 **Ctrl+G**：

- 屏幕只闪一下 `sendshot: uploading clipboard image...`，随即消失；
- `sendshot: uploaded -> <路径>` 这行**从未出现**；
- 但图片**确实上传成功**，且 `Cmd+V` 能粘出远程路径 `~/tmp_images/clipboard-*.png`。

在 WSL2/Ubuntu 下手敲 `sendshot` 命令则一切正常、能看到路径。

## 根因（关键结论）

**逻辑层从没坏**：`pngpaste` 读图、`scp` 上传、`pbcopy` 写剪贴板全程正常。坏的只是**显示**。

zsh 的 **ZLE（行编辑器）** 把屏幕"占为己有"。widget 里用 `print` 往屏幕写字，ZLE 并不跟踪光标被推到了哪；widget 一返回（或调用 `zle redisplay` / `zle reset-prompt`），ZLE 按它**自己记忆的旧位置**把提示符重画一遍，**盖掉约等于"提示符行数"的最后几行输出**。

- 极简提示符（1 行）→ 只吃掉最后一行（如 `copied to clipboard`）。
- `ys` 主题是**多行提示符**（空行 + `# user@host in ~ [time]` + `$`，约 3 行）→ 一口气吃掉最后 ~3 行，把 `uploaded -> 路径` 全擦了。

这解释了"WSL 正常 / mac 异常"的差异：WSL 那边是**手敲命令**（输出留在滚动区，不被 ZLE 重画），mac 这边走 **Ctrl+G 的 ZLE widget**。剪贴板写的是系统 pasteboard，与屏幕显示无关，所以一直好用。

## 修复

把 widget 的输出从 `print` 改为 **`zle -M`**（ZLE 的**消息区**，渲染在提示符**下方**的独立区域，不在提示符重画范围内，永远不会被盖）。

```zsh
sendshot_insert_widget() {
  zle -M "sendshot: uploading clipboard image..."
  zle -R                       # 强制刷新，让"上传中"在 scp 阻塞期间就显示
  local output
  output="$(sendshot)" || { zle -M "sendshot: failed (no image in clipboard?)"; return 1; }
  zle -M "sendshot: ✓ uploaded & copied to clipboard
${output##*$'\n'}"           # zle -M 支持多行
}
```

逻辑层（pngpaste/scp/pbcopy）一行没动。`zle -M` 的消息会一直显示到下次按键，正好契合"按完 Ctrl+G → 切到另一窗口 Cmd+V"的用法。

## 踩坑：直觉选的 `zle reset-prompt` 是错的

网上常见的"从 widget 打印输出"建议是 `print` + `zle reset-prompt`。实测（tmux，多行提示符）**它和 `zle redisplay` 一样会被擦光**——因为 reset-prompt 还是回去重画那个多行提示符。三种写法实测对比：

| 写法 | 多行提示符下 | 结论 |
|---|---|---|
| `print` + `zle redisplay`（原版） | 输出全被擦 | ❌ |
| `print` + `zle reset-prompt` | 输出全被擦 | ❌ |
| `zle -M`（消息区） | 稳定显示 | ✅ |

## 验证方法（可复用）

普通管道只能拿到**原始字节流**（含 ZLE 重画的转义序列），看不出"用户最终在屏幕上看到什么"。用 **tmux** 驱动真实交互式 zsh + `capture-pane` 抓**重画后的最终画面**：

```bash
tmux new-session -d -s t -x 110 -y 30 "zsh -f"
tmux send-keys -t t "PROMPT=$'\n# %n @ %m in %~\n$ '" Enter   # 模拟多行提示符复现
tmux send-keys -t t "source /path/to/widget.zsh" Enter
tmux send-keys -t t C-g                                       # 发送 Ctrl+G
sleep 2
tmux capture-pane -t t -p                                     # = 用户真实所见
tmux kill-session -t t
```

调试时先用桩函数（stub）替换真实 `sendshot`，隔离"显示"这一个变量，避免反复打 EC2。

## 通用要点

- **ZLE widget 里不要用 `print` 输出需要持久可见的内容**——多行提示符会覆盖它。用 `zle -M`（确认信息）或把内容插进 `BUFFER`（需要本地编辑时）。
- 排查"复制/剪贴板"类问题时当心**观察者效应**：用"复制命令再粘贴"的方式去运行 `pbpaste`，会把剪贴板覆盖成命令文本，污染测试。改用在提示符直接 `Cmd+V`，或手敲命令。
- 1×1 的 PNG 用 osascript 放进剪贴板时 `pngpaste` 会报 `CGImageDestinationFinalize failed`；测试夹具要用稍大的有效图（如 64×64，可用 Python `zlib` 直接合成）。
