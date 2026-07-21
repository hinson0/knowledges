# LWW Upsert — 基于时间戳的冲突解决策略

> LWW = Last Write Wins（最后写入胜出），配合 upsert 实现多端同步时的冲突解决。

## 核心概念

- **LWW**：当同一条记录在多端被修改时，`updated_at` 更新的一方胜出
- **Upsert**：`INSERT ... ON CONFLICT DO UPDATE`，有就更新，没有就插入
- 两者结合：插入或更新时，只有新数据比已有数据更新才覆盖

## SQL 实现

```sql
-- 1. 尝试插入一条新记录
INSERT INTO transactions (id, amount, updated_at, ...)
VALUES (...)

-- 2. 如果 id 已存在（主键冲突），不报错，转为更新
ON CONFLICT (id) DO UPDATE

-- 3. 用新数据覆盖旧字段
SET amount = EXCLUDED.amount,
    updated_at = EXCLUDED.updated_at,
    ...

-- 4. 但只在新数据更新时才执行这个 UPDATE
WHERE EXCLUDED.updated_at > transactions.updated_at;
```

- **`ON CONFLICT (id)`** — 当插入的 `id` 和表里已有的 `id` 冲突时，不抛错，走 `DO UPDATE` 分支
- **`EXCLUDED`** — PostgreSQL 特殊关键字，代表本次尝试插入但被拦截的那行数据（即客户端传来的新数据）
- **`transactions.updated_at`** — 指表里已有的旧数据
- 如果客户端数据比服务端旧，WHERE 不成立，UPDATE 不执行，INSERT 也不执行——**等于静默跳过**

## 同步场景示例

| 时间  | 客户端                                    | 服务端                                      |
| ----- | ----------------------------------------- | ------------------------------------------- |
| 10:00 | 创建交易 A，金额 100                      | 同步收到，存入                              |
| 10:05 | 离线，改金额为 200 (`updated_at = 10:05`) | —                                           |
| 10:03 | —                                         | 另一设备改金额为 150 (`updated_at = 10:03`) |
| 10:10 | 上线，push 金额 200                       | LWW 比较：10:05 > 10:03，**接受 200**       |

## 适用场景

- 多端同步（手机、网页等多设备修改同一数据）
- 离线优先应用（离线期间产生的修改，上线后批量同步）
- 记账类应用——用户最后一次改的就是想要的

## 各数据库 Upsert 语法对比

这是 **PostgreSQL 特有语法**，各数据库写法不同：

| 数据库         | 语法                                 | 冲突引用关键字     |
| -------------- | ------------------------------------ | ------------------ |
| **PostgreSQL** | `INSERT ... ON CONFLICT DO UPDATE`   | `EXCLUDED`         |
| **MySQL**      | `INSERT ... ON DUPLICATE KEY UPDATE` | `VALUES()`         |
| **SQLite**     | `INSERT ... ON CONFLICT DO UPDATE`   | `excluded`（小写） |
| **SQL Server** | `MERGE ... WHEN MATCHED THEN UPDATE` | `SOURCE`           |

PostgreSQL 和 SQLite 语法很像，但 MySQL 和 SQL Server 完全不同。

## 局限性

- **不保留历史**：被覆盖的数据直接丢失，无法合并
- **时钟依赖**：依赖 `updated_at` 准确性，客户端时钟偏移可能导致异常
- **不适合协同编辑**：多人同时编辑同一字段时，只有一方的修改会保留
