# Read Committed(读已提交)隔离级别

> 来源:`fastapi_web/src/learning_demo/1857.md`(2026-05-11 流水笔记)

## 概念

`read committed` 是数据库**事务隔离级别**中的一种,中文叫"读已提交"。它的核心规则只有一句话:

> **一个事务只能读到其他事务已经提交(commit)的数据,读不到还没提交的数据。**

## 用一个例子说清楚

假设有张账户表,Alice 的余额是 100。

```
时间   事务 A (转账中)              事务 B (查询余额)
────────────────────────────────────────────────────
T1    BEGIN;
T2    UPDATE 账户
      SET 余额=200
      WHERE 名字='Alice';
                                  BEGIN;
T3                                SELECT 余额 FROM 账户
                                  WHERE 名字='Alice';
                                  -- 读到 100 (旧值)
                                  -- 因为 A 还没 commit
T4    COMMIT;
T5                                SELECT 余额 FROM 账户
                                  WHERE 名字='Alice';
                                  -- 读到 200 (新值)
                                  -- 因为 A 已经 commit 了
```

注意 T3 和 T5:**同一个事务 B 内,前后两次读到的余额不一样**。这就是 Read Committed 的特点。

## 它防止了什么、又允许了什么

### 防止:脏读(Dirty Read)

你不会读到别人事务里"中间状态"的数据。比如 A 正在转账,余额暂时变成了 -100(还没扣对方账户),这时 B 读不到 -100。

### 允许:不可重复读(Non-repeatable Read)

同一个事务里两次读同一行,结果可能不一样(就像上面 T3 和 T5)。因为别人 commit 了,你下次读就会看到新值。

## 四个隔离级别的对比

从弱到强:

| 级别                         | 脏读 | 不可重复读 | 幻读                |
| ---------------------------- | ---- | ---------- | ------------------- |
| Read Uncommitted             | 可能 | 可能       | 可能                |
| **Read Committed**(PG 默认)  | 防止 | 可能       | 可能                |
| Repeatable Read              | 防止 | 防止       | 可能(PG 实际也防止) |
| Serializable                 | 防止 | 防止       | 防止                |

## 坑/Why:PostgreSQL 默认选 RC 的考量

**Why:** 性能和一致性的折中。RC 几乎不会因为读操作而阻塞,并发性能好,而且大多数业务场景下"读到最新已提交数据"反而是想要的行为。

**How to apply:** 如果业务需要更强一致性(比如报表统计、对账),再手动切到 `Repeatable Read` 或 `Serializable`。

简单记忆:**"已提交"就是"别人写完盖章了的我才能看,正在写的我不偷看"**。

## 关联

- `pg-repeatable-read-snapshot.md` — RR 与 RC 的对比、什么时候该升级到 RR
- `pg-non-repeatable-read-term.md` — "不可重复读"术语字面拆解
- `pg-mvcc-experiment.md` — RC/RR 在 MVCC 层面的实现差异
