# Laravel/phpdotenv:真实环境变量 > .env 文件

## Trigger Question
> 凭什么能「覆盖」.env 里的值?(compose 的 environment 与 .env 同名时谁生效)

## Key Takeaways
- Laravel 用的 phpdotenv **默认不覆盖「已存在的真实环境变量」**(overwrite=false)。
- 加载顺序:容器启动时已有真实环境变量 `DB_HOST=mysql` → Laravel 读 `.env` 看到 `DB_HOST=127.0.0.1` → 发现该 key 已有真实值 → **跳过,不覆盖**。
- 优先级口诀:**真实环境变量 > .env 文件**。
- 这是 docker-compose `environment:` 能覆盖 `.env`、以及部署平台注入 secret 能生效的支点。

## Pitfall / Why
- 推论:若某 key 由真实环境注入,`.env` 里同名行会被忽略——所以在 `.env` 给 `SITE_KEY=` 空值,生产注入真值时不会被覆盖,**生产安全**。
- 验证最终生效值:
  ```bash
  docker compose exec app php artisan tinker \
    --execute="echo config('database.connections.mysql.host');"
  ```
  若没刷新成预期值,多半是 config 缓存,`php artisan config:clear` 即可。

## Related
- [[docker-compose-host-vs-container-db-address]]
- [[phpdotenv-variable-resolution-quirks]]
