# pnpm 构建脚本拦截 (ERR_PNPM_IGNORED_BUILDS) 与 allowBuilds 配置

## 触发问题

> `pnpm i` 后输出：
> ```
> [ERR_PNPM_IGNORED_BUILDS] Ignored build scripts: better-sqlite3@12.10.0, esbuild@0.18.20, esbuild@0.21.5, esbuild@0.25.12, esbuild@0.28.0
> Run "pnpm approve-builds" to pick which dependencies should be allowed to run scripts.
> ```
> 为什么会报错？

> （针对 pnpm-workspace.yaml 里 `allowBuilds: { better-sqlite3: set this to true or false }` 的占位符）
> "set this to true or false" 应该是 true or false 吧？

## 核心要点

- **这不是致命报错**：安装本身已成功（上面有 `Already up to date`）。`ERR_` 只是 pnpm 错误码命名前缀，这条是**安全拦截通知**，不中断安装。判断成败看退出码 / 有没有 `Done`，别看这行字。
- **pnpm v10 起默认行为变了**：不再自动执行依赖包的生命周期脚本（`preinstall` / `install` / `postinstall`）。目的是防**供应链攻击**——被投毒的包只要在 `postinstall` 写恶意代码，install 瞬间就被执行。所以 pnpm 改为「列出需要跑脚本的包，让你手动批准白名单」。
- **被拦的是正经包**：`better-sqlite3` 要在 postinstall 编译原生 C++ 模块（node-gyp 产出 `.node`）；`esbuild` 要下载对应平台的二进制。pnpm 不替你判断谁是好人，一律先拦下来问。
- **隐患在运行时**：esbuild 二进制没装好 → `vite` / `turbo build` 会挂；better-sqlite3 没编译 → 连数据库时才报错。所以该处理，别忽略。
- **配置字段随版本变化**（最大的坑，见下）。本机 pnpm 11.8.0 用的是 `allowBuilds`。

## 配置示例

pnpm **v11** 的写法（放在 `pnpm-workspace.yaml` 或 package.json 的 `pnpm` 字段下），是**「包名 → 布尔值」的映射表**：

```yaml
# pnpm-workspace.yaml (pnpm v11+)
allowBuilds:
  better-sqlite3: true       # true  = 允许它跑构建脚本
  esbuild: true
  core-js: false             # false = 明确禁止（且不再提示）
  nx@21.6.4 || 21.6.5: true  # 支持带版本匹配的 key
```

改完执行让它们真正构建一次：

```bash
pnpm rebuild
# 或交互式批准（会自动把正确配置写进 pnpm-workspace.yaml）：
pnpm approve-builds
```

相关 settings：
- `strictDepBuilds`（默认 `true`）：检测到未审核的构建脚本就让安装失败。
- `dangerouslyAllowAllBuilds`（默认 `false`）：全部放行，不推荐。

## 易错点 / 原因

**坑 1：为什么填了 `allowBuilds` 还一直警告？**
项目里那段是占位符：
```yaml
allowBuilds:
  better-sqlite3: set this to true or false   # ← 不是合法布尔值
  esbuild: set this to true or false
```
`set this to true or false` 是**字面提示**——让你把值填成 `true` 或 `false`。它不是合法布尔，pnpm 解析不了 → 视为「未决定」→ 继续拦截并提示。把值改成 `true` 即可。

**坑 2：v10 与 v11 配置字段不一样（版本迁移陷阱）**

| 版本 | 字段 | 形态 | 示例 |
|------|------|------|------|
| pnpm v10 | `onlyBuiltDependencies` | **白名单数组**（列进去=允许） | `onlyBuiltDependencies: [better-sqlite3, esbuild]` |
| pnpm v11 | `allowBuilds` | **布尔映射**（可同时表达允许/拒绝） | `allowBuilds: { esbuild: true, core-js: false }` |

v11 把旧的 `onlyBuiltDependencies` / `neverBuiltDependencies` 合并进了一个 `allowBuilds`。好处：能同时表达「允许」和「明确拒绝」，还支持 `nx@21.6.4 || 21.6.5: true` 这种带版本匹配的 key。

> 自查记录：起初我凭 v10 旧记忆，断言「`allowBuilds` 不存在、应该用 `onlyBuiltDependencies` 数组」——**错了**。用户指出值应为 true/false 后，两路验证确认 `allowBuilds` 才对：① 官方 v11 settings 文档；② 本机 `/opt/homebrew/lib/node_modules/pnpm/dist` grep `allowBuilds` 出现 16 次。**教训：库的版本化配置不要凭记忆，按当前安装版本查文档 + 本地二进制实测。**

## 相关

- [[turbo_persistent]]
