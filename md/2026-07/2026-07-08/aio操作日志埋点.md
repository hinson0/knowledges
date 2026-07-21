# AIO 插件操作日志埋点（type=plugin，全手动 record）

## 结论
- AIO 所有 model 都 extend BaseModel（EventfulDeleteBuilder 会让 whereIn->delete 触发 deleted 事件），
  但 AIO 是运行时加载插件、不在 root composer PSR-4，OperationLogServiceProvider 启动时不会为其注册 observer，
  → 事件触发但无人接收 → 所有写入都必须手动 record()/logBatch()。**不返回 registerLines。**

## 埋点位置（均在 DB 提交后、仅成功、有实际变化才记）
- AioSeoTypicalPageService: addTypicalPages(updated)/removeTypicalPages(deleted)
- AioSeoPageKeywordService: copySelected/moveSelected(updated)、removeSelected/deleteKeywords(deleted)
  - syncPageKeywords(PUT update) 故意不埋：它被 AioSeoKeywordClusteringService 复用，埋了会污染 clustering 路径
- AioSeoCompetitorService: addCompetitor(created/updated)/removeCompetitor(deleted，软删 is_active=0 是 where()->update)
  - add/remove 原本整体包在 DB::transaction(fn) return 里；用 `&$logInfo` 引用把日志信息带出事务，事务返回后再 record
- AioSeoSetupService: submit(created，AioSeoSetupRun)

## 配置分类 slug
`'aio' => ['system_marketing', 'plugin_application_aio_seo_menu']`
- 顶层 Module=system_marketing（AIO 菜单 parent=plugin_application_seo_group，seo slug 也映射 system_marketing）
- 子 Menu code = AioMenuCode::MENU->value（plugins/aio/src/Enums/AioMenuCode.php），在 menus/admin.php 用作菜单码

## 测试 harness（关键）
- 照抄既有绿测试 AioSeoPageKeywordServiceDeleteTrackingTest：sqlite :memory: + 手建表 + mock 上下文
- 额外手建 operation_logs 表；aio_seo_pages 的 upsert 需要 uq_page 唯一索引；json_page.with('plugins') 需建 plugins 表
- fact#2 site_id 对齐：config(['app.site_id'=>FIXED_SITE_ID,'app.tenant_id'=>FIXED_TENANT_ID]) + OperationContext::set(['site_id'=>bytes])
  - FIXED_SITE_ID(AioSeoPlatformService::$FIXED_SITE_ID) == .env.testing SITE_ID
- 断言真正写出 OperationLog 行（record() 吞异常，写不出则 exists()=false 测试红）+ 断 code==0
- Bus::fake() 拦截 setup 的 SeoSetupOrchestratorJob 与 competitor 的 SyncTrackingCompetitorsJob

## 环境既存红测试（与本次改动无关，改前改后同样红）
- AioSeoCompetitorServiceSyncTrackingTest（11 红）、AioSeoPageKeywordServiceDeleteTrackingTest（2 红/2 绿）
