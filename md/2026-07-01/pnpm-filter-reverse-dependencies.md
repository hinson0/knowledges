# pnpm `--filter` 反向依赖查询:谁依赖了某个包

> 来源:turborepo_learning 中 pnpm workspace 依赖关系学习会话。

## Trigger Question

> `pnpm -F 某个包` 如何查看谁依赖了它?

## Key Takeaways

- `pnpm --filter` / `pnpm -F` 不是动作,只是选择 workspace 包的范围。
- 要看“谁依赖了某个包”,用左侧 `...`:
  - `...@repo/shared` = `@repo/shared` 自己 + 所有依赖它的 workspace 包。
- 要看“某个包依赖了谁”,用右侧 `...`:
  - `@repo/web...` = `@repo/web` 自己 + 它依赖的 workspace 包。
- `list --depth -1` 常用来只显示选中的包名,不展开依赖树。
- 改动基础包前,先跑反向依赖查询,可以快速判断影响范围。

## Code Example

```bash
# 查看谁依赖了 @repo/shared
pnpm --filter "...@repo/shared" list --depth -1

# 简写
pnpm -F "...@repo/shared" list --depth -1
```

如果包名是 `@repo/ui`:

```bash
pnpm -F "...@repo/ui" list --depth -1
```

## Direction Cheat Sheet

| 写法 | 含义 | 典型用途 |
|---|---|---|
| `pnpm -F "@repo/shared" list` | 只看 `@repo/shared` 自己 | 看某个包本身 |
| `pnpm -F "@repo/web..." list --depth -1` | `web` + `web` 依赖的包 | 构建一个应用需要哪些内部包 |
| `pnpm -F "...@repo/shared" list --depth -1` | `shared` + 依赖 `shared` 的包 | 查谁依赖了基础包 |
| `pnpm -F "...@repo/shared..." list --depth -1` | `shared` + 上游使用者 + 下游依赖 | 查最完整影响范围 |

简单记忆:

```txt
包名...  看它依赖谁
...包名  看谁依赖它
```

## Pitfall / Why

- `-F` 后面要跟动作,例如 `list`、`build`、`test`、`exec pwd`;只写 `pnpm -F "...@repo/shared"` 不是完整命令。
- 建议给 filter 表达式加引号,例如 `"...@repo/shared"`,避免 shell 解析带来干扰。
- `...` 只沿 workspace 中真实声明的依赖关系走;如果某个包没有在 `package.json` 里声明依赖,它不会出现在反向依赖结果里。

## Related

- [[pnpm-filter-selection-syntax]] — `pnpm --filter` 的 `...` 上下游完整说明
- [[pnpm-workspace-symlink-resolution]] — workspace 依赖声明与软链解析
