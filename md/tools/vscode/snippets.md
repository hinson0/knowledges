你可以在 VS Code 中为 Python 创建多个 snippet 文件（例如 `python-langgraph.json` 和 `python-fastapi.json`），它们会自动合并，在编辑 Python 文件时全部可用。

---

### 1. 创建多个全局 Python snippet 文件

这些文件存放在用户片段目录下，所有带 `python-` 前缀的文件都会被看作 Python 语言片段。

**操作步骤：**

1. 按 `Ctrl+Shift+P` 打开命令面板，输入 **Preferences: Configure User Snippets** 并回车。
2. 选择 **New Snippets file for 'python'**（如果列表中没有，也可以手动创建文件）。
3. 输入文件名，例如 `python-langgraph.json`。
4. 重复上述步骤创建 `python-fastapi.json`、`python-myproject.json` 等。

> 只要文件名以 `python-` 开头，VS Code 就会在使用 Python 时加载其中的所有 snippet。

**示例文件** `python-langgraph.json`：

```json
// 用户片段目录：Windows 为 %APPDATA%\Code\User\snippets\
// macOS/Linux 为 ~/.config/Code/User/snippets/
{
  "LangGraph StateGraph": {
    "prefix": "lg-graph",
    "body": [
      "from langgraph.graph import StateGraph, END",
      "",
      "workflow = StateGraph(${1:State})",
      "$0"
    ],
    "description": "创建 LangGraph StateGraph"
  },
  "LangGraph add node": {
    "prefix": "lg-node",
    "body": "workflow.add_node(\"${1:node_name}\", ${2:callable})",
    "description": "添加节点"
  }
}
```

在 Python 文件中输入 `lg-graph` 并按下 `Ctrl+Space` 即可触发。

---

### 2. 按项目隔离 snippet（工作区级别）

如果你想让某些 snippet 只在特定项目中出现（比如 LangGraph 项目），可以把 snippet 文件放在该项目的 `. vscode` 文件夹内。

- 在项目根目录下创建 `.vscode` 文件夹（如果还没有）。
- 创建后缀为 `.code-snippets` 的文件。
- 如果想限制该文件中的 snippet 只对 Python 生效，有两种方式：
  - 文件名以 `python-` 开头，例如 `python-langgraph.code-snippets`（推荐）。
  - 或在每个 snippet 对象里加上 `"scope": "python"`。

**示例**（使用 scope 属性的文件 `langgraph.code-snippets`）：

```json
{
  "LangGraph StateGraph": {
    "prefix": "lg-graph",
    "body": [
      "from langgraph.graph import StateGraph, END",
      "",
      "workflow = StateGraph(${1:State})",
      "$0"
    ],
    "description": "创建 LangGraph StateGraph",
    "scope": "python"
  }
}
```

这样你就可以把不同主题的 snippet 分门别类管理了。
