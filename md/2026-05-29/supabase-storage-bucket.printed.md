# Supabase Storage Bucket(存储桶)

## Trigger Question

> Supabase 里面的 Storage 的 Bucket 是什么意思?这个 bucket 怎么理解?

## Key Takeaways

- **bucket = Supabase Storage 里一个有名字、有独立访问规则的「顶层文件容器」**。存文件必须先选一个桶;桶是创建、命名、设权限的基本单位。
- 类比:Storage 像云端网盘,一个 bucket 像网盘里一个顶层「大文件夹 / 盘」(如「头像」一个桶、「参考图」一个桶),各自独立、可分别设公开/私有。
- 名字来自 Amazon S3(对象存储鼻祖);Supabase Storage 底层是 S3 兼容对象存储,「桶」是顶层命名空间的行业叫法。
- **桶里的「文件夹」是假的**:`u1/1716-abc.png` 整串是文件的名字(key),`/` 只是名字里的字符;对象存储没有真目录树,只有「桶 + 一堆带路径名的文件」。
- Public 桶:每个文件有永久公开 URL,免登录可读(直接塞 `<img src>`);Private 桶:需签名 URL / 鉴权才能读。

## Schema / 概念结构

桶内布局(name 就是带 `/` 的完整 key):

```
reference-images          ← 桶名(bucket)
  ├── u1/1716-abc.png       ← 文件 name = "u1/1716-abc.png"
  ├── u1/1717-def.png
  └── anon/1718-xyz.png
```

| 桶类型     | 访问方式                              | 适合              |
| ---------- | ------------------------------------- | ----------------- |
| Public     | 文件有永久公开 URL,任何人免登录可打开 | 头像、参考图等要展示的 |
| Private    | 必须签名 URL / 鉴权                    | 合同、隐私文件    |

## 本项目对应

- 桶名 `reference-images`,设为 **public**。
- 上传文件名 `${userId ?? "anon"}/${时间戳}-${随机}.${ext}`,第一段是用户 id 或 `anon`。
- 上传成功调 `getPublicUrl()` 拿公开 URL,回写进参考图卡片的 `<img>`。

## Related

- [[supabase-storage-rls-policy]] — 桶里「谁能写哪个文件夹」的权限规则
- [[reference-image-upload-flow]] — 文件怎么进桶、怎么变成卡片里的图
