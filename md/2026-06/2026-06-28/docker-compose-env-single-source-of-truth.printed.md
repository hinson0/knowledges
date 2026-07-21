# Docker Compose 与 .env 的 MySQL 配置单一事实来源(SSOT)

## Trigger Question
> docker-compose.yml 和 .env 文件 的 mysql 相当于要维护 2 份,有没有更工程的实践方法 避免这样的 2 份维护?

## Key Takeaways
- 根因:同一份事实(MySQL 凭据)被两套命名规范各存了一份——Laravel 用 `DB_DATABASE/DB_USERNAME/DB_PASSWORD`,官方 MySQL 镜像用 `MYSQL_DATABASE/MYSQL_USER/MYSQL_PASSWORD`。
- Docker Compose 会**自动加载** compose 文件同目录下的 `.env`,用于替换 compose 文件里的 `${VAR}` 占位符(这是「插值」,不是「注入容器」)。
- 解法:让 compose 用 `${DB_*}` 引用 `.env`,`.env` 成为唯一来源;在 mysql 服务里做一层「名字映射」。
- `${VAR:-默认值}` 提供兜底:新人没配 `.env` 也能起来。
- **不能**用 `env_file: .env` 直接喂 MySQL 镜像,因为命名不匹配(DB_* ≠ MYSQL_*);映射只能靠 `environment:` 里的 `${}`。

## Code Example
```yaml
# docker-compose.yml — mysql 服务用 ${DB_*} 引用 .env,避免双写
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: ${DB_DATABASE:-cecmf}
      MYSQL_USER: ${DB_USERNAME:-cecmf}
      MYSQL_PASSWORD: ${DB_PASSWORD:-secret}
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:-root}
```
```ini
# .env — 唯一事实来源
DB_DATABASE=cecmf
DB_USERNAME=cecmf
DB_PASSWORD=secret
DB_ROOT_PASSWORD=root
```

## Pitfall / Why
- 区分两个「.env」:① Compose 自动加载的 `.env`(给 compose 文件做 `${}` 插值);② 应用(Laravel)的 `.env`。本项目两者是同一个文件,所以方便。
- 改了 `.env` 里的密码后,若 `mysql-data` 卷**已初始化**过,密码不会变——MySQL 仅在首次空目录初始化时建用户/设密码。需 `docker compose down -v` 重建,或手动 `ALTER USER`。
- healthcheck 若硬编码 `-proot`,改密码后探活会失效;应同样参数化为 `-p${DB_ROOT_PASSWORD}`。
- 新建项目要先有 `.env`,否则 compose 插值时 `${DB_PASSWORD}` 变空串导致 MySQL 初始化失败;`:-默认值` 兜底 + `cp .env.example .env` 固化进 onboarding。

## Related
- [[docker-compose-host-vs-container-db-address]]
- [[laravel-dotenv-env-var-precedence]]
- [[docker-compose-environment-list-vs-map-syntax]]
