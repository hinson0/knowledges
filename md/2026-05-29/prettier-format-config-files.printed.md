# Prettier 格式化方案的配置文件 +「.editorconfig 取舍」

> 来源:本仓库「统一代码格式化 + 本地强制」改动(分支 `chore/prettier-format-enforcement`)。
> 关键前提:本仓库真正的格式化器是 **Prettier 不是 ESLint**——ESLint 已通过 `eslint-config-prettier` 关闭所有风格规则,只管代码质量。
> **最终决策**:`.editorconfig` 已被移除,其可表达项并入 `.prettierrc.json`(见下方 Pitfall/Why)。

## Trigger Question

> 一个文件逐一解释一下。我不太明白 EditorConfig 是一个什么样的配置文件。VS Code 我的理解是,它只有 setting.json 文件作为配置文件。那这个 EditorConfig 是什么?

> .editorconfig 删掉吧,我不需要这种所谓的跨编辑器通用标准,直接把它集成在 .prettierrc.json 当中即可。

## Key Takeaways

- 配置文件分两类职责:**① 定义风格(规则本身)** 与 **② 让风格自动生效(强制 / 工具接线)**。
- 风格的"单一真相来源"是 `.prettierrc.json` + `package.json` 里锁定的 prettier 精确版本——保证全团队同一套规则、同一个格式化器。
- `.editorconfig` 本是**跨编辑器的开放标准**(非 VS Code 专有),管最底层通用排版;但本仓库几乎全是 Prettier 能处理的文件,故**最终移除**,把能表达的项并入 `.prettierrc`。
- 关键认知:`.editorconfig` ↔ `.prettierrc` **不是 1:1 可搬**——部分能搬、部分是 Prettier 内置行为无需搬、还有一部分能力(覆盖 Prettier 不管的文件)会随删除而丢失。

## 配置文件逐一说明(Field Table)

| 文件 | 类别 | 作用 |
|---|---|---|
| `.prettierrc.json` | ① 风格定义 | Prettier 规则:`semi`、双引号、`tabWidth:2`、`useTabs:false`、`endOfLine:"lf"`、80 列、尾逗号 `all`。**团队风格单一真相来源** |
| `.prettierignore` | ① 风格定义 | 告诉 Prettier **哪些不要碰**:锁文件、构建产物、graphify 生成内容、**冻结的原型参考源 `apps/prototype/`** |
| `.vscode/settings.json` | ② 自动生效 | VS Code 工作区:打开 `formatOnSave`、指定用 Prettier 作格式化器 |
| `.vscode/extensions.json` | ② 自动生效 | VS Code 插件推荐:提示装 Prettier / ESLint 插件 |
| `.lintstagedrc.json` | ② 自动生效 | lint-staged 配置:`prettier --write --ignore-unknown`,提交时只对**本次暂存文件**格式化;接进 `.githooks/pre-commit` |
| ~~`.git-blame-ignore-revs`~~ | (已移除) | 原用于记录批量格式化提交 SHA 让 `git blame` 跳过;**已按用户决定移除**,reformat 提交将照常出现在 blame 中 |
| ~~`.editorconfig`~~ | (已移除) | 原为跨编辑器底层排版标准;**已删除**,可表达项并入 `.prettierrc.json` |

## Pitfall / Why — 为什么删掉 `.editorconfig` 并入 `.prettierrc` 是合理的

**先纠误区**:`.editorconfig` 不是 VS Code 的配置,而是行业开放标准(editorconfig.org),与编辑器无关——VS Code 的 `settings.json` 才是 VS Code 专有(WebStorm/Vim 不认)。`.editorconfig` 管的是最底层通用排版:字符编码、换行符、缩进、末尾换行、去行尾空格,对任何编辑器、任何文件类型生效。

**`.editorconfig` 的设置搬到 `.prettierrc` 时分三种情况:**

| `.editorconfig` 项 | 能否搬入 `.prettierrc` | 说明 |
|---|---|---|
| `indent_size = 2` | ✅ → `tabWidth: 2` | 已有 |
| `indent_style = space` | ✅ → `useTabs: false` | 已并入 |
| `end_of_line = lf` | ✅ → `endOfLine: "lf"` | 已并入 |
| `charset = utf-8` | ➖ 无需 | Prettier **总是**输出 UTF-8,无此开关 |
| `insert_final_newline` | ➖ 无需 | Prettier **总是**补末尾换行 |
| `trim_trailing_whitespace` | ➖ 无需 | Prettier **总是**去行尾空格(Markdown 的硬换行由 Prettier 自行处理) |
| (覆盖 `.env`/纯文本等 Prettier 不管的文件) | ❌ 丢失 | 这是删除的唯一实质代价 |

**结论 / 取舍**:第 3 类(丢失)对本仓库影响很小——它几乎全是 TS/JSON/CSS/MD,都归 Prettier 管;`.env` 已被 gitignore。因此移除 `.editorconfig`、把规则集中到 `.prettierrc` 单一真相来源,反而更简洁。代价:用 WebStorm 等非 VS Code 编辑器、或编辑 `.env`/shell 等非 Prettier 文件时,不再有编辑器级的 LF/去行尾空格兜底。

**附:VS Code 与 `.editorconfig` 的冷知识**(供参考):VS Code **原生不读** `.editorconfig`,需装 `EditorConfig.EditorConfig` 插件;JetBrains 内置原生支持。

## 强制层定位

- 服务于两层**本地**强制:① 编辑器 on-save(`.vscode/*` + Prettier 读 `.prettierrc`)② pre-commit(`.lintstagedrc.json` + `.githooks/pre-commit`)。
- 第三层 CI(`prettier --check`)为规划项、当前未启用;本地两层可被 `--no-verify` / 漏装 hook 绕过,CI 才是唯一不可绕过的层。

## Related

- [[1056]] — 仓库 / monorepo 总体结构总览
- [[0753]] — apps/web 前后端边界与目录结构
