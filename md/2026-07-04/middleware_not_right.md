收到,你去吃饭。这 3 个想法很有价值,我逐个评透 —— 而且 **1 和 3 合起来其实指向一个比原设计更好的方案**,2 有个绕不过的死穴。趁你吃饭我把最难的 Customer 也验证好。

## Todo 1 + Todo 3 合看:你的直觉对,但要分两维

先认错:**你说得对,我之前把 `target` 理解浅了** —— 我当成了 `$this->name`/`$this->username`。看你截图,`target` 是**"这次操作针对的那个目标对象"的人类可读标识**,而且经常要**组装**:`Product Category: Electronics`、`Wireless Earbuds X5 (ID: 3371)`、`Footer Navigation Links` —— 有类型前缀、有 ID、来自不同字段。

这恰好把三个契约方法**劈成两类**:

| 契约方法                 | 本质                                                                    | 能不能用映射表           |
| ------------------------ | ----------------------------------------------------------------------- | ------------------------ |
| `operationApplication()` | model → 固定字符串(`AdminUser`→`users`)                                 | ✅ **纯映射**            |
| `operationModule()`      | model → 固定字符串                                                      | ✅ **纯映射**            |
| `operationTargetName()`  | 取/**组装**这条记录的目标名(`"分类: {$name}"`、`"{$name} (ID: {$id})"`) | ❌ 因对象而异,**要逻辑** |

所以**你的映射表想法是对的,但只对 application/module 成立**;`target` 那一维用映射表表达不了(它不是"取哪个字段"这么简单,是"怎么拼")。

**最佳形态 = 混合**(在 Provider 注册一张表):

```php
// 简单模块：一行搞定，零 model 改动
Role::class => ['application' => 'roles', 'module' => 'access', 'target' => 'name'],
// 复杂 target：给个闭包，把"怎么拼"就近写在注册处
SeoBlock::class => ['application' => 'aio', 'module' => 'seo',
    'target' => fn($m) => $m->block_title],
Product::class => ['application' => 'e-commerce', 'module' => 'catalog',
    'target' => fn($m) => "{$m->name} (ID: {$m->id})"],
```

Observer 改成"**先查这张表,查不到再看 model 有没有实现契约**"。这样:

- application/module:集中一处、加一行,**不碰 model**(你要的省事)。
- target:简单的写字段名、复杂的写闭包,**灵活性保住**(你截图那些拼接都能表达)。
- 契约方法降级为"逃生口"——某个 model 逻辑特别刁钻时才实现。

`★ Insight ─────────────────────────────────────`

- 原设计 line 181 特意说"不必维护全局映射表",它选契约是赌**模块自治**(每个 model 自带说明,不怕全局表膨胀/漏配)。你的映射表是相反赌注:**集中可见**(一处看全,但表随模块长、和各 model 耦在一个文件)。两者都成立,是团队口味。
- 混合方案取中间:把"纯映射"的两维集中(省事),"要逻辑"的一维就近留闭包(灵活)。**约定优于配置 + 逃生口**,是这类"元数据描述"的经典解法。
  `─────────────────────────────────────────────────`

**结论**:能改造,推荐混合方案。不过这是"单条那半"的事(已定 batch 之后统一做),到时按这个来,比逐个 model 写三方法省。

## Todo 2:middleware 统一 batch —— 有死穴,做不干净

**核心矛盾**:batch 日志要记的是 `changes = [{id, name}]`,而且是**收窄后真正被操作的那些**(绑用户的角色跳过、已是目标状态的跳过、被占用的等级跳过)。这两样数据**只活在 service 方法内部**,middleware 够不着:

- **name 必须在 delete/update 之前 `get`** —— 删了就没了。middleware 卡在 controller 前后两难:
  - **before**:请求没执行,只能拿到请求体里的**原始 ids**;拿不到 name(要查库),更不知道 service 会把哪些收窄掉。
  - **after**:删除已发生,**name 已经没了**;也不知道 service 内部最终动了哪几条。
- 你能从 URL 判断"这是个 batch",没错 —— 但**日志要的不是"发生了 batch",是"到底动了哪几条、它们叫什么"**,而这个 URL 和请求参数都告诉不了你。

一句话:**middleware 知道"来了一次批量请求",不知道"真正改了谁"**。而那 3-4 行 logBatch 之所以必须待在 service 里,就是因为**只有那里同时握着"收窄后的集合"和"删除前的名字"**。

但你的直觉**有对的部分 —— 减少散点**。现状其实已经往这个方向做了两件事:

1. **公共上下文已经集中在中间件了**(原设计 line 169):operator / ip / user_agent / 推断的 application,由中间件绑到请求作用域,service 和 observer 自动取,不用每处传。**能上提的都上提了**。
2. **logBatch 已经把每处压到 3-4 行**(action + 集合 + nameKey + application),散点但极薄。

**结论**:能集中的(上下文)已在中间件;不能集中的(改了谁+叫什么)本质必须在 service。**继续散点 + logBatch 是对的**,middleware 替不掉那 3-4 行。(除非你接受"只记 id 不记 name、且不收窄"——那 middleware 能干,但你们要 name + 收窄,所以不行。)

---

## Customer:趁你吃饭我 fork 验证好

既然 todo 2 结论是继续散点,Customer(§4.4)还是散点做。它是所有 batch 里**最容易写错的**(分组/标签/等级共用 `baseDelete`/`changeStatus`,还要按 count 区分单条/批量)。我趁你吃饭 fork 一个去把它核对准 + 写测试(含"count==1 走单条、count>1 走批量"两种断言)+ 容器跑绿,你回来直接拿一套验证过的,不用陪试错:
