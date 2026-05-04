## 如果我对age创建索引,在age=10和age>0 都分别会用什么索引呢?

---

### 1. `select * from users where age=39` — Bitmap Heap Scan

```sql explain输出
                                                             QUERY PLAN
------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on users  (cost=1040.67..106597.04 rows=94998 width=45) (actual time=43.902..577.922 rows=100948 loops=1)
   Recheck Cond: (age = 39)
   Heap Blocks: exact=64307
   ->  Bitmap Index Scan on idx_users_age  (cost=0.00..1016.92 rows=94998 width=0) (actual time=20.895..20.895 rows=100948 loops=1)
         Index Cond: (age = 39)
 Planning Time: 1.278 ms
 JIT:
   Functions: 4
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 1.977 ms, Inlining 0.000 ms, Optimization 1.692 ms, Emission 8.606 ms, Total 12.275 ms
 Execution Time: 583.870 ms
(11 rows)
```

#### 1.1 Bitmap Index Scan on idx_users_age 解读

```
-> Bitmap Index Scan on idx_users_age  (cost=0.00..1016.92 rows=94998 width=0) (actual time=20.895..20.895 rows=100948 loops=1)
Index Cond: (age = 39)
```

- `(cost=0.00..1016.92 rows=94998 width=0)`
  - 没有启动成本，索引遍历的总代价为 1016.92 个代价单位；
  - `width=0` 表示它不返回实际数据行，只返回一个位图。
- `(actual time=20.895..20.895 rows=100948 loops=1)`
  - 实际启动时间是 20.895 ms，总时间也是 20.895 ms；
  - 实际行数 100,948；
  - 执行次数 `loops=1` 次。

**① 为什么 actual time=20.895..20.895，总时间也是 20.895？**

这里你可能混淆了 cost（估算代价）和 actual time（实际时间）。

- `(cost=0.00..1016.92 rows=94998 width=0)` 是优化器估算的代价，单位是**抽象代价**，不是毫秒。
- `(actual time=20.895..20.895)` 是**实际执行时间**，单位是毫秒。

两个数字碰巧接近，但本质上不同。为什么启动时间和总时间都是 20.895？因为 Bitmap Index Scan 的任务是扫描索引并构建一个位图，它不返回数据行（width=0）。它一次性完成所有工作，没有"逐行输出"的阶段，所以启动即结束，两个时间相等。

> 说白了，并没有返回实际的行，而是构建了一个 bitmap。因此消耗时间基本为 0（没有逐行输出的开销）。

**② 为什么 rows=100948（实际）与 cost 中的 rows=94998（估算）不同？**

- `cost ... rows=94998` 是优化器根据统计信息（pg_stats）估算的满足 age=39 的行数。
- `actual ... rows=100948` 是查询时实际在索引中找到的行数。

两者不一致很正常，因为统计信息是抽样估算的，不可能 100% 精确。你的数据中 age 分布可能有一点点倾斜，导致实际行数略高于预估。这属于正常误差范围。如果误差非常大（例如实际 1 万行，预估 1000 万行），就需要执行 `ANALYZE users;` 更新统计信息。

> 也就是说 cost 的 rows 和 actual 的 rows 不同，但不能差很多。如果差很多说明表没有统计到最新的信息，因此需要 ANALYZE 一下。

**③ loops=1 是什么意思？**

`loops` 表示该执行计划节点被执行的次数。`loops=1` 表示这个节点只执行了 1 次。

如果是在嵌套循环连接（Nested Loop）中，内表的索引扫描可能会执行多次（跟外表行数有关），此时 `loops` 会大于 1，`actual time` 会显示每次的平均时间，总时间 = 平均时间 × loops。

在你的查询中，Bitmap Index Scan 是独立执行的，只运行了一次。

**④ loops > 1 的示例 — Nested Loop Join**

```sql 查询
SELECT u.*
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.amount > 30;

 id | username |     email      | age | is_active
----+----------+----------------+-----+-----------
  1 | hinson0  | hinson0@qq.com |  39 | t
  1 | hinson0  | hinson0@qq.com |  39 | t
  ... (共 11 行)
```

```sql explain输出
                                                         QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
 Nested Loop  (cost=0.43..3839.98 rows=453 width=45) (actual time=0.447..0.488 rows=11 loops=1)
   ->  Seq Scan on orders o  (cost=0.00..27.00 rows=453 width=4) (actual time=0.308..0.313 rows=11 loops=1)
         Filter: (amount > '30'::numeric)
         Rows Removed by Filter: 2
   ->  Index Scan using users_pkey on users u  (cost=0.43..8.42 rows=1 width=45) (actual time=0.014..0.014 rows=1 loops=11)
         Index Cond: (id = o.user_id)
 Planning Time: 1.599 ms
 Execution Time: 0.686 ms
(8 rows)
```

- **为什么内表 loops=11？** Nested Loop Join：对于外表（orders）返回的每一行，都会去内表（users）执行一次索引扫描，以获取对应的 user 信息。外表 Seq Scan on orders 经过 `amount > 30` 过滤后，实际返回了 11 行（rows=11）。因此内表的 Index Scan using users_pkey 被调用了 11 次（loops=11），每次查找一个 user_id。

  > 也就是说外表的记录数决定了 inner join 的 loops 次数。

- **actual time 和总时间怎么理解？**
  - 内表 `actual time=0.014..0.014`：这是**每次执行的平均时间**（毫秒）。11 次执行的平均启动时间和平均完成时间都是 0.014 ms（说明每次查找都极快）。内表总耗时 = 0.014 ms × 11 ≈ 0.154 ms。
  - 外表 `actual time=0.308..0.313`：总耗时 0.313 ms（loops=1，只执行一次）。
  - Nested Loop 节点 `actual time=0.447..0.488`：总耗时 0.488 ms，等于外表全表扫描 + 11 次内表查找的开销总和（还有一点点连接本身的 CPU 时间）。

  > 也就是说，总计的 Nested Loop actual time 是 0.488 ms，是外表全表扫描 + 内表查询的开销总和（+ CPU 的连接时间消耗）。

---

#### 1.2 Bitmap Heap Scan on users 解读

```
Bitmap Heap Scan on users  (cost=1040.67..106597.04 rows=94998 width=45) (actual time=43.902..577.922 rows=100948 loops=1)
  Recheck Cond: (age = 39)
  Heap Blocks: exact=64307
```

- `(cost=1040.67..106597.04 rows=94998 width=45)`
  - 启动成本 1040.67（来自构建位图），总成本 106597.04；
  - 实际执行时间 583 ms；
  - 读取了 64,307 个堆页面。
- `(actual time=43.902..577.922 rows=100948 loops=1)`
  - 实际启动时间 43 ms；
  - 总计时间 577 ms；
  - 执行节点 1 次。

**① Recheck Cond: (age = 39) — 重新检查条件**

Bitmap Index Scan 构建的位图只能标记某个页面上存在符合 `age=39` 的行，但它不知道这个页面里具体哪一行符合条件。因此，Bitmap Heap Scan 把相关页面批量读出来后，需要重新对每一行执行 `age=39` 的判断，确保返回的行确实满足查询条件。这就是 Recheck Cond 的作用——在堆扫描阶段再次校验索引条件，只返回真正的匹配行。

为什么需要重新检查？因为 PostgreSQL 的位图索引大致流程是：

1. 索引扫描返回一系列满足条件的行指针（CTID，即块号+块内偏移）。
2. 这些指针被压缩成"以页面为单位"的位图：该页面只要有至少一行满足条件，就打上标记。
3. 堆扫描时，整个页面被读入内存，然后逐行检查是否真正符合条件（位图不记录具体偏移量）。

所以必须有 Recheck Cond 在堆扫描阶段做精确过滤。在你的计划中：

- `Recheck Cond: (age = 39)` 表示对每个从堆读取的页面，都执行了一次 `age = 39` 的条件判断。
- 索引找到了 100,948 行指针，但这些指针分布在 64,307 个页面里，位图只标记了页面，不标记行，所以必须重检查。

**② Heap Blocks: exact=64307 — 精确读取的堆页面数**

在执行 Bitmap Heap Scan 时，总共读取了堆表的 64,307 个页面（blocks）。

- **exact 的含义**：当 Heap Blocks 后跟着 `exact=64307` 时，表示这个数字是精确统计的，不是估算。如果出现的是 `lossy=...`，则表示由于 `work_mem` 不足，位图被转换为"有损"模式，此时只标记页面而不精确到行指针，Heap Blocks 的统计可能为近似值。你的计划中是 `exact`，说明位图完整，所有信息精确，性能统计也准确。
- **64307 个页面意味着什么？**：每个页面默认 8KB，所以大约读取了 502 MB 的堆数据（64307 × 8KB ≈ 514 MB）。因为 `age=39` 的行分散在整个表的各个页面里，读取它们相当于几乎遍历了整个表，这是 Bitmap Heap Scan 代价高的主要原因，也是执行时间达到 583 ms 的关键所在。

**③ 整个流程总结**

1. **Bitmap Index Scan**：先在 `idx_users_age` 索引中找出所有 `age = 39` 的行指针（CTID），一共找到 100,948 个。
2. **构建位图（Bitmap）**：把这些行指针对应的数据页面标记出来，因为很多行可能位于同一个页面，最终得到 64,307 个不同的页面需要读取。
3. **Bitmap Heap Scan 读取页面并 Recheck**：按物理顺序依次把这 64,307 个页面读入内存，然后对每个页面重新检查 `age = 39` 的条件，最终确认出这 100,948 行就是真正满足条件的记录。

---

### 2. `select age from users where age=39` — Index Only Scan

```sql explain输出
                                                              QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------
 Index Only Scan using idx_users_age on users  (cost=0.43..1970.90 rows=94998 width=4) (actual time=0.107..15.514 rows=100948 loops=1)
   Index Cond: (age = 39)
   Heap Fetches: 4
 Planning Time: 0.201 ms
 Execution Time: 20.865 ms
(5 rows)
```

当查询的列全部被索引覆盖时，PostgreSQL 会使用 **Index Only Scan** 直接从索引返回结果，**避免回表**。

与之前的 `select *` 引发的 Bitmap Heap Scan（读 64k 个堆页面、约 500MB）相比，Index Only Scan 只需读取少量索引页面，执行时间从 **583 ms 降到 20 ms**。

- `Heap Fetches: 4`：少量 Heap Fetches 用于可见性检查，数值低说明表的可见性映射（Visibility Map）健康。

---

### 3. `select * from users where age > 0` — Seq Scan（全表扫描）

```sql explain输出
                                                      QUERY PLAN
----------------------------------------------------------------------------------------------------------------------
 Seq Scan on users  (cost=0.00..227127.20 rows=9999776 width=45) (actual time=11.716..1436.391 rows=10000003 loops=1)
   Filter: (age > 0)
 Planning Time: 0.509 ms
 JIT:
   Functions: 4
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 3.421 ms, Inlining 0.000 ms, Optimization 5.071 ms, Emission 5.282 ms, Total 13.775 ms
 Execution Time: 1667.769 ms
(8 rows)
```

当条件是 `age > 0` 时，优化器认为几乎所有行都满足条件（rows 估算约 1000 万行），此时走索引 + 回表的代价远高于直接顺序扫描全表，因此选择了 **Seq Scan**。

> 即使有索引，优化器也不一定会使用——当结果集占比很大时，全表扫描更高效。

---

## 为什么启动时间 = 总时间？

你提出这个问题很敏锐，也正好是很多同学看不懂执行计划的地方。关键在于 **Bitmap Index Scan 并不是一行一行往外吐数据的**，而是一口气把整个位图构建好，再整体交给父节点。

---

### ① 为什么启动时间 = 总时间？

对于一个普通的 `Index Scan`（索引扫描），**启动时间** 是找到第一行并返回给上层的时间，**总时间** 是返回所有行的时间，两者通常会不一样，因为会逐步输出很多行。

但是 **`Bitmap Index Scan` 完全不一样**：

- 它的任务不是返回用户要的数据行，而是**扫描索引，收集所有匹配行的物理位置（CTID），构建一个位图**。
- 在构建位图的过程中，它**不向上层输出任何结果**——也就是它的 "第一行" 实际上是它完成所有扫描后**一次性交付的整个位图**。
- 因此，**它的第一行输出时刻，就是它完成所有扫描的时刻**。  
  → 启动时间（到第一行） = 总时间（到所有行） = 整个构建位图的耗时。

在你这里，这两个时间都是 20.895 毫秒，意味着：

> **它花了 20.895 毫秒扫描索引中所有 `age=39` 的叶子节点，把对应的 100,948 个行指针全部标记到位图中，然后才将这个位图作为一个整体递给上层。**

`rows=100948` 只是说明索引里匹配了这么多行（即有效行指针数量），但因为这个节点只输出**一个位图对象**，它不在输出过程中流式地产生行，所以不存在 "第一行早、最后一行晚" 的情况。

---

### ② 对比父节点：Bitmap Heap Scan 就是流式返回行的

看父节点：

```
Bitmap Heap Scan on users  (actual time=43.902..577.922 rows=100948 loops=1)
```

- `43.902` 是第一行返回的时间（这其中包含了子节点构建位图的 20ms，再加上根据位图读取第一个数据页的时间）。
- `577.922` 是所有 100,948 行返回完毕的时间。
- 因为它是真正一行一行（或一页一页）把数据行返回的，所以`启动时间 ≠ 总时间`。

---

### ③ 一句总结

> **Bitmap Index Scan 的两个时间相等，是因为它不是一个流式输出节点——它必须先构建完整个位图，才能输出第一个结果（也就是整个位图）。虽然处理了 10 万行指针，但这 10 万行是被它一口气塞进位图的，完成之后才交付，所以 start = total = 20.895 ms。**
