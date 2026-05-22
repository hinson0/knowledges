# Pylance 补全排序:localityBonus 与 AST 距离

## 触发提问

> VS Code setting json 里面,如果我想要实现我自己声明的局部变量优先显示在列表的提示里面,我应该去修改哪些配置?

## 关键结论

- **`editor.suggest.localityBonus: true` 是核心**:让 Pylance 按 **AST 距离**给符号加分,光标附近声明的符号排前
- AST 距离不是"光标上方多少行",而是**抽象语法树的祖先距离**:同一函数内 > 同一 class 内 > 同一文件顶层 > 同一 package > 外部 import
- 即使设了 `localityBonus`,**`autoImportCompletions: true` 会让远处 module 通过 LSP `sortText` 高优先级绕过 localityBonus**,这是局部变量优先的**最大隐性干扰**
- VS Code 补全排序综合 4 个权重源:LSP `sortText` / localityBonus / 历史使用 / 词级 fallback;关键 setting 各控一个

## VS Code 补全排序的 4 个权重源

| 权重源 | 控制 setting | 偏好什么 |
|---|---|---|
| **LSP `sortText`** | (LSP 协议不可配) | Pylance 自己排,优先级最高 |
| **localityBonus** | `editor.suggest.localityBonus` | **光标附近**的声明加分 |
| **历史使用** | `editor.suggestSelection` | recently used 优先 |
| **词级 fallback** | `editor.wordBasedSuggestions` | 文档内出现过的词补底 |

干扰源:`python.analysis.autoImportCompletions` 让远处 module 走"高 sortText 优先级",绕过 localityBonus。

## 推荐的局部变量优先配置

```jsonc
{
  // 核心 — 必开
  "editor.suggest.localityBonus": true,

  // 把词级 fallback 收窄到「当前文档」— 远处文档的同名词不参与
  "editor.wordBasedSuggestions": "currentDocument",  // 改自 "matchingDocuments"

  // 关闭/限制 auto-import 弹出 — 否则远处 module 涌进列表跟局部变量抢
  "python.analysis.autoImportCompletions": false,    // 改自 true

  // 最近用过的(局部循环里反复 reference 的)排前
  "editor.suggestSelection": "recentlyUsed"  // 比 "recentlyUsedByPrefix" 更激进
}
```

## AST 距离的工作原理

```python
import itertools                      # 距离: 文件外 import(最远)

def my_func():
    items = [1, 2, 3]                # 距离: 同一函数顶部 - 2
    iterator = iter(items)           # 距离: 同一函数顶部 - 1
    for it in items:                 # 距离: 同一 for 块 - 0(最近)
        # 在这里打 "it" 看建议列表前 3 个:
        # 期望顺序(localityBonus 生效):
        #   1. it          ← 同一 for 块,最近
        #   2. iterator    ← 同一函数,上方 2 行
        #   3. items       ← 同一函数,上方 3 行
        #   ...
        #   后面才是 itertools / iter (外部 / global)
        pass
```

如果你打 `it` 后看到 `itertools` 排在 `iterator` / `items` 前面 → `autoImportCompletions` 在作祟,关掉。

## `suggestSelection` 三种模式对比

| 值 | 行为 | 适用 |
|---|---|---|
| `first` | 列表第一项 | 最简单,但不够智能 |
| `recentlyUsed` | 全局最近用过的优先 | 推荐 — 打 `it` 时可能预选 `items`(你刚用过) |
| `recentlyUsedByPrefix` | 按当前输入前缀找最近用过 | 更精确但偏保守(打 `it` 只看 `it...` 开头历史) |

Python 日常推荐 `recentlyUsed` — 输入到一半时通常还没足够前缀做 byPrefix 判断。

## autoImportCompletions 折中方案(不想全关)

如果想保留 auto-import 但减少排序干扰:

```jsonc
"python.analysis.autoImportCompletions": true,
"python.analysis.importFormat": "absolute",     // 强制绝对 import
"python.analysis.indexing": true,
// 等用 Ctrl+. 走 Code Action 主动 import,平时光标周围清净
"editor.suggest.snippetsPreventQuickSuggestions": false,
```

但**最干净是关 autoImport**:写 `np.array(` 时想自动 import 走 Ctrl+. 也行。

## 坑 / Why

- **`localityBonus` 是编辑器层加分,LSP sortText 是协议层优先级 — 协议层优先**:这就是为啥即使 localityBonus=true,远处 module 仍能冒到前面 — autoImportCompletions 给的 sortText 直接绕过编辑器加分
- **Pylance 的 AST 距离用的是真 AST,不是行号**:写 inner function 时,inner 内的局部变量距离 = 0,outer 的变量距离 = 1,跨 file 的 = 很多 — 行号近不等于 AST 近
- **`wordBasedSuggestions: "currentDocument"` 的代价**:在 TS 项目里,其他 .ts 文件的变量不再作为词级 fallback 出现 — 但 LSP(typescript-language-server)有 cross-file 符号建议,影响小
- **设置在 `[python]` 块 vs 全局**:`localityBonus / wordBasedSuggestions / suggestSelection` 是**编辑器行为偏好**,不是 Python 特有 — 应该放全局,所有语言一起享受
- **跟 day5 grep_code 的 "教 LLM 自救" 哲学呼应**:editor.suggest 系列设置都是"给 reasoner(IDE/LLM)精确的'距离信号'让他自己排序",而不是"工具替他做完美选择"

## 关联

- [[vscode-language-block-replace-not-merge]] — 这些设置放语言块还是全局?偏好类放全局,语言规则类放块内
- [[schema-accept-multi-output-single]] — 同款"减少 reasoner 心智负担"哲学
