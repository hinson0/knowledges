# "不可重复读"术语拆解

> 来源:`fastapi_web/src/learning_demo/pgsql_non_repeated_readable.md`(2026-05-11 流水笔记)
> 配套阅读:`pg-read-committed.md`(现象与级别对比)、`pg-mvcc-experiment.md`(底层实现)

## 字面拆解

**不可重复读 = Non-repeatable Read = "读"这个动作不能"重复"**

关键不在"读",而在"**重复**"这两个字。

"重复"在这里的意思是:**重复做同一件事,得到同样的结果**。

就像你说"这个实验是可重复的",意思是别人按你的步骤再做一遍,会得到一样的结果。

所以:

- **可重复读**:同一个事务里,你读 Alice 的余额,读一次是 1000,再读一次还是 1000,**重复读取得到相同结果** ✅
- **不可重复读**:同一个事务里,你读 Alice 的余额,第一次 1000,第二次 2000,**重复读取得到不同结果** ❌

## 换个角度:从"事务"的视角看

事务的本意是想给你一个"**稳定的世界快照**"——在我这个事务期间,我看到的数据应该是稳定的、可预测的。

但在 RC 级别下,这个"快照"是**每条 SQL 语句执行时才生成的**,不是整个事务共享一个。所以:

```
事务 A 开始
  ├─ 第 1 次 SELECT  → 拍一张快照 → 看到 1000
  ├─ (别人 COMMIT 了)
  ├─ 第 2 次 SELECT  → 又拍一张新快照 → 看到 2000
事务 A 结束
```

两次"读"动作,各自看到不同的世界。**重复地读,不能得到可重复的结果**——这就叫"不可重复读"。

## 为什么这是个"问题"

光看现象你可能觉得:"读到最新数据不是挺好的吗?"

问题出在**事务内的逻辑一致性**上。看这个场景:

```sql
BEGIN;

-- 第 1 步:检查余额够不够
SELECT balance FROM accounts WHERE name = 'Alice';
-- 看到 1000,够扣 500

-- (此时别的事务把 Alice 余额改成了 100 并提交)

-- 第 2 步:基于"够扣"的判断去扣款
UPDATE accounts SET balance = balance - 500 WHERE name = 'Alice';
-- 现在余额变成 -400 了!

COMMIT;
```

你在事务里做了一个"先检查、再操作"的逻辑,**这个逻辑的前提**(余额是 1000)在事务执行过程中被推翻了。重复读到的不一样,意味着你**不能信任前面读到的值**去做后续决策。

## 对比 Repeatable Read 一眼就懂

把同样的实验放到 `REPEATABLE READ` 级别下:

```sql
🅐 BEGIN ISOLATION LEVEL REPEATABLE READ;
🅐 SELECT balance FROM accounts WHERE name = 'Alice';  -- 1000

🅑 UPDATE ... SET balance=2000; COMMIT;

🅐 SELECT balance FROM accounts WHERE name = 'Alice';  -- 还是 1000 !
🅐 COMMIT;
```

事务 A 从头到尾看到的都是事务开始时刻的世界——**重复读,结果可重复**。这才是这个名字想表达的对立面。

## 一句话总结

> **"不可重复读"= 在同一个事务里,把同一个 SELECT 重复执行,可能得到不一样的结果。**

名字描述的是"重复这个读操作"这件事失败了,不是描述"读"本身有问题。中文翻译有点拗口,英文 `Non-repeatable Read` 直译过来就是"不可重复的读取",意思更直白一点。

## 关联

- `pg-read-committed.md` — RC 隔离级别详解、四级对比表
- `pg-repeatable-read-snapshot.md` — RR 快照一致性、什么时候该用 RR
- `pg-mvcc-experiment.md` — RC vs RR 快照机制的底层实现
