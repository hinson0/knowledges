# Compose 的 "variable is not set" 警告为何对 Laravel 无害

## Trigger Question
> `WARN ... "SITE_KEY" variable is not set. Defaulting to a blank string.` —— 这是什么原因,会不会影响 Laravel?

## Key Takeaways
- 警告来源:`.env` 身兼两职(Laravel 配置 + Compose 插值源)。Compose 读 `.env` 时会展开它见到的所有 `${...}`,如 `PLATFORM_CLIENT_ID="${SITE_KEY}"`,发现 `SITE_KEY` 未定义 → WARN 并填空串。
- 对照:`MAIL_FROM_NAME="${APP_NAME}"` 不报警,因为 `APP_NAME` 已定义——判据只是「Compose 视角里该变量有没有定义」。
- **对 Laravel 无害**,三道隔离:
  1. Compose 的替换只在内存,**不改磁盘文件**;
  2. 项目 `.env` **不会自动注入容器**(要进容器必须显式 `environment:`/`env_file:`);
  3. app 容器靠 volume 挂载**直接读 `.env` 原文**,Laravel 自己解析 `${SITE_KEY}`,绕开 Compose。
- 消噪(可选):在 `.env` 给 `SITE_KEY=`/`SITE_SECRET=` 空值即可;不处理也完全没问题。

## Pitfall / Why
- 数据流:磁盘 `.env` 原文 →(路径1)Compose 读 → 内存替换 → 仅用于 compose 文件插值 → 没被引用 → 丢弃(产生 WARN);→(路径2)挂载进容器 → Laravel 直接读原文 → 自己解析(**真正生效**)。两条路径互不干扰。
- 注意:给 `SITE_KEY` 加空值**会改变** Laravel 的解析结果(字面量 → 空串),详见 [[phpdotenv-variable-resolution-quirks]]。

## Related
- [[phpdotenv-variable-resolution-quirks]]
- [[laravel-dotenv-env-var-precedence]]
