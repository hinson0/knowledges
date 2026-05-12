# Redis ZSet 排行榜查询命令速查

> 来源:`fastapi_web/src/0512/0904.md`(2026-05-12 流水笔记)

## 概念

把分数写进 sorted set(`ZADD game:leaderboard ...`)之后,在 `redis-cli` 里如何**查**它——以"游戏排行榜"为例,把 ZSet 最常用的 8 个查询命令一次过完。

## 进入客户端

```bash
redis-cli
```

如果有密码或非默认端口:`redis-cli -h localhost -p 6379 -a yourpassword`

## 常用查询命令

### 1. 看排行榜里有多少人

```
ZCARD game:leaderboard
```

### 2. 从高到低查看全部数据(带分数)

```
ZREVRANGE game:leaderboard 0 -1 WITHSCORES
```

`0 -1` 表示从第一个到最后一个,`WITHSCORES` 表示同时返回分数。

### 3. 从低到高查看

```
ZRANGE game:leaderboard 0 -1 WITHSCORES
```

### 4. 查看 Top 3(分数最高的前 3 名)

```
ZREVRANGE game:leaderboard 0 2 WITHSCORES
```

### 5. 查某个玩家的分数

```
ZSCORE game:leaderboard David
```

### 6. 查某个玩家的排名

```
ZREVRANK game:leaderboard David
```

`ZREVRANK` 是从高到低的排名(David 应该是 0,因为分数最高);`ZRANK` 是从低到高。**排名从 0 开始**。

### 7. 按分数范围筛选(比如查 8500–9200 之间的玩家)

```
ZRANGEBYSCORE game:leaderboard 8500 9200 WITHSCORES
```

### 8. 确认这个 key 存在、类型对不对

```
TYPE game:leaderboard
```

应该返回 `zset`。

## 在 Python 里查询(对照表)

如果你想在 Python 脚本里查,对应的方法名几乎一样:

```python
r.zcard("game:leaderboard")
r.zrevrange("game:leaderboard", 0, -1, withscores=True)
r.zscore("game:leaderboard", "David")
r.zrevrank("game:leaderboard", "David")
r.zrangebyscore("game:leaderboard", 8500, 9200, withscores=True)
```

## 预期效果

跑一下 `ZREVRANGE game:leaderboard 0 -1 WITHSCORES`,你应该会看到 David (9500) 排第一,Frank (7200) 排最后。

## 关联

- `redis-4-scenarios-demo.md` — 排行榜完整 Python demo + 另外 3 个场景
- `redis-command-naming-rules.md` — `Z` `REV` `RANGE` `BY` `SCORE` 拆解大法
