# Supabase Storage RLS 上传策略(按用户隔离)

## Trigger Question

> create policy "ref images: authed insert own folder" on storage.objects for insert to authenticated with check ( bucket_id = 'reference-images' and ( (storage.foldername(name))[1] = auth.uid()::text or (storage.foldername(name))[1] = 'anon' ) ); 这个是什么意思?

## Key Takeaways

- 一句话:**登录用户能往 `reference-images` 桶上传,但只能传进「以自己用户 id 命名的文件夹」(或公共 `anon` 文件夹),不能塞进别人的文件夹。** 这是 Supabase 的行级权限(RLS)。
- Supabase 把每个上传的文件记成 `storage.objects` 表里的一行;策略是给这张表加访问规则。
- `name` 是文件在桶内的完整路径;`storage.foldername(name)` 按 `/` 切成数组,`[1]` 取第一段(PG 数组从 1 开始)。
- `auth.uid()` 是当前登录用户 UUID,`::text` 转文本比较 → 第一段必须等于你的 id。
- 作用 = **用户隔离**:A 用户无法往 B 用户文件夹写 / 覆盖。

## Code Example

```sql
create policy "ref images: authed insert own folder"
on storage.objects for insert to authenticated      -- 只管 insert(上传),只对登录用户
with check (                                          -- 每次上传必须满足:
  bucket_id = 'reference-images'                      -- 只对这个桶生效
  and (
    (storage.foldername(name))[1] = auth.uid()::text  -- 最外层文件夹 = 你的用户 id
    or (storage.foldername(name))[1] = 'anon'         -- 或者就叫 anon(兜底路径)
  )
);
```

| 片段                            | 含义                                  |
| ------------------------------- | ------------------------------------- |
| `on storage.objects`            | 每个文件是这张表的一行,给它加规则     |
| `for insert to authenticated`   | 只管上传动作,只对已登录用户           |
| `with check (...)`              | 不满足条件则数据库拒绝插入             |
| `bucket_id = 'reference-images'`| 只管这个桶                            |
| `(storage.foldername(name))[1]` | 路径(如 `u1/1716-abc.png`)第一段 = `u1` |
| `= auth.uid()::text`            | 必须等于当前用户 id                   |
| `or ... = 'anon'`               | 或文件夹叫 anon                       |

## Pitfall / Why

- 「按用户隔离」本质是 **文件名前缀约定 + 一条 RLS**,不是真有用户目录(对象存储没目录树)。
- 跟代码闭环:上传路径 `${userId ?? "anon"}/...`(`reference-image.ts`)正好让第一段 = id 或 anon,符合策略。

## Related

- [[supabase-storage-bucket]] — bucket 概念、public/private
- [[reference-image-upload-flow]]
