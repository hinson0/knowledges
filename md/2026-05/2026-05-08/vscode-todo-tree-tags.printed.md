# VS Code TodoTree 插件:让小写 `todo` 也被识别

## 问题

`# TODO`(大写)能被高亮和显示在 TodoTree 树上,但 `# todo`(小写)不会。

## 根因

TodoTree 默认配置里识别的标签列表只有大写:

```json
"todo-tree.general.tags": ["TODO", "FIXME", "BUG"]
```

## 方案一:把小写 `todo` 加入标签列表(推荐)

在 `settings.json`:

```json
"todo-tree.general.tags": ["TODO", "FIXME", "BUG", "todo"]
```

或用 `tagGroups` 把大小写归为一组:

```json
"todo-tree.general.tagGroups": {
    "TODO": ["TODO", "todo"]
}
```

## 方案二:关闭大小写敏感(全局不区分)

```json
"todo-tree.regex.regexCaseSensitive": false
```

副作用:`fixme` / `bug` 等也会变得不区分大小写,可能不够精确。

## 操作步骤

1. 命令面板(`Cmd+Shift+P`)
2. 输入 `Preferences: Open Settings (JSON)`
3. 把上面的配置加进去

**推荐方案一**,精确可控。
