# phpdotenv 变量解析的坑:未定义 vs 空值、顺序、内联注释

> 说明:此条在 docker 化的 .env 重排中被触发并验证,与 [[docker-compose-dotenv-interpolation-warning]] 直接相关。

## Trigger Question
> `.env` 文件里面 `SITE_KEY=` 这样做之后,那 Laravel 会出现什么问题?

## Key Takeaways
- **未定义 vs 定义为空,结果不同**:
  - `${SITE_KEY}` 未定义 → phpdotenv **保留字面量** `'${SITE_KEY}'`(非空、truthy)。
  - `SITE_KEY=`(定义为空) → 替换成 `''`(空串)。
- **顺序敏感**:phpdotenv 从上往下解析,`${VAR}` 只能引用**更早**定义的变量;定义放在引用行下方,则解析到引用时仍是未定义。
- `env('KEY', '默认值')` 的默认值**仅在变量返回 null(不存在)时生效**;空串和字面量都是非 null,默认值不会兜底。
- phpdotenv 会**剥离行尾内联注释**:`X=https://a.cn  #注释` 解析出的值是 `https://a.cn`。

## Schema / Field Table
| `.env` 中 SITE_KEY 状态 | `${SITE_KEY}` 解析 | `env('PLATFORM_CLIENT_ID')` |
|---|---|---|
| 未定义 | 保留 `${SITE_KEY}` 字面量 | `'${SITE_KEY}'` |
| `SITE_KEY=`(空) | `''` | `''` |
| 想让 `env()` 默认值生效 | — | 需删/注释掉 `PLATFORM_CLIENT_ID` 行,使其返回 null |

## Code Example
```bash
# 实测 phpdotenv 剥离行尾内联注释
printf 'X=https://platform-dev.cedemo.cn  #注释\n' > /tmp/envtest/.env
php -r 'require "vendor/autoload.php"; \
  $r=Dotenv\Dotenv::createArrayBacked("/tmp/envtest")->load(); echo $r["X"];'
# 输出: https://platform-dev.cedemo.cn
```

## Pitfall / Why
- 现实后果:`PLATFORM_CLIENT_ID="${SITE_KEY}"` 在 SITE_KEY 未注入时,config 实际拿到字符串 `'${SITE_KEY}'`(垃圾值)——既不是真凭据,也不是 config 里写的 fallback 默认值;若去调平台 OAuth 会失败。
- 设计意图:`${SITE_KEY}` 通常由部署平台注入为真实环境变量;本地未注入时退化为字面量。生产注入真值时不会被 `.env` 的空行覆盖,见 [[laravel-dotenv-env-var-precedence]]。

## Related
- [[docker-compose-dotenv-interpolation-warning]]
- [[laravel-dotenv-env-var-precedence]]
