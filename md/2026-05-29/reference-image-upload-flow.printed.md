# 参考图上传数据流(本地预览 + 异步传 Supabase)

## Trigger Question

> 增加图片上传的功能,这个图片作为参考图片。
>
> 点上传 → 进哪个桶 → 存成什么名 → 怎么变成卡片里那张图?

## Key Takeaways

- 设计 = **本地先显示 + 后台异步传**:①~④ 全是浏览器本地操作(零网络),只有第 ⑤ 步才联网传 Supabase。
- 卡片里看到的图是 **本地 blob 预览**(`previewUrl = URL.createObjectURL(file)`),不是从 Supabase 拉回来的 → 即使没配 / 上传失败,图照样显示。
- `remoteUrl`(Supabase 公开链)存下来给后续「快捷动作」用:`origSrc = remoteUrl ?? previewUrl`(优先持久化的远程图)。
- 上传失败不阻断:`status:"error"` + toast「保存失败 · 本地可用」,本地预览仍在。
- 校验先行:类型 jpg/png/webp + ≤10MB(`validateReferenceFile`,纯函数),不合格弹 toast 不建卡。

## 数据流

```
① 点「上传参考图」→ fileInputRef.current?.click()(隐藏 <input type=file>)
② 选文件 → onChange → onFilePicked(e)
③ validateReferenceFile(file)   ├ 不合格 → toast,结束   └ 合格 ↓
④ 本地预览(不联网):previewUrl = URL.createObjectURL(file)
   setAttached({previewUrl,name,size,remoteUrl:null,status:"uploading"})
   → 卡片立即显示缩略图 + 真实文件名/大小 + 「上传中…」
⑤ 后台异步:uploadReferenceImage(file, user?.id)
   path = `${userId ?? "anon"}/${Date.now()}-${rand}.${ext}`
   supabase.storage.from("reference-images").upload(path,file) → getPublicUrl
   ├ 成功 .then → patchIfCurrent({remoteUrl,status:"done"}) → 「已保存」
   └ 失败 .catch → patchIfCurrent({status:"error"}) + toast「保存失败 · 本地可用」
```

## Pitfall / Why

- `previewUrlRef` 与 `attached.previewUrl` 看似重复,实则分工:前者是「可释放资源句柄」,用于卸载/替换时 `revokeObjectURL`(不依赖渲染、不踩陈旧闭包);后者是渲染用的 state。
- `patchIfCurrent` 用 `cur.previewUrl === previewUrl` 守卫:防止「换图后旧图的上传结果回来覆盖新状态」(陈旧异步)。
- 关键字提取 + 图片本地预览 **完全不需要后端**;只有「持久化到 Supabase」才需建桶 + 配 `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY`。没配好时上传降级,本地预览不受影响 —— 这是预期,不是 bug。

## 三个产物落点

| 产物              | 在哪                                    | 谁用                 |
| ----------------- | --------------------------------------- | -------------------- |
| previewUrl(blob) | 内存(createObjectURL)                 | 卡片缩略图、立即预览 |
| 文件实体          | Supabase 桶 reference-images,名 `u1/...png` | 持久化               |
| remoteUrl(公开链)| getPublicUrl 返回                       | 存 attached.remoteUrl,给 quick task |

## Related

- [[supabase-storage-bucket]]
- [[supabase-storage-rls-policy]]
