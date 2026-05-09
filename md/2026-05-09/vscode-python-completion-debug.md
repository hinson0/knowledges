# VS Code Python 代码补全失效 · 三层机制排查指南

> 来源:Week 2 · Day 3 中途遇到的 IDE 问题
> 关键词:Pylance / wordBasedSuggestions / snippetSuggestions / 解释器漂移

---

## 一句话总结

**VS Code 的 Python 补全不是单一系统,而是 3 套独立机制并存:Pylance(语义补全) + 编辑器关键字 + 单词补全。任何一层失效,表现都是"打字没提示",但根因和修复方式完全不同。**

---

## 一、问题现象

- 在 `.py` 文件里输入 `pr` 不再提示 `print` 等以 `pr` 开头的关键字
- 但输入 `os.ch` 却能正常提示 `chdir`、`chflags` 等方法
- Reload VS Code 后短暂恢复,运行 Jupyter cell 后又失效

---

## 二、根本原因(共三层)

补全失效不是单一原因,而是**三个独立问题叠加**导致的。理解这一点很关键:**Pylance 智能补全和 VS Code 关键字/单词补全是两套独立机制**。

| 现象                               | 归属机制              | 失效时的表现                       |
| ---------------------------------- | --------------------- | ---------------------------------- |
| 打 `os.` 后弹出方法列表            | Pylance(语言服务器) | 没提示 = Pylance 出问题            |
| 打 `impo` 弹出 `import`            | VS Code 编辑器本身    | 没提示 = editor 设置问题           |
| 打 `pr` 弹出代码里出现过的 `print` | VS Code 单词补全      | 没提示 = wordBasedSuggestions 关了 |

### 原因 1 · `editor.wordBasedSuggestions` 被关闭

```json
"[python]": {
    "editor.wordBasedSuggestions": "off"  // ❌ 这导致基于单词的补全完全失效
}
```

### 原因 2 · Python 解释器在 venv 和全局之间反复切换

Pylance 日志里能看到 pythonPath 在 `.venv/bin/python` 和 `/usr/local/bin/python3` 之间反复横跳,每次切换都触发整个项目(176 个文件)重新索引,索引期间补全质量大幅下降。

**触发原因**:Jupyter notebook 选择的 kernel 与 VS Code 选择的解释器不一致。

### 原因 3 · `editor.snippetSuggestions: "inline"` 让关键字 snippet 不出现在补全列表

```json
"editor.snippetSuggestions": "inline"  // ❌ 关键字以"内联灰字"显示,容易被误以为没补全
```

这是 **"打 impo 不提示"的真正元凶** — 关键字补全压根没经过 Pylance,是 VS Code 编辑器层的设置问题。

---

## 三、解决方案

### 1. User settings.json 关键修改

```json
{
  // 全局:让 snippet 显示在补全列表顶部,而不是 inline
  "editor.snippetSuggestions": "top",

  "[python]": {
    // 启用所有上下文的快速补全
    "editor.quickSuggestions": {
      "other": "on",
      "comments": "off",
      "strings": "on"
    },
    // 显式开启关键字和 snippet 补全(关键修复点)
    "editor.suggest.showKeywords": true,
    "editor.suggest.showSnippets": true,
    // 启用基于已有文档单词的补全
    "editor.wordBasedSuggestions": "matchingDocuments",
    // 其他常规配置
    "editor.defaultFormatter": "charliermarsh.ruff"
  }
}
```

### 2. 锁定项目的 Python 解释器

在项目根目录创建 `.vscode/settings.json`(workspace 级别):

```json
{
  "python.defaultInterpreterPath": "./.venv/bin/python",
  "python.terminal.activateEnvironment": true
}
```

然后在 Jupyter notebook 里也手动选择同一个 `.venv` 的 Python 作为 kernel,避免触发解释器切换。

### 3. 避免误伤其他语言

不要在顶层设置 `editor.defaultFormatter` 为某个特定语言的 formatter(如 ruff 只能格式化 Python)。把 formatter 配置放到对应语言的 `[language]` 段里。

---

## 四、排查方法论(最重要的部分)

遇到 VS Code 补全问题,按这个顺序定位:

### Step 1 · 分清楚是哪一层的补全失效

打 `os.` 有没有提示?

- 有 → Pylance 正常,问题在 editor 设置
- 没有 → Pylance 出问题,看下一步

### Step 2 · 看 Pylance 输出日志

`查看 → 输出` → 右上角下拉选 `Pylance`

重点看:

- `pythonPath` 有没有反复变化(解释器切换问题)
- 有没有大量 `failed to parse docstring` 警告(docstring 卡死 Pylance)
- 索引数 `Found N source files` 是否稳定

### Step 3 · 检查 VS Code 状态栏

- 右下角 Python 解释器显示的是不是预期的那个(`.venv` vs 全局)
- `Cmd+Shift+P` → `Developer: Show Running Extensions` 看 Pylance 是否正常激活

### Step 4 · 让 VS Code 帮你验证配置

- 任何不存在或已弃用的设置项,VS Code 都会用波浪线和「未知的配置设置」提示出来
- 不要凭印象填配置,写完看看有没有警告

### Step 5 · 应急手段

- `Cmd+Shift+P` → `Python: Restart Language Server`(重启 Pylance,不用重启整个 VS Code)

---

## 五、参数速查表

### `quickSuggestions` 的三个键

| 键         | 含义           | 推荐值  |
| ---------- | -------------- | ------- |
| `other`    | 普通代码区域    | `"on"`  |
| `comments` | 注释里         | `"off"` |
| `strings`  | 字符串里       | `"on"`  |

值可以是 `"on"` / `"off"` / `"inline"`。

### `snippetSuggestions` 的四个值

| 值         | 含义                                    |
| ---------- | --------------------------------------- |
| `"top"`    | 列表顶部 ⭐ **推荐**                    |
| `"bottom"` | 列表底部                                 |
| `"inline"` | 内联灰字 ❌ 容易让人以为没补全          |
| `"none"`   | 关闭                                     |

### `wordBasedSuggestions` 的取值

| 值                     | 范围                                  |
| ---------------------- | ------------------------------------- |
| `"off"`                | 关闭                                   |
| `"currentDocument"`    | 仅当前文件                             |
| `"matchingDocuments"`  | 同语言所有打开文件 ⭐ **推荐**        |
| `"allDocuments"`       | 所有打开文件                           |

---

## 六、三种补全的来源(理论)

| 来源                  | 提供什么                            |
| --------------------- | ----------------------------------- |
| Pylance               | 属性、方法、类型推导                 |
| VS Code keywords      | 语言关键字 `import` / `def` / `class` |
| VS Code snippets      | 代码片段                             |
| VS Code word-based    | 基于当前文档已出现单词               |

**任何一种失效,都表现为"打字没提示"**,但修法完全不同。所以诊断顺序很重要。

---

## 七、相关教训(可迁移)

- **"看起来同一个症状,可能是多个独立 bug 叠加"** —— Step 1 的"分清是哪一层"是诊断技巧的核心,任何复杂系统排查都该先做这步
- **"配置文件警告不要忽略"** —— VS Code 对未知配置项有黄色波浪线,大部分人视而不见,但它正是配置改坏的最早信号
- **"索引漂移 = 工具链不稳定的最强信号"** —— 任何 IDE / 编译器 / 解析器,只要看到"反复重新索引",立即怀疑解释器/配置在抖动,而不是怀疑代码

_问题排查日期:2026-05-09_
