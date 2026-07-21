# Docker 下数据库地址:宿主机视角 vs 容器视角

## Trigger Question
> ```
> +    environment:
> +      DB_HOST: mysql
> +      DB_PORT: 3306
> ```
> 这是什么意思

## Key Takeaways
- 同一个「连库地址」在宿主机和容器里不同,但 `.env` 只能填一个值。
- 约定:`.env` 填**宿主机视角** `DB_HOST=127.0.0.1 / DB_PORT=3307`;在 compose 的 app 服务用 `environment:` 把容器内覆盖成 `DB_HOST=mysql / DB_PORT=3306`。
- 一份 `.env` 同时服务两种场景:宿主机跑 artisan/测试走 `127.0.0.1:3307`,容器内走 `mysql:3306`。

## Schema / Field Table
| 场景 | 连 mysql 的地址 | 原因 |
|------|----------------|------|
| 宿主机(本机跑 artisan/测试) | `127.0.0.1:3307` | 容器把 3306 映射到宿主机 3307 |
| app 容器内部 | `mysql:3306` | 容器间靠服务名互访;端口映射只对宿主机生效,容器间走原始 3306 |

## Code Example
```yaml
services:
  app:
    environment:
      DB_HOST: mysql       # mysql = 下方 mysql 服务名,compose 内置 DNS 解析到该容器
      DB_PORT: "3306"
```
```bash
# 验证容器内实际值(应为 mysql / 3306)
docker compose exec app printenv DB_HOST DB_PORT
```

## Pitfall / Why
- 反例:直接把 `.env` 改成 `DB_HOST=mysql` 是**错的**——`mysql` 只在 compose 网络内可解析,宿主机解析不了;且 `DB_PORT` 还是 `3307` 时容器内也连不上(容器内监听 3306)。结果两种场景全断。
- 之所以 compose 的 `environment:` 能覆盖 `.env` 里的值,见 [[laravel-dotenv-env-var-precedence]]。

## Related
- [[laravel-dotenv-env-var-precedence]]
- [[docker-compose-env-single-source-of-truth]]
- [[docker-compose-environment-list-vs-map-syntax]]
