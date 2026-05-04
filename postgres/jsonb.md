## 完整知识点盘点

---

### 一、JSONB `@>` 包含运算符

| 要点         | 说明                                                         |
| ------------ | ------------------------------------------------------------ |
| **语法**     | `A @> B`，判断 JSONB 类型 A 是否在顶层完全包含 B             |
| **规则**     | B 中所有 key-value 必须在 A 中存在且值相等；A 可以有多余字段 |
| **嵌套**     | 嵌套对象和数组也进行深层包含比较                             |
| **适用类型** | 仅 JSONB，普通 JSON 也可用但无索引加速                       |

```sql
WHERE products.attributes @> '{"brand":"lv","color":"red"}'::jsonb
```

**配套运算符族：**

| 运算符 | 含义                     |
| ------ | ------------------------ |
| `@>`   | 左边包含右边             |
| `<@`   | 左边被右边包含           |
| `?`    | 顶层是否包含某 key       |
| `?&`   | 是否包含所有指定 key     |
| `?\|`  | 是否包含任意一个指定 key |

---

### 二、GIN 索引（Generalized Inverted Index）

**本质：** 倒排索引，把 JSONB 文档拆解为 key/value 条目 → 行指针列表。

```
内部结构示意：
"color"  → [行1, 行2, 行3]
"red"    → [行1, 行3]
"lv"     → [行2, 行5]
```

**加速的操作：** `@>`、`<@`、`?`、`?&`、`?|`、`@?`（JSONPath）

**SQLAlchemy 写法（正确）：**

```python
idx_attributes_gin = Index(
    "idx_attributes_gin",
    attributes,                # 列表达式（直接用类体内变量名）
    postgresql_using="gin",
)
```

**对应的 SQL：**

```sql
CREATE INDEX idx_attributes_gin ON products USING GIN (attributes);
```

---

### 三、SQLAlchemy Index 定义的三个常见错误

| 错误                 | 原因                              | 正确写法                                    |
| -------------------- | --------------------------------- | ------------------------------------------- |
| 缺少列表达式         | 只传了索引名和 `postgresql_using` | 第二个位置参数必须传列                      |
| `Product.attributes` | 类体执行时 `Product` 还未绑定     | 直接用 `attributes` 或字符串 `"attributes"` |
| `self.attributes`    | 类体中没有 `self`                 | 同上                                        |

**正确模式：**

```python
class Product(Base):
    attributes: Mapped[dict] = mapped_column(JSONB, ...)

    idx_attributes_gin = Index(
        "idx_attributes_gin",   # 索引名（位置1）
        attributes,             # 列表达式（位置2，必须）
        postgresql_using="gin", # 关键字参数
    )
```

---

### 四、表达式索引 vs GIN 索引

你的 models.py 中有两种索引：

| 索引                 | 类型              | 作用                                          |
| -------------------- | ----------------- | --------------------------------------------- |
| `idx_product_price`  | B-tree 表达式索引 | 按 `attributes->>'price'` 的数值排序/范围查询 |
| `idx_product_brand`  | B-tree 表达式索引 | 按 `attributes->>'brand'` 的文本精确匹配/排序 |
| `idx_attributes_gin` | GIN 索引          | `@>` 包含查询、`?` key 存在检查等             |

B-tree 表达式索引适用于对 JSONB 内**具体字段值**的精确匹配和排序，GIN 索引适用于对整个 JSONB 文档的**包含关系**和 key 存在性查询。两者解决不同场景，可以共存。

---

### 五、EXPLAIN ANALYZE 查询计划解读

**Seq Scan（全表扫描）：**

```
Seq Scan on products  (cost=0.00..186.30 rows=39 width=254)
                      (actual time=0.061..5.406 rows=1005 loops=1)
  Filter: (attributes @> '{"brand": "lv"}'::jsonb)
  Rows Removed by Filter: 9007
```

**Bitmap Index Scan + Bitmap Heap Scan（走 GIN 索引）：**

```
Bitmap Heap Scan on products  (cost=26.45..176.27 rows=946 width=78)
  Recheck Cond: (attributes @> '{"brand": "lv"}'::jsonb)
  Heap Blocks: exact=138
  ->  Bitmap Index Scan on idx_attributes_gin
        (cost=0.00..26.21 rows=946 width=0)
        Index Cond: (attributes @> '{"brand": "lv"}'::jsonb)
```

**关键字段速查：**

| 字段                     | 含义                                                       |
| ------------------------ | ---------------------------------------------------------- |
| `cost=x..y`              | `x`=启动代价（返回第一行前的工作量），`y`=总代价（相对值） |
| `rows=N` 在估算          | 优化器预估返回几行                                         |
| `actual rows=N`          | 实际返回几行                                               |
| `Recheck Cond`           | Bitmap 扫描后需重新检查条件（GIN 可能有 hash 误报）        |
| `Heap Blocks`            | 实际读取的数据页数                                         |
| `Rows Removed by Filter` | 扫描了但被过滤掉的行数                                     |

**Bitmap Scan 的两阶段原理：**

1. **Bitmap Index Scan**：查 GIN 倒排索引，在内存构建 bitmap（位图），标记所有匹配行的物理位置
2. **Bitmap Heap Scan**：按物理顺序回表读取，将多个随机 I/O 转为顺序 I/O

---

### 六、优化器为何不走索引（四种情况）

| 情况               | 原因                                    | 解决                                       |
| ------------------ | --------------------------------------- | ------------------------------------------ |
| **表太小**（12行） | Seq Scan 成本比索引回表更低             | 正常现象，数据量大了自动切换               |
| **统计信息过期**   | 批量插入后优化器不知道表变大了          | `ANALYZE table_name;` 或等待 autovacuum    |
| **返回比例过高**   | 要返回全表 >20% 的行时，Seq Scan 更高效 | 正常现象，索引无意义                       |
| **索引未创建成功** | 定义有误（如缺少列表达式）              | `\d table_name` 检查，修正 SQLAlchemy 定义 |

**诊断命令：**

```sql
-- 强制走索引（仅测试用）
SET enable_seqscan = off;
-- 恢复
SET enable_seqscan = on;

-- 查看统计信息状态
SELECT relname, last_autoanalyze, n_mod_since_analyze
FROM pg_stat_user_tables
WHERE relname = 'products';
```

---

### 七、PostgreSQL autovacuum 与统计信息

| 要点         | 说明                                                         |
| ------------ | ------------------------------------------------------------ |
| **默认状态** | PostgreSQL 9.0+ 默认开启                                     |
| **触发条件** | 表变更比例超过 `autovacuum_analyze_scale_factor`（默认 10%） |
| **工作原理** | 后台进程定期扫描，自动执行 ANALYZE 和 VACUUM                 |
| **失效场景** | 批量写入后**立即查询**，autovacuum 还没来得及触发            |

**最佳实践：**

```sql
-- 批量导入后立即更新统计信息
BEGIN;
INSERT INTO products SELECT ... FROM generate_series(1, 100000);
ANALYZE products;  -- 即时生效
COMMIT;
```

不需要每次手动 ANALYZE，autovac
