# VS Code 语言块的 dict 配置是「替换」不是「合并」

## 触发提问

> 这样子调整会有什么影响吗?[把 quickSuggestions 从 [python] 块提到全局]

> 我的这样的调整之后,还有什么需要去调整的吗?

## 关键结论

- VS Code 的 `[language] { ... }` 语言块里**任何 object-typed 设置**(dict 类型,如 `editor.quickSuggestions` / `editor.codeActionsOnSave`)**整体替换**全局同名 key,**不是 deep-merge**
- "双胞胎坑":`editor.quickSuggestions` 和 `editor.codeActionsOnSave` 都是这个机制的受害者 — 你以为只覆盖了一个子 key,实际整个 object 被替换,其他子 key 走 VS Code 默认值
- **修复口诀**:在语言块里写任何 dict-typed setting,如果全局也设了同名 key,**务必把全局的所有子 key 也复制一份进来**,否则全局值在该语言里"消失"
- VS Code 选 replace 不选 merge 的设计理由:deep-merge 对 array / 嵌套 dict 的语义不可预测,replace 简单确定 — 但这个规则**藏在文档很深的地方**,反复咬人

## 受影响的两个常用配置

### 1. `editor.codeActionsOnSave`

```jsonc
// ❌ 出 bug 的写法
{
  // 全局
  "editor.codeActionsOnSave": {
    "source.organizeImports": "explicit"
  },
  "[python]": {
    // ⚠ 整体替换 — organizeImports 在 Python 文件里失效!
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit"
    }
  }
}

// ✅ 正确写法
{
  // 全局
  "editor.codeActionsOnSave": {
    "source.organizeImports": "explicit"
  },
  "[python]": {
    // 显式把全局的子 key 也写进来
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"   // ← 必须重复写
    }
  }
}
```

### 2. `editor.quickSuggestions`

```jsonc
// 全局
"editor.quickSuggestions": {
  "strings": "on",
  "other": "on",
  "comments": "off"
}

// [markdown] 块如果只想覆盖 strings:
"[markdown]": {
  "editor.quickSuggestions": {
    "strings": "on"
    // ⚠ 没写 "other" / "comments" → 走 VS Code 默认(other:on, comments:off)
    //   恰巧跟全局一致,看起来"没出 bug",但语义上是替换不是合并
  }
}

// [json] / [jsonc] 块覆盖关掉(避免在 JSON 字符串值里弹建议干扰):
"[json]": {
  "editor.quickSuggestions": { "strings": "off" }
  // ↑ 只写 strings,other 和 comments 走默认值
}
```

## 调试 / 验证方法

写一段最小 case 在 Python 文件里测:

```python
import os    # unused
import sys   # unused
from pathlib import Path
x = Path("/tmp")
```

**Ctrl+S 保存**,看:
- 全局 `source.organizeImports: "explicit"` + Python 块**只**写 `source.fixAll` → unused imports 仍在 → 证明 organizeImports 被替换掉了
- 把 `source.organizeImports` 加进 Python 块 → unused imports 自动删除 → 修复成功

## Ruff 扩展专属 ID(消黄线警告)

VS Code 报"未知的配置设置"是 JSON schema validation 误报(false positive)。Ruff 扩展贡献了**带 `.ruff` 后缀**的专属 action ID 到 schema:

```jsonc
"[python]": {
  "editor.codeActionsOnSave": {
    "source.fixAll.ruff": "explicit",            // 不报警告
    "source.organizeImports.ruff": "explicit"    // 不报警告
  }
}
```

跟裸 ID(`source.fixAll`)功能等价,但 schema 校验能通过。带后缀也明确"我就要 Ruff 来做",防止以后装别的 Python LSP 引起冲突。

## VS Code Schema 验证 vs 运行时是两套系统

- **Schema validation**(黄线警告):**静态检查**,只看 VS Code core + 已注册扩展贡献的 JSON schema
- **运行时**(`codeActionsOnSave` 触发那刻):**动态查询 action providers**,会问所有 active 扩展"你认领 source.organizeImports 吗?",有人认领就跑
- **两者经常不同步** — 扩展把 action 注册到 provider 但忘了同步到 schema → 出现"功能正常但黄线警告"
- 这不光 Ruff,Pyright / Pylint / Mypy 都有过类似 issue
- **判断真假 false positive**:实测一下功能是否真生效;**功能真生效 → 黄线可忽略 / 改用 `.ruff` 后缀消警告**

## 坑 / Why

- **"全局化 vs 语言专属"的判断口诀**:一条设置是否该全局化,看它**是"我对编辑器行为的偏好"**还是"这个语言特有的格式规则"
  - 偏好类(`localityBonus / suggestSelection / wordBasedSuggestions`)→ 全局
  - 语言规则类(`tabSize / defaultFormatter / formatOnType`)→ 块内
- **4 个 TS/JS/JSX 语言块完全相同 = VS Code 限制**:`[typescript]` / `[javascript]` / `[typescriptreact]` / `[javascriptreact]` 不能继承,只能复制粘贴 4 份 — 加注释提醒"改一个要同步改 4 个"
- **markdown 块的 strings:on 让 strings:off 默认变成 on?** 不会——object 是替换不是合并,markdown 块的 `{"strings": "on"}` 整体替换全局 → 其他子 key(other / comments)走 **VS Code 默认值**(other:on / comments:off),不是全局值
- **这跟 LLM 工具 schema 设计的对应教训**:LLM 入参的字段语义是替换还是合并,**默认行为必须文档化**,不然 LLM 调用会一直出错(day5 的 `_normalize_globs` 做的就是显式归一化,避免下游分支)

## 关联

- [[claude-md-import-syntax]] — 跟语言块替换/合并的"语义不确定"是同一类配置坑
- [[schema-accept-multi-output-single]] — LLM 工具应该显式做形态归一化,避免下游踩这种坑
