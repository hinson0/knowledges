# pnpm 与 turbo 的同名 --filter:位置 + 谁解析

> 姊妹篇见 [[pnpm-filter-selection-syntax]](filter 选什么:`...` 上下游 + 必须跟动作)。本篇讲 filter **放哪**(相对子命令的位置)和 **谁在解析**(pnpm 自己 vs 透传给 turbo)。

## 触发问题

> 两条命令的区别(`--filter` 的位置):
> ```
> # ❌ 报错
> pnpm exec tsc --noEmit --filter=@repo/shared
> #   → error TS5023: Unknown compiler option '--filter=@repo/shared'
> # ✅ 正确
> pnpm --filter=@repo/shared exec tsc --noEmit
> ```
> 核心区别:`--filter` 在 `exec` 的前面还是后面。

> `pnpm dev --filter=@repo/web` 那这个怎么理解?(它把 `--filter` 放在了脚本名后面,为什么又能用?)

## 核心要点

- **pnpm 命令以「子命令 / 程序名」为分界切成两半**:之前的旗标给 pnpm 自己(`--filter`、`-r`、`-C` 等);之后的一切**原样透传**给被执行的程序。`--filter` 想被 pnpm 消费,就必须放在子命令**前面**。
- **`pnpm exec tsc --noEmit --filter=X` 报错**:`exec` 后面跑的是 tsc,`--filter` 在 tsc 之后 → 透传给 tsc → tsc 不认识 → `Unknown compiler option`。filter 被喂给了错误的人。
- **`pnpm dev --filter=X` 能用,但干活的不是 pnpm 而是 turbo**:`dev` 脚本 = `turbo run lint dev`,`--filter` 被透传后实际执行 `turbo run lint dev --filter=X`,由 **turbo** 解析(turbo 自己也有一个同名 `--filter`)。
- **pnpm 和 turbo 各有一个 `--filter`,语义相似但不是一回事**——这是全部混乱的根源。`--filter` 放脚本名后能不能用,取决于**接收方认不认**:turbo 认 ✅,vite / tsc 不认 ❌。假如 dev 脚本直接是 `vite`(不经 turbo),`--filter` 就会砸到 vite 上报错,和 tsc 那条一模一样。
- **两种「正确写法」并不等价**(最易踩的坑):`pnpm dev --filter=web`(经 turbo,跑 lint+dev、走任务图)≠ `pnpm --filter=web dev`(pnpm 直接进 apps/web 跑 vite、绕过 turbo)。详见下方。

## 命令对照

| 命令 | `--filter` 落到谁手里 | 结果 |
|------|----------------------|------|
| `pnpm exec tsc --noEmit --filter=X` | 透传给 **tsc**(程序名后) | ❌ `Unknown compiler option '--filter'` |
| `pnpm --filter=X exec tsc --noEmit` | **pnpm** 自己消费(exec 前) | ✅ pnpm 选包后在包内跑 tsc |
| `pnpm dev --filter=X` | 透传给 `dev` 脚本 → **turbo** | ✅ 由 turbo 选包 |

第 1、3 条**本质是同一种行为**(脚本/程序名后的东西原样透传),区别只在接收方认不认 `--filter`。

## 判决性测试 / 实测事实

用**不存在**的包名测试,看 pnpm 回显的真正命令、以及谁在报错(故意写错就不会真启动常驻 dev):

```text
$ pnpm dev --filter=@repo/__nope__
$ turbo run lint dev --filter=@repo/__nope__      ← pnpm 用 $ 回显它真正执行的命令
• turbo 2.9.18
  x No package found with name '@repo/__nope__' in workspace   ← turbo 的口吻,不是 pnpm 的
[ELIFECYCLE] Command failed with exit code 1.
```

证明:pnpm 没消费 `--filter`,而是拼到脚本后透传给了 turbo,是 **turbo** 在解析。

实测事实(turborepo_learning 仓库):
- 根 `dev` 脚本 = `turbo run lint dev`
- `apps/web` 自己的 `dev` = `vite --port 3000`
- turbo 版本 = 2.9.18

## 易错点·原因

**两种「跑 web 的 dev」并不等价**:

```bash
# 写法一:--filter 在后 → 透传给 turbo
pnpm dev --filter=@repo/web
#   实际执行: turbo run lint dev --filter=@repo/web
#   → 走 turbo 任务图: 先跑 lint 再跑 dev, 尊重任务依赖,
#     还会按依赖图把 web 依赖的包(@repo/shared / @repo/ui)一并纳入

# 写法二:--filter 在前 → pnpm 自己消费
pnpm --filter=@repo/web dev
#   → pnpm 进入 apps/web 目录, 直接跑它自己的 dev 脚本 = vite --port 3000
#   → 绕过根 turbo: 没有 lint, 没有任务编排
```

- **写法一**经 turbo:含 `lint`,且按 turbo 的 `dependsOn` 依赖图带上相关包。
- **写法二**绕过 turbo:只有 vite,没有 lint、没有 turbo 编排。
- 结果可能差很多。仓库里 `demo: turbo run dev --filter='@repo/demo-*'` 用的就是写法一(把 filter 交给 turbo)的思路。

**记忆模型**:

```text
pnpm [给pnpm的旗标]  <子命令/脚本名>  [原样透传给后面程序的参数]
       ↑ pnpm 消费                        ↑ 谁接收谁解析
```

- `--filter` 放**子命令前** → pnpm 选包(pnpm 的 filter)
- `--filter` 放**脚本名后** → 透传出去;能不能用,看接收方(turbo 行,vite / tsc 不行)

## 相关

- [[pnpm-filter-selection-syntax]] — 姊妹篇:filter 选什么(`...` 上下游选择器、`--filter` 是定语必须跟动作)
- [[turbo-dependson-build-order]] — 为何「经 turbo」会按依赖顺序、带上依赖包
- [[pnpm-allowbuilds-ignored-builds]] — 同属 pnpm/turbo monorepo CLI 主题
