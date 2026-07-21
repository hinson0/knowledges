# Redis 命令命名规律:看一眼就能猜出功能

> 来源:`fastapi_web/src/0512/0906.md`(2026-05-12 流水笔记)

## 概念

学 Redis 命令命名规律,能让你**看一眼命令就猜出功能**,不用死记。本文以 `ZREVRANGE` 为切入点拆解,再扩展到全部数据类型前缀 + 修饰词缩写表。

## 拆解 ZREVRANGE

```
ZREVRANGE
│ │  │
│ │  └─ RANGE  = 范围
│ └──── REV    = REVerse(反向/逆序)
└────── Z      = Zset(有序集合)
```

**完整翻译:Z(在有序集合里)REV(反向)RANGE(取范围)**

意思就是:**从有序集合里反向(从大到小)取一段范围**。

## Redis 命名的两个超级规律

### 规律 1:第一个字母 = 数据类型

| 前缀         | 类型                                         | 例子                         |
| ------------ | -------------------------------------------- | ---------------------------- |
| **(无前缀)** | String                                       | `GET`, `SET`, `INCR`         |
| **H**        | Hash                                         | `HGET`, `HSET`, `HKEYS`      |
| **L**        | List                                         | `LPUSH`, `LRANGE`, `LPOP`    |
| **S**        | Set                                          | `SADD`, `SMEMBERS`, `SINTER` |
| **Z**        | ZSet(有序集合,Zorted Set 的 Z)               | `ZADD`, `ZRANGE`, `ZSCORE`   |
| **PF**       | HyperLogLog(发明人 Philippe Flajolet 的缩写) | `PFADD`, `PFCOUNT`           |
| **GEO**      | 地理位置                                     | `GEOADD`, `GEOSEARCH`        |
| **X**        | Stream(eXtreme,流)                           | `XADD`, `XREAD`              |
| **BIT**      | Bitmap                                       | `SETBIT`, `BITCOUNT`         |

💡 **小冷知识**:为什么有序集合是 Z 不是 O?因为 `O` 容易和数字 0 搞混,而 **Z 是字母表最后一个**,刚好用来表示"特殊的、最高级的 Set"。也有说法是 `Sorted Set` 的发音类似 "Zorted",作者就用了 Z。

### 规律 2:中间的关键词

#### REV = REVerse(反向)

| 命令               | 含义                     |
| ------------------ | ------------------------ |
| `ZRANGE`           | **正向**(从小到大)取范围 |
| `ZREVRANGE`        | **反向**(从大到小)取范围 |
| `ZRANGEBYSCORE`    | 按分数正向取             |
| `ZREVRANGEBYSCORE` | 按分数反向取             |
| `ZRANK`            | 正向排名(分数低的排名 0) |
| `ZREVRANK`         | 反向排名(分数高的排名 0) |

**排行榜用 REV 系列,因为大家想看"分数最高的"在第一名。**

#### 其他高频缩写

| 缩写            | 全称                  | 含义           |
| --------------- | --------------------- | -------------- |
| **ADD**         | Add                   | 增加           |
| **GET / SET**   | -                     | 取值 / 设值    |
| **INCR / DECR** | Increment / Decrement | 自增 / 自减    |
| **POP / PUSH**  | -                     | 弹出 / 推入    |
| **REM**         | Remove                | 删除           |
| **CARD**        | Cardinality           | 基数(元素总数) |
| **LEN**         | Length                | 长度           |
| **EX**          | EXpire                | 过期(秒)       |
| **PX**          | EXpire(milliseconds)  | 过期(毫秒)     |
| **NX**          | Not eXists            | 不存在时才操作 |
| **XX**          | eXists                | 存在时才操作   |
| **MGET / MSET** | Multi GET / SET       | 批量取值/设值  |
| **TTL**         | Time To Live          | 剩余生存时间   |

## 用规律破解陌生命令

掌握了规律,看到陌生命令也能秒猜:

### `ZINCRBY`

```
Z + INCR + BY = ZSet 里给某个元素的分数自增 BY 这么多
```

**用法**:`ZINCRBY leaderboard 100 Alice` → Alice 分数加 100

### `ZRANGEBYSCORE`

```
Z + RANGE + BY + SCORE = ZSet 按分数(BY SCORE)取范围
```

**用法**:`ZRANGEBYSCORE leaderboard 8000 9000` → 取分数在 8000-9000 之间的

### `HMGET`

```
H + M + GET = Hash 里批量(M)取值
```

**用法**:`HMGET user:1001 name age email` → 一次取 user:1001 的三个字段

### `SINTERSTORE`

```
S + INTER + STORE = Set 求交集(INTERsection)并存储(STORE)
```

**用法**:`SINTERSTORE result set1 set2` → set1 和 set2 的交集存到 result

### `SETEX`

```
SET + EX = SET + EXpire = 设值的同时设过期时间
```

**用法**:`SETEX session_token 3600 "abc123"` → 设值并 3600 秒后过期

### `SETNX`

```
SET + NX = Not eXists = key 不存在时才 SET
```

**用法**:`SETNX lock "1"` → 经典分布式锁基础

## 现在再看你的命令,完全秒懂

```
ZREVRANGE leaderboard 0 9 WITHSCORES
│ │  │     │           │ │ │
│ │  │     │           │ │ └─ WITHSCORES = 返回时带上分数
│ │  │     │           │ └─── 9 = 结束索引(取到第 10 个)
│ │  │     │           └───── 0 = 起始索引
│ │  │     └───────────────── leaderboard = ZSet 的 key
│ │  └─────────────────────── RANGE = 取一段范围
│ └────────────────────────── REV = 反向(从分数高到低)
└──────────────────────────── Z = ZSet 操作
```

**翻译**:在 `leaderboard` 这个 ZSet 里,**反向**(分数从高到低)取**索引 0 到 9**(前 10 名),**同时返回分数**。

→ **就是"取分数前 10 名"** 🏆

## 反例对比

如果你写成 `ZRANGE`(没有 REV):

```bash
ZRANGE leaderboard 0 9 WITHSCORES
```

→ 这是**正向**取,会拿到**分数最低的 10 个人**,变成"最差排行榜" 😅

## 一张图记住

```
                Redis 命令拆解大法

  Z  REV  RANGE  BY  SCORE
  ↑   ↑    ↑     ↑    ↑
  类型 方向  动作  限定 维度

  Z    = ZSet                 (类型)
  REV  = Reverse 反向          (方向)
  RANGE = 取一段                (动作)
  BY   = 按某个维度             (限定)
  SCORE = 分数维度              (维度)
```

**记住:Redis 命令 = 类型字母 + 修饰词 + 动词**,几乎所有命令都可以这样拆。

## 实战练习:猜下面这些命令的含义

(先自己猜,再看答案)

1. `ZREVRANGEBYSCORE leaderboard 9999 8000`
2. `HINCRBY user:1001 age 1`
3. `LPOPMIN queue 5`(注意没这个命令,陷阱题)
4. `SUNIONSTORE all_users team_a team_b`
5. `ZCOUNT scores 60 100`

<details>
<summary>点开看答案</summary>

1. ZSet 里,反向,按分数,取 9999 到 8000 分的元素(高分到低分)
2. Hash 里,user:1001 的 age 字段自增 1
3. **陷阱:没这个命令**!(只有 ZPOPMIN / LPOP,LPOPMIN 不存在)
4. Set 求并集(UNION)并存储,把 team_a 和 team_b 合并到 all_users
5. ZSet 里,统计分数在 60-100 之间的元素数量(COUNT)

</details>

## 一句话总结

> Redis 命令的命名是**前缀拆解式**的:**第一个字母是数据类型,后面拼接 REV(反向)、BY(限定)、EX(过期)等修饰词,最后是动作**。掌握这套规律,**99% 的命令一眼就能看懂**,基本不用查文档。

掌握这套**命令拆解大法**之后,你看 Redis 文档就像看代码注释,效率翻倍。

## 关联

- `redis-zset-query-commands.md` — ZSet 排行榜 8 个查询命令实操
- `redis-4-scenarios-demo.md` — 4 个场景的命令在真实代码里怎么用
