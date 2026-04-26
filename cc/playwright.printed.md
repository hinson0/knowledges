# `playwright@claude-plugins-official` 插件

## 一句话定位

**它是 MCP 服务器注册插件**,不是 slash command 也不是 skill — 启用后 Claude 就能操作真实浏览器(打开网页、截图、点击、填表)。

## 拆解

插件目录结构极简,只有两个文件:

```
~/.claude/plugins/cache/claude-plugins-official/playwright/unknown/
├── .claude-plugin/plugin.json   # 插件元数据
└── .mcp.json                    # MCP 服务器配置
```

`.mcp.json` 内容:

```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest"]
  }
}
```

**本质**:启用这个插件 = 在 Claude Code 里接入了 **Microsoft 官方的 Playwright MCP 服务器**(`@playwright/mcp`)。插件自己**没有任何逻辑代码**,只是"声明了一个 MCP 依赖"。

## 能力

启用后 Claude 会多出一批 `mcp__playwright__*` 工具:

| 能力 | 典型动作 |
|------|---------|
| 导航 | 打开 URL、前进/后退 |
| 交互 | 点击按钮、输入文本、选下拉 |
| 截图 | 截当前页面(给 Claude 看) |
| 断言 | 验证元素是否存在/可见 |
| 抓取 | 读取 DOM 文本、HTML、URL |

## 和相似插件的区别(关键对比)

| 插件 | 作用 | 场景 | 产物 |
|------|------|------|------|
| `frontend-design` | **生成**高质量前端代码 | "做个登录页" | 源码文件 |
| `playground` | **生成**单文件可交互 HTML 探索器 | "做个色卡调色工具" | 单个 HTML 文件 |
| `playwright` | **操作**真实浏览器 | "打开这个页面,截图看布局有没有问题" | 截图 / DOM 数据 |

前两者是"画图师",后者是"机器手"。

## 什么时候它真的有用

1. **前端自测闭环** — CLAUDE.md 里有"UI 改动后必须在浏览器里验证"之类规则时,playwright 让 Claude 能自己打开 Expo Web / Storybook 截图自查,不用人工截图
2. **抓资料** — 给 Claude 一个 URL,让它自己打开、提取结构化数据(比 WebFetch 更强,能处理 JS 渲染页面)
3. **E2E 脚本辅助** — Claude 读页面结构后反向生成 Playwright 测试脚本

## 对 coco 项目的现实度

- ✅ **Expo Web 模式**(`pnpm dev` 的 web 输出):可以让 Claude 截图验证 UI
- ⚠️ **原生 iOS/Android**(Expo Go 真机):playwright 控不了,只能走 Detox / Maestro 等移动端 E2E
- ⚠️ **首次调用延迟**:`npx @playwright/mcp@latest` 首次会下载包,可能有 10s+ 等待

## 启用后的隐性代价

- **context 占用**:MCP 服务器的工具定义会进每次对话 context(几十个工具 schema)
- **权限提示**:首次用各种 playwright 工具时会挨个弹权限窗
- **npm 运行**:本地需要 node + npx 环境

如果当前主要在做移动端开发,`playwright` 的性价比不如 `frontend-design`。可以 `/smart:op` 按项目类型禁用它节省 context。

## 关键记忆点

> Playwright 插件 ≠ 写 Playwright 测试代码的助手。它是"让 Claude 自己操纵浏览器"的工具。
>
> 想让 Claude 帮你写 Playwright 测试代码,不用启用这个插件 — 它只是增加 Claude 的"手脚",不增加它对 Playwright API 的知识。
