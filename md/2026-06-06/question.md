# 仓库指南

## 项目结构与模块组织

这个仓库是一个 Laravel 12 单体项目。核心应用代码位于 `app/`，HTTP 入口位于 `routes/`，运行时配置位于 `config/`。

数据库迁移、模型工厂和 Seeder 位于 `database/`。Blade 视图位于 `resources/views/`，公开 Web 资源位于 `public/`，可复用的代码生成模板位于 `stubs/`。

仓库专属扩展位于 `plugins/<slug>/`，并通过 `plugin.json` 清单文件描述；主题预设存放在 `preset-themes/`。测试分布在 `tests/Feature`、`tests/Unit` 和 `tests/Helpers`。

## 构建、测试与开发命令

使用 `composer install` 安装 PHP 依赖，使用 `npm install` 安装前端工具链。

`composer dev` 会在同一个进程组中启动本地 Laravel 服务、队列监听器、日志 tail 和 Vite。

`npm run dev` 只启动前端监听器，`npm run build` 用于生成生产环境资源。

`composer test` 会清除缓存配置，并运行 `php artisan test`。

数据库结构变更使用 `php artisan migrate`；如果需要种子数据，再运行 `php artisan db:seed`。

## 编码风格与命名规范

遵循 `.editorconfig`：UTF-8、LF 换行，默认 4 空格缩进，YAML 使用 2 空格缩进。

PHP 代码遵循 PSR-12 / Laravel 风格，并使用 `vendor/bin/pint` 格式化。

使用 `vendor/bin/phpstan analyse` 运行静态分析；本仓库使用 Larastan level 5，分析范围包括 `app/`、`routes/` 和 `database/`。

类名使用 StudlyCase，方法和属性使用 camelCase，数据库字段和配置 key 使用 snake_case，插件目录也使用 snake_case，例如 `plugins/seo_index/`。

## 测试指南

PHPUnit 11 配置在 `phpunit.xml` 中。

纯逻辑测试放在 `tests/Unit`，HTTP、命令和集成测试放在 `tests/Feature`。

测试文件命名为 `*Test.php`。当测试准备逻辑重复时，复用 `tests/Helpers` 中的 helper。

默认测试配置连接 MySQL 数据库 `cecmf_test`，主机为 `mysql-test`，所以运行完整测试套件前需要确认该服务可用。

## Commit 与 Pull Request 指南

近期提交历史使用 Conventional Commit 风格，例如 `feat(seo): ...` 和 `fix(json-page): ...`。

继续使用 `type(scope): summary` 格式，scope 应与修改的模块或插件对应。

Pull Request 应包含简短的问题/解决方案摘要、关联任务或 issue、测试证据，例如 `composer test`，以及 Blade 或后台 UI 变更的截图。

如果涉及迁移、队列行为或 `.env` 变更，需要明确说明。

## 安全与配置建议

从 `.env.example` 开始配置，永远不要提交 `.env`、密钥或 `storage/` 中生成的文件。

测试凭据应与本地开发值分开。

## 当修改插件加载、动态路由或计划任务时，需要记录所需的配置开关，并确认相关 `plugin.json` 清单保持同步。

---

结论：你感觉对了。现有 `AGENTS.md` 不是没用，但它更像一份“仓库 README 摘要”，不是一份“约束 Codex 行为的开发协议”。

它现在主要提供了这些信息：

- 项目是 Laravel 12 单体应用
- 目录分别放什么
- 常用命令是什么
- 编码风格、测试、提交规范
- 安全配置注意事项

这些对新人了解仓库有帮助，但对“防止 Codex 瞎改”帮助很弱。

主要问题是：

1. **没有定义 Codex 什么时候可以改代码**
   现在没有写“默认只分析”“必须用户明确说修改才动手”“只分析时禁止编辑文件”。

2. **没有定义改动边界**
   没有限制不能碰 `.env`、CI/CD、迁移、插件清单、生产配置、锁文件、生成文件等高风险区域。

3. **没有定义修改前流程**
   没要求先说明计划、影响范围、预计修改文件，也没要求大改前等待确认。

4. **没有禁止顺手重构**
   Codex 最容易的问题是为了“顺手优化”扩大范围。现在这份文件没有明确禁止无关重构、批量格式化、重命名、移动文件。

5. **没有保护用户已有改动**
   虽然我系统层面有“不回滚用户改动”的规则，但写进仓库规则会更稳，尤其是多人或多工具协作时。

6. **测试要求太泛**
   只说了 `composer test`，但这个仓库测试依赖 `mysql-test`，实际开发时更需要说明：能跑哪些就跑哪些，不能跑要说明原因；小改跑定向测试，大改再跑全量。

7. **缺少高风险模块规则**
   这个项目有插件加载、动态路由、低代码、权限、队列、SEO、MCP、数据库迁移，这些都应该被标为“改动前必须额外说明影响”。

所以我建议你把它改成两部分：

- **Repository Context**：保留当前这些仓库说明，但压缩。
- **Codex Operating Rules**：新增强约束，明确“怎么工作、怎么改、怎么验证、哪些不能碰”。

一句话评价：
现在的 `AGENTS.md` 适合作为项目简介，不适合作为 Codex 开发护栏。需要重写或大幅补充“行为约束”。
