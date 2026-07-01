# TypeScript 的 `import type`、泛型标注与运行时校验边界

> 来源:turborepo_learning 中 Hono API 路由 `apps/api/src/routes/users.ts` 的学习会话。

## Trigger Question

> `import type` 和普通 `import` 有什么区别?  
> `c.req.json<CreateUserInput>()`、`c.json<ApiResponse<{ id: string }>>()` 分别是什么意思?  
> `const body: CreateUserInput = await c.req.json()` 和 `const body = await c.req.json<CreateUserInput>()` 是否等价?

## Key Takeaways

- `import type` 只导入 TypeScript 类型,编译成 JavaScript 后会被擦除,不产生运行时代码。
- 普通 `import` 导入运行时真实存在的值、函数、类或对象,例如 `Hono`、`desc`、`eq`、`db`、`usersTable`。
- `函数名<类型>()` 是泛型调用,意思是“这次函数调用按这个类型理解返回值或参数约束”。
- `c.req.json<CreateUserInput>()` 表示从请求 body 读取 JSON,并让 TypeScript 把结果当成 `CreateUserInput`。
- `c.json<ApiResponse<{ id: string }>>({...})` 表示返回 JSON 响应,并让 TypeScript 检查响应体符合 `ApiResponse<{ id: string }>`。
- TypeScript 类型只在编译期工作,不会自动做运行时数据校验;真实接口仍需要 validator,如 `zod`、`valibot` 或 Hono validator。

## Code Example

```ts
import type { ApiResponse, CreateUserInput, User } from "@repo/shared";
import { desc, eq } from "drizzle-orm";
import { Hono } from "hono";

// CreateUserInput 是纯类型,适合 import type
const body = await c.req.json<CreateUserInput>();

// ApiResponse<{ id: string }> 是响应体类型
return c.json<ApiResponse<{ id: string }>>({
  success: true,
  message: "创建成功",
  data: { id: String(newUser.id) },
});
```

## `import type` vs `import`

| 写法 | 导入内容 | JS 编译后 | 适用场景 |
|---|---|---|---|
| `import type { User } from "@repo/shared"` | 仅类型 | 被擦除 | `User[]`、`CreateUserInput`、`ApiResponse<T>` |
| `import { Hono } from "hono"` | 运行时值 | 保留 | `new Hono()`、调用函数、访问对象属性 |

错误示例:

```ts
import type { Hono } from "hono";

export const usersRoute = new Hono(); // 错: Hono 被当成类型导入,运行时不能 new
```

## 两种 body 写法的关系

这两种写法在当前场景下基本等价:

```ts
const body: CreateUserInput = await c.req.json();
```

```ts
const body = await c.req.json<CreateUserInput>();
```

区别只是类型标注的位置:

- `const body: CreateUserInput = ...` 是给变量 `body` 标类型。
- `c.req.json<CreateUserInput>()` 是给 `json()` 这次函数调用传泛型。

在 Hono 这类 API 里,第二种更常见,因为语义更接近“这次请求 JSON 应该按 `CreateUserInput` 解析”。

## 展开 `ApiResponse<{ id: string }>`

如果共享类型大致是:

```ts
type ApiResponse<T> = {
  success: boolean;
  message: string;
  data: T;
};
```

那么:

```ts
ApiResponse<{ id: string }>
```

等价于:

```ts
{
  success: boolean;
  message: string;
  data: {
    id: string;
  };
}
```

所以这段响应:

```ts
return c.json<ApiResponse<{ id: string }>>({
  success: true,
  message: "创建成功",
  data: { id: String(newUser.id) },
});
```

约束的是接口返回结构:

```json
{
  "success": true,
  "message": "创建成功",
  "data": {
    "id": "123"
  }
}
```

## Pitfall / Why

- `CreateUserInput` 只是编译期类型,不会保证请求真的带了 `name`、`email`。
- 前端如果传 `{ "name": 123 }`,`c.req.json<CreateUserInput>()` 本身不会自动报错。
- 生产接口需要运行时校验,否则类型标注只保护写代码的人,不保护真实用户输入。

## Related

- [[monorepo-end-to-end-type-sharing]] — `@repo/shared` 在 monorepo 中共享类型契约
- [[compiled-internal-package-dist]] — 内部包类型变更后为何需要 build
