# Tmux 使用指南

> 整理 tmux 常用命令、配置文件及部署方法，适合日常快速查阅。

---

## 常用命令速查

### 一、会话管理（Session）

| 命令                                  | 说明                     |
| ------------------------------------- | ------------------------ |
| `tmux new -s <session-name>`          | 创建新会话               |
| `tmux ls` 或 `tmux list-sessions`     | 列出所有会话             |
| `tmux attach -t <session-name>`       | 重新附着到指定会话       |
| `tmux detach`（快捷键：`Ctrl+b d`）   | 分离当前会话（后台运行） |
| `tmux kill-session -t <session-name>` | 删除指定会话             |
| `tmux switch -t <session-name>`       | 切换到另一个会话         |

---

### 二、窗口管理（Window）

| 快捷键（前缀 `Ctrl+b`） | 说明                     |
| ----------------------- | ------------------------ |
| `c`                     | 创建新窗口               |
| `,`                     | 重命名当前窗口           |
| `p`                     | 切换到上一个窗口         |
| `n`                     | 切换到下一个窗口         |
| `0-9`                   | 直接切换到指定编号的窗口 |
| `w`                     | 以菜单方式列出并选择窗口 |
| `&`                     | 关闭当前窗口（需确认）   |

---

### 三、窗格管理（Pane）

| 快捷键（前缀 `Ctrl+b`）  | 说明                         |
| ------------------------ | ---------------------------- |
| `%`                      | 垂直分割窗格（左右分屏）     |
| `"`                      | 水平分割窗格（上下分屏）     |
| `方向键`（或 `h/j/k/l`） | 在窗格间移动焦点             |
| `q` + 数字编号           | 显示窗格编号，按数字快速跳转 |
| `x`                      | 关闭当前窗格（需确认）       |
| `z`                      | 缩放当前窗格（再次按恢复）   |
| `{` 或 `}`               | 与上一个/下一个窗格交换位置  |
| `;`                      | 切换到上一次使用的窗格       |
| `空格键`                 | 切换预置的窗格布局           |
| `Ctrl+方向键`            | 调整窗格大小                 |
| `!`                      | 将当前窗格拆分为新窗口       |

---

### 四、其他常用快捷键与命令

| 操作               | 说明                             |
| ------------------ | -------------------------------- |
| `Ctrl+b d`         | 分离会话（detach）               |
| `Ctrl+b ?`         | 列出所有快捷键（帮助）           |
| `Ctrl+b :`         | 进入命令模式（可输入 tmux 命令） |
| `tmux kill-server` | 关闭所有 tmux 会话及服务器       |

---

### 五、快速命令示例

```bash
# 创建名为 "work" 的会话
tmux new -s work

# 分离当前会话（在 tmux 内）
Ctrl+b d

# 查看所有会话
tmux ls

# 重新连接到 "work" 会话
tmux attach -t work

# 在会话内创建垂直分割窗格
Ctrl+b %

# 在会话内创建水平分割窗格
Ctrl+b "

# 关闭当前窗格（需 y 确认）
Ctrl+b x
```

---

掌握以上命令即可高效使用 tmux 进行日常终端多任务管理。

---

## ~/.tmux.conf 配置详解

适用场景: 本地 iTerm2 → SSH → 远程 EC2,tmux 运行在 EC2 上做会话持久化。

```tmux
#==============================================================================
# tmux 配置  (~/.tmux.conf)
#
# 场景:本地 iTerm2 --ssh--> 远程 EC2,tmux 跑在 EC2 上(会话持久化)
# 改动后重载:tmux source-file ~/.tmux.conf
# 注意:涉及按键协议的改动(extended-keys 等),需重启 tmux 内运行的程序才生效
#==============================================================================


#------------------------------------------------------------------------------
# 剪贴板:OSC 52(把复制内容从远程穿过 ssh 送回本地 iTerm2 剪贴板)
#
# 无图形界面的服务器没有系统剪贴板,xclip/xsel 用不了。OSC 52 是终端转义序列,
# 由本地终端(iTerm2)负责落地到 macOS 剪贴板。
# 前提:iTerm2 -> Settings -> General -> Selection
#       勾选 "Applications in terminal may access clipboard"
#------------------------------------------------------------------------------
set -g set-clipboard on
set -s set-clipboard on
# 告诉 tmux:外层终端支持 OSC 52(Ms capability),复制时据此发送序列
set -ga terminal-overrides ',*:Ms=\E]52;%p1%s;%p2%s\7'


#------------------------------------------------------------------------------
# 复制模式:vi 键位
#
# 两条复制路径:
#   ① 键盘路(显式绑定):
#     Ctrl+b [          → 进入 copy-mode
#     v + 方向键/hjkl   → 选择
#     y                 → 复制(触发 OSC 52 → iTerm2 → Mac 剪贴板)
#     本地 Cmd+V        → 粘贴
#
#   ② 鼠标路(隐式,靠 mouse on):
#     Ctrl+b [          → 进入 copy-mode
#     鼠标拖选           → 松开即自动复制(触发 OSC 52 → Mac 剪贴板)
#     本地 Cmd+V        → 粘贴
#
# 仅在需要选取屏幕外/翻页历史内容时才用得上;
# 当前可见内容直接用 iTerm2 选中 + Cmd+C/Cmd+V 即可。
#------------------------------------------------------------------------------
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel
# 鼠标拖选,松开即自动复制
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel


#------------------------------------------------------------------------------
# 鼠标支持:拖选复制、滚轮进入复制模式翻历史
# 提示:开启后 tmux 会接管鼠标。想用 iTerm2 原生选择时,按住 Option(⌥) 再拖。
#------------------------------------------------------------------------------
set -g mouse on


#------------------------------------------------------------------------------
# 扩展键透传:让 Shift+Enter / Ctrl+Enter 等带修饰键的按键穿过 tmux
#
# 普通终端里 Shift+Enter 和 Enter 编码相同;现代终端用 CSI-u 协议区分,
# tmux 默认会把这类序列降级丢掉。打开后才能让 Claude Code 等程序收到。
# always = 强制转发(比 on 更省心,on 仅在程序主动请求时才转发)
# ⚠️ 改这里后必须重启 tmux 内的程序,它才会重新协商键盘协议
#------------------------------------------------------------------------------
set -s extended-keys always
set -as terminal-features 'xterm*:extkeys'
```

> ⚠️ **OSC 52 行注意**: 第 26 行中的 `\E` 和 `\7` 是**单反斜杠**。如果通过工具写入文件,注意转义层数——落到文件里必须是单反斜杠。直接从代码块复制即为正确版本。

### 部署方法

1. 将配置保存到目标机器的 `~/.tmux.conf`
2. 执行 `tmux source-file ~/.tmux.conf` 重载配置
3. 若启用了 `extended-keys`,需重启 tmux 内的程序(如 Claude Code)以重新协商键盘协议

---

## 附: SCP 批量上传示例

```bash
scp -i ~/.ssh/WitMani_Agent.pem -r ~/Downloads/export-prototype-a/ \
  ubuntu@ec2-35-74-250-39.ap-northeast-1.compute.amazonaws.com:/home/ubuntu/material_turbo/apps/prototype
```

<details>
<summary>上传日志</summary>

```
Prototype A.html    100% 2851   31.5KB/s  00:00
icons.jsx           100% 5114   56.7KB/s  00:00
images.jsx          100% 4765   53.9KB/s  00:00
inline-task.jsx     100% 8311   89.2KB/s  00:00
signup.jsx          100%   26KB 220.9KB/s  00:00
edit-image.jsx      100%   34KB 279.4KB/s  00:00
q-batch.jsx         100%   18KB 186.7KB/s  00:00
chat-main.jsx       100%   53KB 393.2KB/s  00:00
score-table.jsx     100%   31KB 300.5KB/s  00:00
score-report.jsx    100%   21KB 220.5KB/s  00:00
app-a.jsx           100% 6988   78.1KB/s  00:00
whitelist.jsx       100%  ...
```

</details>
