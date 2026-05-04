你这次的查询 `select age from users where age=39` 得到了一个**Index Only Scan**（仅索引扫描），执行时间只有 **20.865 ms**，相比之前 `select *` 的 583 ms 快了近 **30 倍**。我们来拆解这个现象。

---

### 1. 为什么是 Index Only Scan？

- **查询只涉及 `age` 列**，而 `idx_users_age` 索引正好包含了 `age` 列（以及主键 `id` 作为隐藏的索引元组）。
- 优化器判断：索引**覆盖了查询需要的所有列**，因此不必回表读取堆（Heap），可以直接从索引中取出数据。这就触发了 **Index Only Scan**。
- 对比之前的 `select *`，因为需要返回 `username`, `email`, `is_active` 等索引不包含的列，必须回表，所以只能走 `Bitmap Heap Scan`。

---

### 2. `Heap Fetches: 4` 是什么意思？

尽管理想情况下 Index Only Scan 应当零回表，但实际仍可能出现少量 `Heap Fetches`：

- **可见性检查**：PostgreSQL 的多版本机制要求检查索引元组对应的堆行是否对当前事务可见。通常这会使用索引上的**可见性映射（Visibility Map）**快速判断，如果映射表明该页面都是可见的，就直接从索引返回，无需回表。
- **如果可见性映射不准确**（比如最近有过 UPDATE/DELETE，页面还没被 VACUUM 清理），就必须回表确认，每回表一次就计为一次 `Heap Fetches`。
- 你的计划只有 **4 次 Heap Fetches**，说明绝大部分页面都被可见性映射覆盖，索引直接返回了数据。

> 若 `Heap Fetches` 数值很大，通常意味着表需要执行 `VACUUM` 更新可见性映射，否则 Index Only Scan 的性能优势会打折扣。

---

### 3. 性能对比与总结

| 查询                                 | 扫描方式         | 是否回表              | 读取量            | 实际执行时间 |
| ------------------------------------ | ---------------- | --------------------- | ----------------- | ------------ |
| `select * from users where age=39`   | Bitmap Heap Scan | 是（64,307 个堆页面） | 约 500 MB         | 583 ms       |
| `select age from users where age=39` | Index Only Scan  | 几乎不（4 次回表）    | 仅索引页，约几 MB | **20.9 ms**  |

**核心要点**：

- 只查询索引列（或包含在索引里的列）时，PostgreSQL 能够使用 Index Only Scan 避免昂贵的回表I/O，极大提升查询速度。
- `Heap Fetches` 表示因可见性检查而发生的少量回表，正常值极低；如果偏高，应执行 `VACUUM` 或 `ANALYZE`。
- 这个例子完美展示了**覆盖索引**的威力，是数据库优化的常用手段。

---

**面试时可以这样讲**：

> “当查询的列全部被索引覆盖时，PostgreSQL 会使用 Index Only Scan 直接从索引返回结果，避免回表。与之前的 `select *` 引发的 Bitmap Heap Scan（读64k个堆页面、500MB）相比，Index Only Scan 只需读取少量索引页面，执行时间从 583ms 降到 20ms。少量 Heap Fetches 用于可见性检查，数值低说明表的可见性映射健康。”
