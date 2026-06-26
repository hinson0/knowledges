Laravel `artisan` 常用命令可以按用途记。

**数据库**

```bash
php artisan migrate
```

执行数据库迁移。

```bash
php artisan migrate:status
```

查看迁移执行状态。

```bash
php artisan migrate:rollback
```

回滚上一批迁移。

```bash
php artisan db:seed
```

执行 seeder 灌数据。

```bash
php artisan db:seed --class='Database\Seeders\XxxSeeder'
```

只执行指定 seeder。

**路由**

```bash
php artisan route:list
```

查看所有路由。

```bash
php artisan route:list --path=admin/audit-logs
```

按路径过滤路由。

**缓存**

```bash
php artisan optimize:clear
```

清掉配置、路由、视图、事件等缓存，本地排障很常用。

```bash
php artisan config:clear
```

清配置缓存。

```bash
php artisan route:clear
```

清路由缓存。

```bash
php artisan cache:clear
```

清应用缓存。

**开发调试**

```bash
php artisan tinker
```

进入 Laravel 交互式命令行。

```bash
php artisan tinker --execute='echo config("app.name");'
```

直接执行一段 PHP/Laravel 代码。

```bash
php artisan serve --host=0.0.0.0 --port=8001
```

启动本地 Laravel HTTP 服务。

**测试**

```bash
php artisan test
```

运行测试。

```bash
php artisan test tests/Feature/AuditLogFeatureTest.php
```

只跑某个测试文件。

```bash
php artisan test --filter=AuditLogFeatureTest
```

按测试类或方法过滤。

**生成代码**

```bash
php artisan make:model AuditLog
```

生成 Model。

```bash
php artisan make:migration create_audit_logs_table
```

生成 migration。

```bash
php artisan make:controller Admin/V1/AuditLogController
```

生成 controller。

```bash
php artisan make:request AuditLogRequest
```

生成 FormRequest。

```bash
php artisan make:seeder DemoSeeder
```

生成 seeder。

**队列**

```bash
php artisan queue:work
```

启动队列 worker。

```bash
php artisan queue:failed
```

查看失败队列。

```bash
php artisan queue:retry all
```

重试失败队列。

**项目自定义命令**

你的项目里还有自定义命令，比如：

```bash
php artisan menu:clear-cache
```

重新导入菜单配置并清菜单缓存。

```bash
php artisan import-export:files-clean
```

清理过期导入导出文件。
