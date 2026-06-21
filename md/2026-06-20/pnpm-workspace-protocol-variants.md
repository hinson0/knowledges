# pnpm workspace: 协议的取值变体(* / ~ / ^ / 固定版本)

> 来源:pnpm+turbo 学习会话「Q&A」。承接 [[pnpm-add-workspace-vs-version]](`workspace:*` 链本地 vs `^版本` 走 npm),本篇专讲 `workspace:` 协议内部的多种写法。

## Trigger Question

> `workspace:*` 的 `*` 还能换成别的值吗?

## Key Takeaways

- `workspace:` 协议**不止 `*` 一种**,常见有:`workspace:*`、`workspace:~`、`workspace:^`、`workspace:<具体版本/范围>`,外加别名写法。
- **它们的差别只在"发布到 npm 那一刻"才有意义**:pnpm publish 时会把 `workspace:` 前缀**改写成一个真实版本号/范围**(因为发到 npm 后别人没有你的工作区,必须给真实版本)。
- **开发期行为完全一致**:不管写 `*`/`~`/`^`,本地都是"链到工作区里的那个包",没有任何区别。
- **私有(`private: true`)/永不发布的 monorepo:用 `workspace:*` 即可**。`~`/`^` 是给"要发 npm 的开源库 monorepo"做版本范围策略用的。本项目所有包都是 private,`*` 是最省心的默认。
- 还有**别名**写法:`"my-shared": "workspace:@repo/shared@*"`,用于把内部包重命名后引入。

## Schema / Field Table

各写法对照(假设被依赖包当前版本是 1.5.0):

| 写法 | 本地行为 | 发布时替换为 |
|---|---|---|
| `workspace:*` | 链本地 | `1.5.0`(锁死精确版本) |
| `workspace:~` | 链本地 | `~1.5.0`(允许 patch:1.5.x) |
| `workspace:^` | 链本地 | `^1.5.0`(允许 minor:1.x) |
| `workspace:1.5.0` / `workspace:>=1.5.0` | 链本地(若版本满足) | 原样 `1.5.0` / `>=1.5.0` |
| `<别名>@workspace:*` | 链本地并重命名 | 解析为对应包的精确/范围版本 |

## Code Example

```jsonc
// 某个 app 的 package.json —— 几种 workspace: 写法
{
  "dependencies": {
    "@repo/shared": "workspace:*",                 // 最常用,发布锁精确版本
    "@repo/ui": "workspace:^",                      // 发布时变 ^x.y.z
    "@repo/utils": "workspace:~1.5.0",              // 指定基线
    "my-shared": "workspace:@repo/shared@*"         // 别名引入内部包
  }
}
```

## Pitfall / Why

- **`*` / `~` / `^` 的区别在"发包"时才显现**:很多人以为它们影响本地链接行为,其实本地完全一样(都链工作区)。真正不同的是 `pnpm publish` 把前缀改写成什么版本范围,决定下游消费者拿到的版本约束。
- **不发布就别纠结**:private monorepo(如本项目)永远不会触发发布替换,`workspace:*` 一把梭即可,无需考虑 `~`/`^`。
- 对照另一条易混点:`"@repo/shared": "workspace:*"`(链本地)与 `"zod": "^4.4.3"`(走 npm)的区别,见 [[pnpm-add-workspace-vs-version]] —— 那是"本地 vs npm"的区别,本篇是"workspace 协议内部"的区别,两者别混。

## Related

- [[pnpm-add-workspace-vs-version]] — workspace:* vs ^npm版本(链本地 vs 下载)
- [[pnpm-workspace-symlink-resolution]] — workspace 软链解析与"谁声明谁才有"
