# Redis 4 个场景最小 Demo:排行榜 / 限流 / 签到 / 地理位置

> 来源:`fastapi_web/src/0512/0905.md`(2026-05-12 流水笔记)

## 概念

把 Redis 最常考的 4 个场景做成**能立刻跑通**的最小代码:**排行榜(ZSet)、限流计数器(String+INCR)、签到(Bitmap)、附近的车(Geo)**。每个 demo 都给出完整代码 + 预期输出 + 核心原理表。

## 准备:起一个 Redis 容器

```bash
docker run -d --name redis-demo -p 6379:6379 redis:7-alpine

# 进 redis-cli 测试一下
docker exec -it redis-demo redis-cli ping
# 应该返回 PONG
```

装 Python 客户端:

```bash
uv add redis
# 或
pip install redis
```

## 场景 1:排行榜(ZSet)

新建 `redis_demo_1_leaderboard.py`:

```python
import redis

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

# 清空之前的数据
r.delete("game:leaderboard")

# 1. 写入分数(ZADD)
players = {
    "Alice":   8500,
    "Bob":     9200,
    "Carol":   7800,
    "David":   9500,
    "Eve":     8800,
    "Frank":   7200,
    "Grace":   9100,
    "Henry":   8000,
    "Ivy":     8600,
    "Jack":    9300,
}

# mapping 参数批量插入
r.zadd("game:leaderboard", players)

# 2. 取 Top 10(ZREVRANGE 从高到低)
print("🏆 Top 10 排行榜:")
top10 = r.zrevrange("game:leaderboard", 0, 9, withscores=True)
for rank, (name, score) in enumerate(top10, 1):
    print(f"  {rank}. {name}: {int(score)}")

# 3. 查某个玩家的排名(ZREVRANK,从 0 开始)
rank = r.zrevrank("game:leaderboard", "Alice")
print(f"\nAlice 排名: 第 {rank + 1} 名")

# 4. 查某个玩家的分数(ZSCORE)
score = r.zscore("game:leaderboard", "Alice")
print(f"Alice 分数: {int(score)}")

# 5. 给玩家加分(ZINCRBY)
r.zincrby("game:leaderboard", 500, "Alice")
new_score = r.zscore("game:leaderboard", "Alice")
print(f"Alice 加 500 分后: {int(new_score)}")

# 6. 查某个分数段的玩家(ZRANGEBYSCORE)
print("\n8000-9000 分段玩家:")
mid_players = r.zrangebyscore("game:leaderboard", 8000, 9000, withscores=True)
for name, score in mid_players:
    print(f"  {name}: {int(score)}")

# 7. 看排行榜总人数(ZCARD)
total = r.zcard("game:leaderboard")
print(f"\n总玩家数: {total}")
```

跑一下:

```bash
python redis_demo_1_leaderboard.py
```

**预期输出:**

```
🏆 Top 10 排行榜:
  1. David: 9500
  2. Jack: 9300
  3. Bob: 9200
  4. Grace: 9100
  5. Eve: 8800
  6. Ivy: 8600
  7. Alice: 8500
  ...

Alice 排名: 第 7 名
Alice 分数: 8500
Alice 加 500 分后: 9000
...
```

**核心操作:**

| 命令              | 作用              |
| ----------------- | ----------------- |
| `ZADD`            | 加入/更新分数     |
| `ZREVRANGE 0 9`   | 取分数最高的前 10 |
| `ZREVRANK`        | 查玩家排名        |
| `ZSCORE`          | 查玩家分数        |
| `ZINCRBY`         | 原子加分          |
| `ZRANGEBYSCORE`   | 按分数段查        |

## 场景 2:计数器 + 限流(String + INCR)

新建 `redis_demo_2_ratelimit.py`:

```python
import redis
import time

r = redis.Redis(host="localhost", port=6379, decode_responses=True)


def rate_limit(user_id: str, limit: int = 5, window: int = 60) -> bool:
    """
    限流:每个用户每 window 秒最多 limit 次请求

    返回 True 表示允许,False 表示被限流
    """
    key = f"rate_limit:{user_id}:{int(time.time() // window)}"
    # 用 pipeline 保证原子性
    pipe = r.pipeline()
    pipe.incr(key)
    pipe.expire(key, window)
    count, _ = pipe.execute()

    return count <= limit


# 模拟用户 123 在 1 秒内发 10 个请求
user_id = "user_123"
for i in range(10):
    allowed = rate_limit(user_id, limit=5, window=60)
    status = "✅ 通过" if allowed else "❌ 被限流"
    current_count = r.get(f"rate_limit:{user_id}:{int(time.time() // 60)}")
    print(f"请求 {i+1}: {status} (当前计数: {current_count})")


# 计数器用法:统计访问量
print("\n--- 计数器示例 ---")
r.delete("page_views:home")
for _ in range(100):
    r.incr("page_views:home")

print(f"首页访问量: {r.get('page_views:home')}")

# 多接口计数
api_stats = {
    "api:GET:/users":  3,
    "api:POST:/login": 5,
    "api:GET:/orders": 8,
}
for api, count in api_stats.items():
    for _ in range(count):
        r.incr(api)
    print(f"{api} 调用次数: {r.get(api)}")
```

跑一下:

```bash
python redis_demo_2_ratelimit.py
```

**预期输出:**

```
请求 1: ✅ 通过 (当前计数: 1)
请求 2: ✅ 通过 (当前计数: 2)
请求 3: ✅ 通过 (当前计数: 3)
请求 4: ✅ 通过 (当前计数: 4)
请求 5: ✅ 通过 (当前计数: 5)
请求 6: ❌ 被限流 (当前计数: 6)
请求 7: ❌ 被限流 (当前计数: 7)
...

首页访问量: 100
api:GET:/users 调用次数: 3
api:POST:/login 调用次数: 5
api:GET:/orders 调用次数: 8
```

**核心原理:**

- `INCR` 是**原子操作**,并发安全
- key 里带时间窗口(`time.time() // 60`),自动滚动
- `EXPIRE` 保证 key 会过期,不会无限增长

## 场景 3:签到(Bitmap)

新建 `redis_demo_3_signin.py`:

```python
import redis
from datetime import date, timedelta

r = redis.Redis(host="localhost", port=6379, decode_responses=True)


def get_signin_key(user_id: int, year_month: str) -> str:
    """user:1001:signin:202605"""
    return f"user:{user_id}:signin:{year_month}"


def signin(user_id: int, day: date):
    """签到:把对应日期的位设为 1"""
    key = get_signin_key(user_id, day.strftime("%Y%m"))
    # 第 N 天对应位 N-1
    r.setbit(key, day.day - 1, 1)


def has_signed(user_id: int, day: date) -> bool:
    """查某天是否签到"""
    key = get_signin_key(user_id, day.strftime("%Y%m"))
    return r.getbit(key, day.day - 1) == 1


def count_signin(user_id: int, year_month: str) -> int:
    """统计某月签到天数"""
    key = get_signin_key(user_id, year_month)
    return r.bitcount(key)


def get_signin_days(user_id: int, year: int, month: int) -> list:
    """列出某月所有签到日期"""
    key = get_signin_key(user_id, f"{year}{month:02d}")
    days = []
    # 一个月最多 31 天
    for day in range(1, 32):
        if r.getbit(key, day - 1) == 1:
            days.append(day)
    return days


# === Demo 演示 ===
user_id = 1001
key = get_signin_key(user_id, "202605")
r.delete(key)  # 清空

# 模拟用户 5 月签到了 1, 2, 3, 5, 8, 10, 15, 20 这几天
for day_num in [1, 2, 3, 5, 8, 10, 15, 20]:
    signin(user_id, date(2026, 5, day_num))

print(f"用户 {user_id} 5 月签到情况:")

# 查某些日期
for d in [1, 4, 5, 10, 11]:
    day = date(2026, 5, d)
    signed = has_signed(user_id, day)
    print(f"  5月{d}日: {'✅ 已签到' if signed else '❌ 未签到'}")

# 统计本月签到总天数
total = count_signin(user_id, "202605")
print(f"\n5 月总签到天数: {total} 天")

# 列出所有签到日期
days = get_signin_days(user_id, 2026, 5)
print(f"签到日期: {days}")

# 看内存占用(惊喜!)
mem = r.execute_command("MEMORY", "USAGE", key)
print(f"\n这条 bitmap 占用内存: {mem} bytes (一个月签到状态)")

# 推算一下规模
print(f"\n💡 推算:")
print(f"  100 万用户一个月签到数据 ≈ {mem * 1_000_000 / 1024 / 1024:.1f} MB")
print(f"  1 亿用户一个月签到数据 ≈ {mem * 100_000_000 / 1024 / 1024 / 1024:.2f} GB")
```

跑一下:

```bash
python redis_demo_3_signin.py
```

**预期输出:**

```
用户 1001 5 月签到情况:
  5月1日: ✅ 已签到
  5月4日: ❌ 未签到
  5月5日: ✅ 已签到
  5月10日: ✅ 已签到
  5月11日: ❌ 未签到

5 月总签到天数: 8 天
签到日期: [1, 2, 3, 5, 8, 10, 15, 20]

这条 bitmap 占用内存: 56 bytes (一个月签到状态)

💡 推算:
  100 万用户一个月签到数据 ≈ 53.4 MB
  1 亿用户一个月签到数据 ≈ 5.21 GB
```

**核心原理:**

- 一个用户一个月签到 = **一个 String 的位图**,每天 1 bit
- 31 bit ≈ 4 bytes,加 Redis 开销大概 50 bytes
- `BITCOUNT` 直接 O(N/8) 数 1 的个数,**比 SQL 全表 COUNT 快上千倍**

**对比 SQL 方案:**

如果用 SQL 表 `user_signin (user_id, date)`,1 亿用户每天一行,一个月就是 **30 亿行**,索引几十 GB 起步。bitmap 只要 5 GB。

## 场景 4:附近的车(Geo)

新建 `redis_demo_4_geo.py`:

```python
import redis
import random

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

r.delete("vehicles")

# 1. 添加车辆位置(GEOADD)
# 武汉地区一些虚构车辆位置(经度, 纬度, VIN)
vehicles = [
    (114.305, 30.593, "VIN_001"),  # 武汉市中心
    (114.310, 30.595, "VIN_002"),  # 附近
    (114.260, 30.580, "VIN_003"),  # 汉阳
    (114.500, 30.600, "VIN_004"),  # 远点的
    (114.306, 30.594, "VIN_005"),  # 中心旁边
    (114.350, 30.620, "VIN_006"),  # 武昌
    (114.270, 30.560, "VIN_007"),  # 汉阳南
    (115.000, 31.000, "VIN_008"),  # 很远的车
]

for lng, lat, vin in vehicles:
    r.geoadd("vehicles", (lng, lat, vin))

print(f"✅ 已注册 {len(vehicles)} 辆车的位置")

# 2. 查某辆车的位置(GEOPOS)
pos = r.geopos("vehicles", "VIN_001")
print(f"\nVIN_001 当前位置: 经度 {pos[0][0]:.4f}, 纬度 {pos[0][1]:.4f}")

# 3. 算两辆车的距离(GEODIST)
dist = r.geodist("vehicles", "VIN_001", "VIN_003", unit="km")
print(f"VIN_001 到 VIN_003 的距离: {dist:.2f} km")

# 4. 查附近 5 公里内的车(GEOSEARCH,新版命令)
center_lng, center_lat = 114.305, 30.593
print(f"\n🔍 查询坐标 ({center_lng}, {center_lat}) 附近 5km 的车辆:")

nearby = r.geosearch(
    "vehicles",
    longitude=center_lng,
    latitude=center_lat,
    radius=5,
    unit="km",
    withcoord=True,
    withdist=True,
    sort="ASC",  # 按距离从近到远
)

for item in nearby:
    vin, dist, (lng, lat) = item
    print(f"  {vin}: 距离 {dist:.3f} km, 位置 ({lng:.4f}, {lat:.4f})")

# 5. 查附近 50 公里内的(包括远的)
print(f"\n🔍 附近 50km 的车辆数: {len(r.geosearch('vehicles', longitude=center_lng, latitude=center_lat, radius=50, unit='km'))}")

# 6. 查矩形区域内的车(地图框选)
print("\n🔍 武汉市核心区域(经度 114.25-114.40,纬度 30.55-30.65)的车:")
box_vehicles = r.geosearch(
    "vehicles",
    longitude=114.325,  # 矩形中心
    latitude=30.600,
    width=15,           # 宽 15 km
    height=11,          # 高 11 km
    unit="km",
)
for vin in box_vehicles:
    print(f"  {vin}")

# 7. 模拟车辆移动(更新位置)
print("\n🚗 模拟 VIN_001 移动...")
new_lng, new_lat = 114.320, 30.610
r.geoadd("vehicles", (new_lng, new_lat, "VIN_001"))
new_pos = r.geopos("vehicles", "VIN_001")
print(f"VIN_001 新位置: ({new_pos[0][0]:.4f}, {new_pos[0][1]:.4f})")

# 8. 看底层(GEO 本质是 ZSet,geohash 当 score)
print("\n💡 揭秘:Geo 底层就是 ZSet")
print(f"  vehicles 类型: {r.type('vehicles')}")
# 看看 ZSet 里的 score(geohash 编码)
all_with_hash = r.zrange("vehicles", 0, -1, withscores=True)
print("  geohash 编码(部分):")
for vin, geohash in all_with_hash[:3]:
    print(f"    {vin}: {int(geohash)}")
```

跑一下:

```bash
python redis_demo_4_geo.py
```

**预期输出:**

```
✅ 已注册 8 辆车的位置

VIN_001 当前位置: 经度 114.3050, 纬度 30.5930
VIN_001 到 VIN_003 的距离: 4.69 km

🔍 查询坐标 (114.305, 30.593) 附近 5km 的车辆:
  VIN_001: 距离 0.000 km, 位置 (114.3050, 30.5930)
  VIN_005: 距离 0.124 km, 位置 (114.3060, 30.5940)
  VIN_002: 距离 0.561 km, 位置 (114.3100, 30.5950)
  VIN_003: 距离 4.694 km, 位置 (114.2600, 30.5800)

🔍 附近 50km 的车辆数: 7

🔍 武汉市核心区域...的车:
  VIN_001
  VIN_005
  VIN_002
  VIN_006

🚗 模拟 VIN_001 移动...
VIN_001 新位置: (114.3200, 30.6100)

💡 揭秘:Geo 底层就是 ZSet
  vehicles 类型: zset
  geohash 编码(部分):
    VIN_007: 4054804867234423
    VIN_003: 4054805022289445
    VIN_001: 4054805228834367
```

**核心原理:**

- `GEOADD` 内部做了 **geohash 编码**(把二维经纬度变成一维数字),存进 ZSet 的 score
- 因为 ZSet 有序,**地理位置相近的车 geohash 也接近**,所以能用 ZSet 的范围查询快速定位"附近"
- `GEORADIUS` / `GEOSEARCH` 在 ZSet 上做范围扫描,毫秒级返回

## 🎯 跑完这 4 个 demo,你能讲什么

| Demo         | 面试时讲什么                                                                                                                                  |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 排行榜       | "我用 ZSet 实现游戏排行榜,ZADD 加分,ZREVRANGE 取 Top 10,毫秒级返回。**底层是跳表 + 哈希表,跳表保证有序范围查询,哈希表保证 O(1) 单点查找**。" |
| 限流计数器   | "用 `INCR + EXPIRE`,key 带时间窗口自动滚动。`INCR` 是**原子操作**,并发安全。生产环境会用 Lua 脚本保证 INCR 和 EXPIRE 原子性。"                |
| 签到 Bitmap  | "签到用 SETBIT,**1 亿用户一个月只要 5GB**,如果用 SQL 表得几十 GB。`BITCOUNT` 直接 O(N/8) 统计签到天数。"                                      |
| 地理位置 Geo | "车联网项目找附近的车用 GEO,`GEOADD + GEOSEARCH`,**底层是 ZSet 配合 geohash 编码**,把二维坐标转一维方便用 ZSet 范围查询。"                    |

## 💡 超加分演示:看穿底层

跑完 demo 后**用 redis-cli 看一下底层**:

```bash
docker exec -it redis-demo redis-cli

# 看排行榜的底层(是 zset)
TYPE game:leaderboard

# 看签到的底层(是 string!)
TYPE user:1001:signin:202605

# 看车辆位置的底层(是 zset!和排行榜一样)
TYPE vehicles

# 看 bitmap 实际存的什么
GET user:1001:signin:202605
# 输出是一串看起来像乱码的字符 → 那就是位图的原始字节!
```

**亲眼看到 Bitmap 底层就是 String,Geo 底层就是 ZSet** —— 这种"看穿本质"的认知,面试时讲出来比讲 API 牛逼一个量级。

## 🚀 可继续深入方向

跑完后挑感兴趣的方向继续深入:

- 🔥 **分布式锁实战**(SET NX EX + Lua 释放 + Redlock 争议)
- 🔥 **缓存三大坑**(穿透、击穿、雪崩,亲手复现)
- **持久化 RDB vs AOF vs 混合**(看真实持久化文件)
- **Pipeline 性能对比**(单条 vs 批量,QPS 差 100 倍)

## 关联

- `redis-zset-query-commands.md` — 排行榜 ZSet 8 个查询命令速查
- `redis-command-naming-rules.md` — Redis 命令前缀拆解规律
