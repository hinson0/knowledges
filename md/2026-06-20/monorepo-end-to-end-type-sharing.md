# monorepo 前后端类型贯通:共享 @repo/shared 的类型契约

> 来源:pnpm+turbo 学习会话「模块 6」。turborepo_learning 仓库中 web(react)与 api(hono)共享 `packages/shared` 的类型。

## Trigger Question

> 为什么 `apps/api/src/routes/users.ts` 和 `apps/web/src/App.tsx` 都 import 同一个 `@repo/shared` 的 `User` / `CreateUserInput`?这样做有什么价值?

## Key Takeaways

- **前后端 import 同一份类型**:api 和 web 都 `import type { User, CreateUserInput } from "@repo/shared"`,指向同一个 `packages/shared/src/types.ts`。
- **价值 = 端到端类型安全**:前后端共享同一类型契约,字段对不上 **TypeScript 当场报错**(后端给 `CreateUserInput` 加必填字段,前端调用处立即飘红),消灭一整类"字段写错/契约漂移"的运行时 bug。
- **契约由类型强制,而非靠文档/口头约定** —— 这是 monorepo 相对前后端分仓的最大优势之一。
- **`import type` 是纯类型导入**:编译后完全消失,不会把后端代码打进前端包,适合跨包共享类型。
- **`packages/ui` 把 react 设为 peerDependency**:不自带 react,借用宿主(web)的那份,避免"两个 React 实例 / Invalid hook call"。peerDependency = "我需要它,但请由用我的人提供"。

## Schema / Field Table

`import` vs `import type`:

| 写法 | 导入内容 | 编译后是否保留 | 适用 |
|---|---|---|---|
| `import { User }` | 值 + 类型 | 可能保留运行时 require | 导入真实函数/组件(如 Button) |
| `import type { User }` | 仅类型 | **完全擦除** | 跨包共享接口/类型,零运行时开销 |

前后端共享的类型(均来自 `@repo/shared`):

| 类型 | 后端用途(api) | 前端用途(web) |
|---|---|---|
| `User` | 查询返回的行映射 | 列表渲染 `users.map` |
| `CreateUserInput` | `POST` body 解析 | `createUser(input)` 表单提交 |
| `ApiResponse<T>` | `c.json<ApiResponse<...>>` 统一响应 | `json.data` 取数据 |

## Code Example

```ts
// apps/api/src/routes/users.ts —— 后端
import type { ApiResponse, CreateUserInput, User } from "@repo/shared";

// apps/web/src/App.tsx —— 前端,同一份类型
import type { CreateUserInput, User } from "@repo/shared";
import { Button, Card } from "@repo/ui";   // 注意:组件是值导入,不是 import type

async function createUser(input: CreateUserInput): Promise<void> { /* ... */ }
```

```jsonc
// packages/ui/package.json —— react 作为 peerDependency
{
  "peerDependencies": { "react": "^18.3.0", "react-dom": "^18.3.0" }
}
```

## Pitfall / Why

- **为什么是 `import type` 而非 `import`**:类型在运行时不存在,用 `import type` 明确告诉编译器"只借类型,别生成 require",避免把 shared/后端代码意外打进前端 bundle。
- **peerDependency 的坑**:若 ui 把 react 写成普通 dependency,web 和 ui 各装一份 react → 两个 React 实例 → `Invalid hook call`。设为 peerDependency 让宿主统一提供唯一一份。
- **类型变更需配合 build**:shared 是编译型内部包,改了类型要 build 才在消费方生效 —— 见 [[compiled-internal-package-dist]]。

## Related

- [[compiled-internal-package-dist]] — 改了 shared 类型为何要 build
- [[pnpm-workspace-symlink-resolution]] — @repo/shared 怎么软链解析
- [[pnpm-add-workspace-vs-version]] — workspace:* vs ^版本、peerDependency
