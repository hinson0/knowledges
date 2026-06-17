下面是一份可直接保存为 Markdown 的文档。

````markdown
# Codex 中 Playwright 使用方法

## 1. Playwright 什么时候用

Playwright 用来控制真实浏览器，适合检查页面的实际表现。

常见场景：

- 打开页面，确认是否能正常渲染
- 点击按钮、菜单、弹窗，验证交互是否正常
- 填写表单并提交
- 截图检查 UI 布局
- 查看浏览器 console 报错
- 查看 network 请求失败
- 复现前端 bug
- 写 E2E 测试前，先探索页面流程

简单判断：

```text
只看代码就能判断：不用 Playwright
需要确认浏览器真实表现：用 Playwright
需要点击、填表、截图、看 console/network：用 Playwright
```
````

## 2. Codex 里的 Playwright wrapper

Codex 提供了一个 wrapper 脚本：

```bash
$HOME/.codex/skills/playwright/scripts/playwright_cli.sh
```

建议先设置环境变量：

```bash
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export PWCLI="$CODEX_HOME/skills/playwright/scripts/playwright_cli.sh"
```

如果已经加过执行权限：

```bash
chmod +x "$PWCLI"
```

就可以直接运行：

```bash
"$PWCLI" open https://example.com --browser chromium
```

## 3. 推荐设置别名

为了以后少打命令，可以加入 `~/.zshrc`：

```bash
alias pwcli="$HOME/.codex/skills/playwright/scripts/playwright_cli.sh"
```

使其立即生效：

```bash
source ~/.zshrc
```

之后直接使用：

```bash
pwcli open https://example.com --browser chromium
```

## 4. 基本工作流

Playwright CLI 的核心流程是：

1. 打开页面
2. 获取页面快照
3. 根据快照里的元素编号操作页面
4. 页面变化后重新获取快照
5. 必要时截图、看 console、看 network

示例：

```bash
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli snapshot
pwcli click e3
pwcli snapshot
pwcli screenshot
```

`snapshot` 会返回类似 `e1`、`e2`、`e3` 的元素编号。之后点击、填写、读取元素时都用这些编号。

## 5. 常用命令

### 打开页面

```bash
pwcli open https://example.com --browser chromium
```

本机如果没有系统 Chrome，建议加：

```bash
--browser chromium
```

不要使用：

```bash
--headless
```

这个 wrapper 不支持 `--headless` 参数。

### 获取页面快照

```bash
pwcli snapshot
```

这是最常用的命令。操作元素前，通常都要先执行一次。

### 点击元素

```bash
pwcli click e3
```

其中 `e3` 来自最新一次 `snapshot`。

### 输入文本

```bash
pwcli fill e5 "user@example.com"
```

或者：

```bash
pwcli type "hello world"
```

### 按键

```bash
pwcli press Enter
pwcli press ArrowDown
```

### 截图

```bash
pwcli screenshot
```

也可以只截某个元素：

```bash
pwcli screenshot e5
```

### 查看 console

```bash
pwcli console
```

只看 warning：

```bash
pwcli console warning
```

### 查看 network

```bash
pwcli network
```

用于检查接口请求失败、资源加载失败等问题。

### 调整窗口尺寸

```bash
pwcli resize 1280 720
pwcli resize 390 844
```

可用于检查桌面端和移动端布局。

## 6. 表单填写示例

```bash
pwcli open https://example.com/login --browser chromium
pwcli snapshot
pwcli fill e1 "user@example.com"
pwcli fill e2 "password123"
pwcli click e3
pwcli snapshot
pwcli screenshot
```

关键点：

- 先 `snapshot`
- 用快照里的元素编号操作
- 点击提交后重新 `snapshot`
- 最后截图或查看 console

## 7. 调试 UI bug 示例

```bash
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli snapshot
pwcli console
pwcli network
pwcli screenshot
```

如果要复现点击问题：

```bash
pwcli click eX
pwcli snapshot
pwcli console
pwcli screenshot
```

其中 `eX` 替换成实际 snapshot 里的元素编号。

## 8. 多标签页

新开标签页：

```bash
pwcli tab-new https://example.com
```

查看标签页：

```bash
pwcli tab-list
```

切换标签页：

```bash
pwcli tab-select 0
```

关闭标签页：

```bash
pwcli tab-close
```

## 9. Session 隔离

如果同时调试多个页面或项目，可以使用 session：

```bash
pwcli --session marketing open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli --session marketing snapshot
```

也可以设置默认 session：

```bash
export PLAYWRIGHT_CLI_SESSION=marketing
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
```

## 10. 什么时候重新 snapshot

以下情况建议重新执行：

```bash
pwcli snapshot
```

需要重新 snapshot 的场景：

- 页面跳转后
- 点击按钮后页面内容变化
- 打开或关闭弹窗
- 切换 tab
- 元素编号失效
- 命令提示找不到元素

记住：元素编号可能会过期，新的页面状态要用新的 snapshot。

## 11. 常见问题

### wrapper 没有执行权限

执行：

```bash
chmod +x "$HOME/.codex/skills/playwright/scripts/playwright_cli.sh"
```

看到类似下面这样就可以：

```bash
-rwxr-xr-x
```

### 系统找不到 Chrome

使用 Playwright 自带 Chromium：

```bash
pwcli open https://example.com --browser chromium
```

### `--headless` 报错

不要加 `--headless`。这个 wrapper 不支持该参数。

### 点击元素失败

先重新获取快照：

```bash
pwcli snapshot
```

然后使用新的元素编号。

## 12. 最常用组合

日常检查页面：

```bash
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli snapshot
pwcli console
pwcli network
pwcli screenshot
```

交互调试：

```bash
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli snapshot
pwcli click eX
pwcli snapshot
pwcli screenshot
```

移动端布局检查：

```bash
pwcli open http://localhost:8002/admin/marketing/share-scenario --browser chromium
pwcli resize 390 844
pwcli snapshot
pwcli screenshot
```

## 13. 核心记忆

Playwright 的使用顺序可以记成：

```text
open -> snapshot -> interact -> snapshot -> inspect/screenshot
```

也就是：

```bash
pwcli open URL --browser chromium
pwcli snapshot
pwcli click eX
pwcli snapshot
pwcli console
pwcli network
pwcli screenshot
```

```

```
