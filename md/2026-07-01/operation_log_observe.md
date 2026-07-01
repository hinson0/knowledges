你这个问题问到**最关键的点**上了 —— 而且你的困惑来源我猜到了:**你以为「监听」是能在这个方法里看到的一段代码。恰恰相反,「监听」的本质就是「你在这个方法里看不到它」。**

先揭穿一件事:**这个 `updateUser` 方法里,其实产生了两条操作日志,走的是两条完全不同的路径。你只看到了其中一条(手动那条),另一条(监听那条)是隐形的。**

## 把这两条路径在你代码里标出来

```php
// ────────── ①【自动/监听】这一行 ──────────
$saveResult = $adminUserInfo->update($saveData);
//            ↑ 改了 name/username/status 等 AdminUser 自己的字段
//              入库后 Eloquent 自动触发 updated 事件
//              → 在【别的文件】里的 Observer 被勾起来，自动记一条 "updated AdminUser"
//              → 记日志的代码根本不在这个方法里！你在这看不到它，这才是「监听」

// ────────── ②【手动/埋点】这一段 ──────────
$adminUserInfo->roles()->sync($params['role_ids']);   // 改的是「角色关联」，不是 AdminUser 字段
app(OperationLogService::class)->record([              // ← 你看到的这句，是手动补记
    'action' => OperationAction::RoleAssigned->value,
    ...
]);
```

## 为什么 ② 必须手动、不能靠监听?

看仔细:`$adminUserInfo->roles()->sync(...)` **改的不是 AdminUser 表自己的字段**,而是操作一张**中间表(pivot table)** `model_has_roles`(记录「哪个用户拥有哪些角色」的关联表)。

**Eloquent 的 `updated` 事件,只在「模型自己的字段」变更入库时触发。** 你 `sync` 角色关系,AdminUser 这行数据的 name/status 一个字没动 → **不触发 `updated` 事件** → Observer 那条「自动记账」勾不起来 → 抓瞎。

所以角色变更这种「关联关系变了、但主模型字段没变」的动作,监听抓不到,**必须手动 `record()` 补一刀**。这就是为什么你在这里看到一句显式的 `app()->record()`。

## 「监听」的代码到底在哪?

不在 `updateUser` 里,也不在任何业务方法里。它在**一次性注册**的地方,大概长这样(在某个 ServiceProvider 或模型注解里):

```php
// 某个 ServiceProvider::boot() 里，全项目只写一次
AdminUser::observe(OperationLogObserver::class);

// 或者 AdminUser 模型头顶一个注解
#[ObservedBy(OperationLogObserver::class)]
class AdminUser extends BaseModel { ... }
```

注册完之后,**只要任何地方 `$anyAdminUser->update(...)`**,不管是 `updateUser` 还是别的一百个方法,Eloquent 都会自动把 `OperationLogObserver::updated()` 勾起来记账。业务代码**完全不知道**有人在监听 —— 这就是解耦。

`★ Insight ─────────────────────────────────────`
「**手动 record**」= 我**主动**在业务代码里喊「记一笔」,看得见、写得死。
「**监听 Observer**」= 我**事先埋好耳朵**(注册 Observer),业务代码正常 `update()`,事件系统**替我自动**喊「记一笔」—— 记账代码和业务代码物理分离,业务方无感知。

你之所以觉得「哪里是监听?这不明明手动插的吗」,是因为你盯着的 `app()->record()` **正好是手动那条**(角色变更,监听抓不到才手动补);而真正被监听的 `$adminUserInfo->update($saveData)`,它触发的日志代码**故意不在这里** —— 监听的价值就是「让你在业务代码里看不见它」。
`─────────────────────────────────────────────────`

## 这就是「方案 A 混合式采集」名字的由来

| 采集方式                | 抓什么                                                     | 代码在哪              | 本方法的例子                        |
| ----------------------- | ---------------------------------------------------------- | --------------------- | ----------------------------------- |
| **自动(监听 Observer)** | 模型自己字段的增删改(改名、改状态)                         | Observer,业务方看不见 | `$adminUserInfo->update($saveData)` |
| **手动(显式埋点)**      | 事件抓不到的动作:登录、登出、导出、**角色 sync(pivot 表)** | 业务代码里显式写      | `app()->record([RoleAssigned])`     |

**一句话:改 name 那条是「监听自动记」(代码在 Observer,你看不见);改角色那条是「手动补记」(代码在这,你看得见)—— 同一个方法,两条路径,这就是「混合式」。**
