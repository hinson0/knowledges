# Vite 本地代理与 Laravel 社交分享场景创建接口

## 关键接口路径

前端开发环境看到的请求路径：

```text
POST /vite-proxy/api/site/social-share/scenarios
```

实际后端真实路径：

```text
POST /api/site/social-share/scenarios
```

## 前端调用链

1. 入口页面：`ce-site-backend/src/pages/marketing/share-scenario/index.tsx`
2. 点击“新增场景”确认后调用 `createScenario({ name: values.name.trim(), enabled: values.enabled ?? true })`
3. `createScenario` 定义在 `ce-site-backend/src/models/socialShare/socialShare.ts`
4. 请求配置：
   - `method: 'post'`
   - `url: ApiEndpoints.SocialShareScenarios`
   - `data`
5. 接口常量在 `ce-site-backend/src/models/apis.ts`，值为 `'/api/site/social-share/scenarios'`
6. 开发环境下，`ce-site-backend/src/hooks/useAxios.tsx` 会自动加 `baseURL`：`EnvConfig.getProxyPrefix()`，即 `/vite-proxy`

所以前端最终发出的完整 URL 是：

```text
/vite-proxy/api/site/social-share/scenarios
```

## Vite 代理转发规则

1. Vite 配置文件：`ce-site-backend/vite.config.ts`
2. 代理会把请求路径中的 `/vite-proxy` 前缀去掉，变成：

```text
/api/site/social-share/scenarios
```

1. 然后转发到后端服务地址，开发环境里由 `.env.development.local` 配置，一般是：

```text
http://127.0.0.1:8001
```

## 后端路由与处理

1. Laravel 路由定义在：`cms-center/routes/api.php`
2. 关键路由项：

```php
Route::post('scenarios', [SocialShareController::class, 'store']);
```

1. 外层路由前缀为：
   - `api`
   - `site/social-share`
2. 因此最终真实后端路径为：

```text
POST /api/site/social-share/scenarios
```

1. 路由对应控制器方法：
   - `cms-center/app/Http/Controllers/Site/SocialShareController.php`
   - `public function store(SocialShareRequest $request)`

## 校验与创建逻辑

1. 参数校验由 `cms-center/app/Http/Requests/Site/SocialShareRequest.php` 负责
2. 校验规则：
   - `name`：必填，字符串，最长 200
   - `enabled`：可选，布尔值
3. 业务逻辑由 `cms-center/app/Services/SocialShare/SocialShareService.php` 处理
4. 关键方法：`createScenario(string $siteId, array $params)`

该方法执行流程包括：

- 规范化并清理 `name`
- 检查同一站点下名称是否重复
- 计算排序值 `sort`
- 写入数据库表 `site_social_share_scenarios`
- 返回创建后的场景数据

## 完整调用流程

```text
用户点击新增场景
  ↓
share-scenario/index.tsx 调 createScenario()
  ↓
socialShare.ts 发 POST /api/site/social-share/scenarios
  ↓
useAxios 在开发环境加 baseURL /vite-proxy
  ↓
浏览器实际请求 /vite-proxy/api/site/social-share/scenarios
  ↓
vite.config.ts 去掉 /vite-proxy，转发给 Laravel 8001
  ↓
cms-center/routes/api.php 匹配 POST /api/site/social-share/scenarios
  ↓
SocialShareController@store
  ↓
SocialShareRequest 校验 name / enabled
  ↓
SocialShareService::createScenario()
  ↓
写入 site_social_share_scenarios 表
  ↓
返回新建场景给前端
  ↓
前端把新场景加到左侧场景列表
```

---

## 知识点总结

- `/vite-proxy` 是前端开发环境的 Vite 本地代理前缀
- `/api/site/social-share/scenarios` 是后端 Laravel API 的真实接口路径
- 这类代理机制常用于本地开发时前端与后端跨域请求的统一转发
- 该场景创建流程涉及前端路径、代理 rewrite、后端路由、请求验证和业务创建逻辑
