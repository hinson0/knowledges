```
NULLIF(
  BTRIM(leadSubmission.normalized_payload ->> 'product'),
  ''
) AS normalized_product,
```

这段 SQL 从 `normalized_payload` JSON 中读取标准化后的 `product`：

```text
->> 'product'  取出 product 文本
BTRIM(...)     去除首尾空格
NULLIF(...,'') 空字符串转为 NULL
AS normalized_product  查询结果命名
```

例如 `" product ": " 海豹06 "` 最终得到 `normalized_product = "海豹06"`；没有有效值则为 `NULL`。
