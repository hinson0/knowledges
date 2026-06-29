# docker compose exec / run / config 区别与标准链路

## Trigger Question
> `docker compose exec app printenv DB_HOST DB_PORT` 要先启动服务吗?

## Key Takeaways
- `docker compose exec <svc>`:在**已运行**的容器里执行命令;容器没起来报 `service "<svc>" is not running`。
- `docker compose run --rm <svc>`:临时起一个一次性容器跑命令,跑完即弃,**无需先 up**;同样会应用 `environment:`。
- `docker compose config`:渲染并校验最终配置(含 `.env` 插值结果),**不启动**容器——改完配置先跑它,最快发现语法错。
- 标准链路:`config`(查语法) → `up -d`(起服务) → `exec`(查容器内实际值)。

## Code Example
```bash
docker compose config                              # 1. 静态校验 + 看插值结果
docker compose up -d                               # 2. 后台启动
docker compose exec app printenv DB_HOST DB_PORT   # 3. 进运行中的容器查变量

# 只想快速看一眼、不想长期挂服务:
docker compose run --rm app printenv DB_HOST DB_PORT
```

## Related
- [[docker-compose-environment-list-vs-map-syntax]]
- [[docker-compose-dotenv-interpolation-warning]]
