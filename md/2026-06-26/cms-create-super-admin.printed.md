# CMS 创建超级管理员 (php artisan system:init)

## Trigger Question

> 现在我用用户登录 我想用 admin admin123 登录，怎么新增?

背景：cms-center 是 Laravel 项目，用 docker compose 跑（service `app`）。库已 migrate 但 `AdminUser` 表为空（`ADMIN_COUNT=0`），想新增一个 `admin` / `admin123` 的超级管理员登录后台。

## Key Takeaways

- 建超管走 `php artisan system:init`，它**同时**建站点（Sites）、菜单、插件菜单并 seed 超管 —— 比手插一行 `AdminUser` 完整（手插能登录但后台菜单/权限可能为空）。
- `--super-admin-password` 收的是**已加密哈希**（命令签名注明"已加密"），要用 `Hash::make("admin123")` 现生成；**传明文会登录失败**。
- `seedSuperAdmin` 的"建/更新"**不对称**：按 username 查 `AdminUser`，不存在才新建全套字段；**已存在则只把 `is_super=1` 再 save，不改密码/邮箱/name**。所以改已存在用户密码**不能**再跑 system:init。
- `system:init` 的 `site_id` / `tenant_id` 来自 config/env（`config/app.php` → `env('SITE_ID')` / `env('TENANT_ID')`），**没配会抛 `Site ID is not exists`**。
- 验证密码用 `Hash::check("admin123", $u->password)`，返回 true 即能登录。

## Field Table

`php artisan system:init` 关键选项（`app/Console/Commands/SystemInit.php`）：

| 选项 | 必填 | 语义 | 示例 |
|------|------|------|------|
| `--super-admin-username` | ✓ | 超管用户名 | `admin` |
| `--super-admin-password` | ✓ | 超管密码（**已加密哈希**，非明文） | `$2y$12$...` |
| `--super-admin-email` | ✗ | 超管邮箱（不影响用户名登录） | `admin@demo.com` |
| `--import-plugin-menus` | ✗ | 导入已激活插件的菜单 | — |
| `--sync-system-plugins` | ✗ | 同步项目内置系统插件 | — |

## Code Example

```bash
# 新增 admin / admin123(容器内执行;admin 当前不存在 → 干净新建)
docker compose exec -T app sh -lc '
HASH=$(php artisan tinker --execute="echo \Illuminate\Support\Facades\Hash::make(\"admin123\");" | tail -n1)
php artisan system:init \
  --import-plugin-menus \
  --sync-system-plugins \
  --super-admin-username="admin" \
  --super-admin-password="$HASH" \
  --super-admin-email="admin@demo.com"
'
# 成功标志: Super admin 'admin' created/updated successfully. + system init success
```

```bash
# 验证密码能否对上
docker compose exec -T app php artisan tinker --execute='
$u=\App\Models\AdminUser::where("username","admin")->first();
echo $u? ("super=".$u->is_super." check=".(\Illuminate\Support\Facades\Hash::check("admin123",$u->password)?"pass":"FAIL")) : "NOT_FOUND";
'
# check=pass → 浏览器 http://localhost:8000 用 admin / admin123 登录
```

```bash
# 改【已存在】用户的密码(system:init 不会改密码,必须直接改)
docker compose exec -T app php artisan tinker --execute='
$u=\App\Models\AdminUser::where("username","admin")->first();
$u->password=\Illuminate\Support\Facades\Hash::make("新密码"); $u->save(); echo "updated";
'
```

## Pitfall / Why

**结论**：要改已存在管理员的密码，**别再跑 `system:init`**，直接 tinker 改 `password` 字段。

**Why**：`SystemInit.php::seedSuperAdmin` 只在 `AdminUser` 不存在时写入 `$admin->password = $password`；已存在分支只执行 `$admin->is_super = 1; $admin->save();`，密码字段被原样跳过。这是"创建 or 更新"逻辑不对称导致的。

**How to apply**：(1) 新账号 → system:init（一并初始化站点/菜单）。(2) 已有账号改密码 → tinker `$u->password=Hash::make(...)`。(3) 密码参数永远传哈希，命令里 `Hash::make(...)` 现生成；bcrypt 哈希含 `$`，shell 里用**双引号**传 `"$HASH"` 防止二次展开。(4) 跑前确认 env 里 `SITE_ID`/`TENANT_ID` 已配，否则 `Site ID is not exists`。

## Related

- [[install-php-extensions-exit-100]] — 镜像缺 intl 会让 Laravel `Number::format()` 报错，应用跑不起来就无法建/用管理员
- [php_artisan.md](./php_artisan.md) — Laravel artisan 常用命令速查（migrate / tinker / route:list 等）

---
Source: distill from CC session
Date: 2026-06-26
Rounds covered: round #4 - #5
