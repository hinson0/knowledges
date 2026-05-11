# PostgreSQL MVCC 实验总结

> 来源:`fastapi_web/src/learning_demo/2132.md` + `2222.md`(2026-05-11 流水笔记)
> **实验目的**:理解 PG 的 MVCC 实现机制、隔离级别行为、xmin/xmax 隐藏字段、死元组与 VACUUM
> **核心方法**:开两个 psql 终端,模拟并发事务,亲眼看现象

## 概念

**MVCC**(Multi-Version Concurrency Control,多版本并发控制),PostgreSQL 实现"读写不互相阻塞"的核心机制。

核心思想:

- 写操作不会"原地修改"数据,而是**创建新版本**
- 旧版本保留在表里(等 VACUUM 清理)
- 每个事务看到一份"快照",**读不阻塞写,写不阻塞读**

## 🏗️ 实验环境准备

### 开两个 psql 终端窗口

并排放,左边 **🅐 Terminal A**,右边 **🅑 Terminal B**。

```bash
# 两个窗口都执行
psql -h localhost -U yzb
```

### 准备测试表

**🅐 Terminal A**:

```sql
DROP TABLE IF EXISTS accounts;

CREATE TABLE accounts (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(20),
    balance INT
);

INSERT INTO accounts (name, balance) VALUES
    ('Alice', 1000),
    ('Bob',   500),
    ('Carol', 800);
```

## 🧪 实验一:读不阻塞写,写不阻塞读

### 🅐 A 开启事务,修改但不提交

```sql
BEGIN;
UPDATE accounts SET balance = 9999 WHERE name = 'Alice';

SELECT * FROM accounts WHERE name = 'Alice';
-- 看到 9999(A 自己看到自己改的)
```

### 🅑 B 同时查询

```sql
SELECT * FROM accounts WHERE name = 'Alice';
-- 看到 1000(B 看到的还是旧值,完全没被 A 阻塞!)
```

### 🅐 A 回滚

```sql
ROLLBACK;
SELECT * FROM accounts WHERE name = 'Alice';
-- 1000(恢复原值)
```

### ✅ 验证的事实

- 写操作不会阻塞读操作
- 未提交的修改对其他事务不可见
- 回滚后什么都没发生

## 🧪 实验二:RC 隔离级别(PG 默认)

### 看默认隔离级别

```sql
SHOW default_transaction_isolation;
-- 输出:read committed
```

**PostgreSQL 默认是 Read Committed(RC)**。

### 实验:RC 下的"不可重复读"

#### 🅐 A 开启 RC 事务

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到: 1000
```

#### 🅑 B 修改并提交

```sql
BEGIN;
UPDATE accounts SET balance = 2000 WHERE name = 'Alice';
COMMIT;
```

#### 🅐 A 再查一次(还在同一事务里)

```sql
SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到: 2000   ← 同一事务两次读结果不同!这就是"不可重复读"
COMMIT;
```

### ✅ 验证的事实

**RC 隔离级别下,同一事务内两次读同一行,结果可能不同。** 因为 RC 在每条语句执行时都获取最新的"快照"。

## 🧪 实验三:RR 隔离级别(快照一致)

### 🅐 A 开启 RR 事务

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到: 2000(当前最新值)
```

### 🅑 B 修改并提交

```sql
BEGIN;
UPDATE accounts SET balance = 5000 WHERE name = 'Alice';
COMMIT;
```

### 🅐 A 再查一次

```sql
SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到: 2000   ← 还是旧值,整个事务用同一个快照!
COMMIT;

-- 事务结束后再查
SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到: 5000   ← 这时才能看到新值
```

### ✅ 验证的事实

**RR 隔离级别下,整个事务内所有读操作基于事务开始时的快照,多次读结果一致。**

## 🧪 实验四:幻读测试

幻读 = "查询条件下,出现了之前没看到的新行"。

### 🅐 A 开启 RR 事务

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE balance > 500;
-- 看到 Alice(5000)、Carol(800)
```

### 🅑 B 插入新行并提交

```sql
BEGIN;
INSERT INTO accounts (name, balance) VALUES ('David', 700);
COMMIT;
```

### 🅐 A 再次查询同一条件

```sql
SELECT * FROM accounts WHERE balance > 500;
-- 还是只有 Alice 和 Carol,看不到 David!
COMMIT;
```

### ✅ 验证的事实

**PG 的 RR 在快照读层面完全防住了幻读**,比 SQL 标准定义的 RR 更严格。

### 当前读会发生什么?

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM accounts WHERE balance > 500;
-- 看到 Alice, Carol, David(此时 David 已经提交了)
```

**🅑 B 再插入并提交:**

```sql
BEGIN;
INSERT INTO accounts (name, balance) VALUES ('Eve', 600);
COMMIT;
```

**🅐 A 用 `FOR UPDATE` 当前读:**

```sql
SELECT * FROM accounts WHERE balance > 500 FOR UPDATE;
```

可能的结果:

- 报错:`could not serialize access due to concurrent update`
- 这是 PG 的 **serialization failure**,告诉你"并发冲突了,请重试事务"

```sql
ROLLBACK;
```

### ✅ 验证的事实

**PG 在 RR 隔离级别下,遇到并发当前读冲突会直接抛错让你重试事务。**

## 🧪 实验五:看见 MVCC —— xmin / xmax 隐藏字段

PG 每行数据都有两个**隐藏字段**,可以直接 SELECT 出来。

### 🅐 看隐藏字段

```sql
SELECT xmin, xmax, * FROM accounts ORDER BY id;
```

输出:

```
 xmin  | xmax | id | name  | balance
-------+------+----+-------+---------
   742 |    0 |  1 | Alice |    5000
   742 |    0 |  2 | Bob   |     500
   742 |    0 |  3 | Carol |     800
```

### 字段含义

- **`xmin`**:**创建这一行**的事务 ID
- **`xmax`**:**删除/更新这一行**的事务 ID(0 表示该行还活着)

### 🅐 做一次 UPDATE,观察隐藏字段

```sql
BEGIN;
UPDATE accounts SET balance = 7777 WHERE name = 'Alice';
-- 假设这是事务 747

SELECT xmin, xmax, * FROM accounts WHERE name = 'Alice';
```

输出:

```
 xmin | xmax | id | name  | balance
------+------+----+-------+---------
  747 |    0 |  1 | Alice |    7777   ← xmin 是 747
```

```sql
COMMIT;
```

## 🎯 关键原理:UPDATE 不是"原地修改"

**这是 PG MVCC 最重要的认知,务必理解!**

### UPDATE 实际做了两件事

**步骤 1:旧行的 `xmax` 被标记为当前事务 ID**

```
物理位置  xmin  xmax  id  name   balance
(0,1)    742   747   1   Alice   5000    ← 旧行还在,但被打上"死亡标记"
```

**步骤 2:插入一个全新的行**

```
物理位置  xmin  xmax  id  name   balance
(0,1)    742   747   1   Alice   5000    ← 旧版本(死了)
(0,4)    747    0    1   Alice   7777    ← 新版本(活的)
```

### 所以 SELECT 时为什么只看到新行?

PG 在查询时做**可见性判断**:

- 旧行:`xmax=747`(被当前事务杀了)→ **不可见**
- 新行:`xmin=747`(当前事务创建的)→ **可见**

**结论:你看到的不是"原来那行的 xmin 改了",而是磁盘上真的存在两行,PG 只返回了对你可见的版本。**

### Git 类比

**PG 的 UPDATE 就像 Git 提交:**

- 不会"修改"旧版本
- 而是**新建一个版本**,把旧版本"标记为历史"

| 表述                       | 实际含义                                                                |
| -------------------------- | ----------------------------------------------------------------------- |
| "把旧行的 xmax 标记为 747" | 旧行被打上"我死了,杀我的是事务 747"的标签                               |
| "插入一个新行"             | 真的物理插入了一行新数据,xmin=747                                       |
| "xmin 变了"                | ❌ 不严谨,**应该说"你查到的是另一行,这一行的 xmin 本来就是 747"**       |

## 🧪 实验六:用 pageinspect 亲眼看死元组

### 先装扩展(需要超级用户)

```bash
docker exec -it <容器名> psql -U postgres -d yzb -c "CREATE EXTENSION pageinspect;"
```

### 🅐 回到普通用户查询

```sql
-- 临时禁用 autovacuum,防止 PG 自动清理
ALTER TABLE accounts SET (autovacuum_enabled = false);

-- 看页面上所有 tuple(包括死的)
SELECT lp, t_xmin, t_xmax
FROM heap_page_items(get_raw_page('accounts', 0))
WHERE t_xmin IS NOT NULL;
```

输出大概像这样:

```
 lp | t_xmin | t_xmax
----+--------+--------
  1 |    742 |    747   ← 旧版本 Alice(死了)
  2 |    742 |      0   ← Bob(活的)
  3 |    742 |      0   ← Carol(活的)
  4 |    747 |      0   ← 新版本 Alice(活的)
```

### ✅ 这一刻你"看见"了 MVCC

**磁盘上同时存在两个 Alice**,普通 SELECT 看不到旧版本是因为 MVCC 帮你过滤了,**但物理上它确实存在**,等着 VACUUM 来清理。

## 🧪 实验七:制造死元组,看表膨胀

### 🅐 重复更新 1000 次

```sql
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..1000 LOOP
        UPDATE accounts SET balance = balance + 1 WHERE name = 'Alice';
    END LOOP;
END $$;
```

### 看死元组数量

```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size('accounts')) AS table_size
FROM pg_stat_user_tables
WHERE relname = 'accounts';
```

输出:

```
 relname  | n_live_tup | n_dead_tup | table_size
----------+------------+------------+------------
 accounts |          5 |       1000 | 80 kB      ← 表膨胀了!
```

### ✅ 验证的事实

**5 行数据,但表里物理上有 1005 行,死元组占据了 99% 的空间。** 这就是 PG 表"膨胀"(bloat)现象。

## 🧪 实验八:VACUUM 清理死元组

### VACUUM(普通版)

```sql
VACUUM accounts;

SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size('accounts')) AS table_size
FROM pg_stat_user_tables
WHERE relname = 'accounts';
```

输出:

```
 relname  | n_live_tup | n_dead_tup | table_size
----------+------------+------------+------------
 accounts |          5 |          0 | 80 kB      ← 死元组清了,但空间没还给 OS
```

### ⚠️ 关键认知

**VACUUM 只把死元组占用的空间标记为"可重用",不还给操作系统。**

类似 Python 里 `del` 一个对象 —— 引用计数归零,但内存不一定还给 OS。

### VACUUM FULL(真正回收空间)

```sql
VACUUM FULL accounts;

SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size('accounts')) AS table_size
FROM pg_stat_user_tables
WHERE relname = 'accounts';
```

输出:

```
 relname  | n_live_tup | n_dead_tup | table_size
----------+------------+------------+------------
 accounts |          5 |          0 | 8192 bytes   ← 真正回收了
```

### ⚠️ VACUUM FULL 的代价

- **会锁表**,期间无法读写
- 物理上**重写整张表**,IO 开销大
- **生产环境慎用!**

### 生产推荐方案

- `pg_repack` 扩展:在线整理表,不锁表
- 配置 `autovacuum` 参数,让后台自动跑

## 📊 自动 VACUUM(autovacuum)

PG 后台默认开启 `autovacuum`,自动清理死元组。

### 看 autovacuum 配置

```sql
SHOW autovacuum;
-- on

SHOW autovacuum_vacuum_threshold;
-- 50

SHOW autovacuum_vacuum_scale_factor;
-- 0.2
```

### 触发阈值

autovacuum 何时启动?

```
死元组数量 > autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor × 表行数
```

例如:表有 10000 行,`scale_factor=0.2`,`threshold=50` → **死元组超过 2050 个**触发 autovacuum。

### 看 autovacuum 历史

```sql
SELECT relname,
       last_vacuum,
       last_autovacuum,
       n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'accounts';
```

## ⚠️ 长事务的危害

### 现象

如果有一个长事务一直不结束(比如忘记 commit),**它的事务 ID 会阻止 autovacuum 清理任何 xmax 大于该事务 ID 的死元组**。

**结果**:表持续膨胀,即使 autovacuum 在跑,也清不掉东西。

### 怎么发现

```sql
-- 看最长的活跃事务
SELECT pid,
       now() - xact_start AS duration,
       state,
       query
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction')
ORDER BY xact_start
LIMIT 10;
```

### 生产保护措施

```sql
-- 设置空闲事务超时(自动 kill 长时间空闲的事务)
ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';

-- 设置语句超时
ALTER SYSTEM SET statement_timeout = '30s';

SELECT pg_reload_conf();
```

## 🎯 亲眼验证的事实清单

| #   | 现象                                                   |
| --- | ------------------------------------------------------ |
| 1   | 写操作不阻塞读(A 改了 Alice,B 还能正常读旧值)         |
| 2   | 未提交的修改对其他事务不可见                           |
| 3   | PG 默认隔离级别是 Read Committed                       |
| 4   | RC 下能复现"不可重复读"                                |
| 5   | RR 下整个事务用一致快照,多次读结果一致                 |
| 6   | PG 的 RR 在快照读层面完全防住了幻读                    |
| 7   | 当前读冲突会抛 serialization failure                   |
| 8   | `xmin/xmax` 是真的能 SELECT 出来的隐藏字段             |
| 9   | UPDATE 不是"原地修改",而是"标记旧行 xmax + 插入新行"   |
| 10  | 用 `pageinspect` 能看到磁盘上同时存在死的和活的版本    |
| 11  | 表膨胀是真实存在的,1000 次 UPDATE 让表暴涨             |
| 12  | VACUUM 清死元组但不还给 OS,VACUUM FULL 才回收空间      |

## 💡 面试金句

### 短版本(2 分钟)

> "PostgreSQL 的 MVCC 实现核心是 `xmin`、`xmax` 两个隐藏字段。**`xmin` 是创建该行的事务 ID,`xmax` 是删除该行的事务 ID**,这两个字段都能直接 SELECT 出来。
>
> **UPDATE 不是原地修改**,而是把旧行的 xmax 标记为当前事务,然后插入一个全新的行。所以磁盘上同时存在多个版本,通过可见性判断决定哪个版本对当前事务可见。这种'墓地式'设计的代价是**表会膨胀**(bloat),需要 VACUUM 来清理死元组。
>
> **VACUUM 只标记空间可重用,不还给操作系统**;`VACUUM FULL` 才真正回收空间,但会锁表。生产推荐用 `pg_repack` 在线整理。"

### 完整版本(5 分钟)

> "我做过一组完整的 PG MVCC 实验,有几个核心认知:
>
> **第一,PG 默认隔离级别是 Read Committed**,不是 Repeatable Read。我亲手验证过,RC 下同一事务里两次读同一行,如果中间有其他事务提交,第二次读会看到新值,这就是'不可重复读'。RR 下整个事务用同一个快照,多次读结果一致。
>
> **第二,PG 的 RR 比 SQL 标准更严格**。SQL 标准规定 RR 不防幻读,但 PG 的 RR 在快照读层面完全防住了幻读 —— 我实测过,A 事务先查到 N 行,B 插入新行并提交,A 再查还是 N 行。如果用 `FOR UPDATE` 当前读遇到并发冲突,PG 会直接抛 serialization failure,让应用层重试。
>
> **第三,PG 的 MVCC 实现是'墓地式'**。每行有 `xmin`、`xmax` 两个隐藏字段标记创建和删除的事务 ID,UPDATE 不修改原行,而是 '把旧行 xmax 标记为当前事务 + 插入新行'。我用 `pageinspect` 扩展看过磁盘上的真实页面,**5 行表 UPDATE 1000 次后,物理上有 1005 行,死元组占 99%**。
>
> **第四,VACUUM 的两种模式**:普通 VACUUM 只把死元组空间标记为可重用,**不还给操作系统**(类似 Python 的 del);`VACUUM FULL` 物理重写表回收空间,但**会锁表,生产慎用**。我们生产用 `pg_repack` 在线整理。
>
> **第五,长事务在 PG 是大忌**。长事务的事务 ID 会阻止 autovacuum 清理后续的死元组,导致表持续膨胀。我们配置了 `idle_in_transaction_session_timeout` 自动 kill 长时间空闲事务。
>
> 这套机制让 PG 实现了非阻塞的读写并发,代价是要持续维护表的健康度。"

## 📚 核心 SQL 速查

### 隔离级别

```sql
SHOW default_transaction_isolation;

BEGIN ISOLATION LEVEL READ COMMITTED;
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN ISOLATION LEVEL SERIALIZABLE;
```

### 看 xmin/xmax

```sql
SELECT xmin, xmax, ctid, * FROM your_table;
```

### 看死元组统计

```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_relation_size(relname::regclass)) AS size
FROM pg_stat_user_tables
WHERE relname = 'your_table';
```

### 看长事务

```sql
SELECT pid,
       now() - xact_start AS duration,
       state,
       query
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction')
ORDER BY xact_start;

-- 杀掉某个事务
SELECT pg_terminate_backend(<pid>);
```

### VACUUM 操作

```sql
-- 普通 VACUUM(不锁表)
VACUUM accounts;

-- VACUUM + 分析(更新统计信息)
VACUUM ANALYZE accounts;

-- VACUUM FULL(锁表,真正回收空间)
VACUUM FULL accounts;

-- 关闭表的 autovacuum
ALTER TABLE accounts SET (autovacuum_enabled = false);

-- 调整表的 autovacuum 阈值
ALTER TABLE accounts SET (
    autovacuum_vacuum_threshold = 100,
    autovacuum_vacuum_scale_factor = 0.1
);
```

### pageinspect(超级用户)

```sql
CREATE EXTENSION pageinspect;

SELECT lp, t_xmin, t_xmax
FROM heap_page_items(get_raw_page('your_table', 0))
WHERE t_xmin IS NOT NULL;
```

## 🚨 踩坑记录

### 坑 1:误以为 PG 默认是 RR

**真相**:PG 默认 Read Committed。这点和很多人的印象不同(可能受 MySQL InnoDB 默认 RR 的影响)。

### 坑 2:UPDATE 看 xmin 变了,以为是字段被修改

**真相**:UPDATE 是"标记旧行死 + 插入新行"。SELECT 返回的是新行,这个新行的 `xmin` 自然是当前事务 ID。旧行还在磁盘上,只是不可见。

### 坑 3:VACUUM 跑完表大小没变

**真相**:普通 VACUUM 只标记空间可重用,不还给 OS。**这是设计如此,不是 bug**。下次 INSERT 时会复用这些空间。如果要真正回收用 VACUUM FULL,但**会锁表**。

### 坑 4:autovacuum 在跑,表还在膨胀

**真相**:很可能存在长事务。autovacuum 不能清理"事务 ID 大于某个活跃事务的"死元组,所以长事务会让所有 vacuum 失效。

**排查**:`SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY xact_start;`

### 坑 5:`pageinspect` 装不上

**真相**:需要超级用户权限。普通用户(比如 yzb)直接 `CREATE EXTENSION pageinspect` 会报权限错。

**解决**:用 `postgres` 用户连数据库后装一次,以后所有用户都能用。

```bash
docker exec -it <容器名> psql -U postgres -d yzb -c "CREATE EXTENSION pageinspect;"
```

## ✅ Checklist:PG 数据库健康自检

- [ ] 长事务监控:`pg_stat_activity` 没有跑超过 10 分钟的事务
- [ ] 死元组比例:`n_dead_tup / n_live_tup` 不超过 20%
- [ ] autovacuum 在正常运行:`last_autovacuum` 不应该是几天前
- [ ] 表大小监控:与历史对比,异常膨胀及时排查
- [ ] 配置了 `idle_in_transaction_session_timeout`
- [ ] 配置了 `statement_timeout` 防止失控查询
- [ ] 重度更新的表考虑调小 `autovacuum_vacuum_scale_factor`
- [ ] 大表整理用 `pg_repack`,不要用 `VACUUM FULL`

## 关联

- `pg-read-committed.md` — RC 隔离级别详解
- `pg-repeatable-read-snapshot.md` — RR 快照一致性
- `pg-non-repeatable-read-term.md` — "不可重复读"术语
- `pgsql_jsonb_learning.md` — PG JSONB 索引实验

**核心结论**:PG 的 MVCC 通过 xmin/xmax 实现"读不阻塞写",代价是死元组堆积需要 VACUUM 维护。**理解这套机制是 PG DBA 的核心能力。**
