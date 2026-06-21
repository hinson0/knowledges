# Turbo 缓存:增量构建与 FULL TURBO(看见"跳过")

> 来源:本会话「模块 4」。在 monorepo(packages/shared、packages/ui、apps/api、apps/web)里通过"改一行 shared 源码"亲手观察 Turbo 的缓存命中/失效。依赖图:web→ui→shared、web→shared、api→shared,ui 不依赖 shared。

## Trigger Question

> 改了 `packages/shared/src/utils.ts` 一行后,哪些包会 cache miss(重建)、哪些继续 cache hit?还会出现 FULL TURBO 吗?

> 用户预测:"依赖 shared 的 web 包、api 包都会发生变化,也就是 cache miss";"没有 full turbo"。(预测全中)

## Key Takeaways

- **Turbo 按"任务"算哈希指纹**:每个 `包名#task`(如 `@repo/shared#build`)的指纹 = 该包源码 + 它依赖包的产物 + 任务配置(env/outputs 等)。只改一行字符,源码哈希就变(实测 shared 哈希 `8b4fe...` → `a86602...`)。
- **指纹沿依赖图"传染"**:shared 源码变 → shared 产物变 → 依赖它的 api/web 输入变 → 它们指纹也变 → 三个一起重建;ui 不依赖 shared → 输入不变 → 仍命中缓存。**决定缓存失效范围的依赖图,和决定构建顺序的是同一张图**(见 [[turbo-dependson-build-order]])。
- **改一个包的"爆炸半径" = 该包 + 它所有下游**。拆包越合理,半径越小,缓存命中率越高,CI 越快——这是 monorepo 要认真拆包的根本动机之一。
- **`FULL TURBO` 仅当所有任务全部命中缓存时出现**;只要有一个 cache miss 就消失,耗时也从全命中的 ~33ms 跳到真编译的 ~2.5s。
- **日志关键词要分清**:`cache miss, executing` = 这次真跑;`cache hit, replaying logs` = 回放上次的 stdout(看到详细日志 ≠ 这次真执行)。

## Schema / Field Table

改 shared 一行后 `turbo run build` 各包结果(依赖关系决定命中与否):

| 包 | 是否依赖 shared | 本次结果 | 含义 |
|---|---|---|---|
| `@repo/shared` | —(被改的源头) | `cache miss, executing`(哈希 8b4fe…→a86602…) | 源码变,真跑 tsc |
| `@repo/api` | 是 | `cache miss, executing` | 被传染,真跑 tsc |
| `@repo/web` | 是(经 ui + 直接) | `cache miss, executing` | 被传染,真跑 tsc && vite build |
| `@repo/ui` | 否 | `cache hit, replaying logs` | 输入未变,回放缓存 |
| demo-a/b/c | —(无 build 脚本) | 不在 Tasks 内 | 静默跳过 |

汇总行对照:
- 全命中(模块3,未改动):`Cached: 4 cached, 4 total` · `Time: 33ms >>> FULL TURBO`
- 改 shared 后(本次):`Cached: 1 cached, 4 total` · `Time: 2.494s`(无 FULL TURBO)

## Code Example

```text
# 改 packages/shared/src/utils.ts 一行 console.log 文案后:
$ pnpm exec turbo run build

┌─ @repo/shared#build > cache miss, executing a86602cfa3a20367
$ tsc
┌─ @repo/api#build    > cache miss, executing 5c11934d8ae80ca7
$ tsc
┌─ @repo/web#build    > cache miss, executing 7dda0b8c230b9700
$ tsc && vite build      # ✓ built in 294ms
┌─ @repo/ui#build     > cache hit, replaying logs 4bcb99dde61996f2

 Tasks:    4 successful, 4 total
Cached:    1 cached, 4 total
  Time:    2.494s          # ← 无 FULL TURBO
```

```bash
# 强制忽略缓存全部重跑(调试缓存问题时用)
pnpm exec turbo run build --force

# 改 shared 前预判"爆炸半径"(shared + 所有下游)
pnpm exec turbo run build --filter='...@repo/shared'
```

## Pitfall / Why

- **为什么没改源码的 api/web 也重建**:Turbo 把"依赖包的产物"算进了消费者的指纹。上游产物一变,下游输入即变,指纹随之失效——缓存沿依赖边自动传染,不是 bug。
- **`replaying logs` 会"骗眼睛"**:cache hit 时 Turbo 把上次的 stdout 原样回放(连 vite 的产物清单都照打),看起来像真跑了,实际是瞬时回放。判断"真跑还是回放"只看 `executing` vs `replaying logs`,别看日志详细程度。
- **`FULL TURBO` 的触发是"全有或全无"**:任一任务 miss 就不显示;它是"本次零真实工作"的标志。
- **Turbo 版本/全局配置变化会重算所有缓存键**:本会话用户中途把 turbo 2.9.16 升到 2.9.18 并改了 `$schema`,导致 ui 的哈希基线整体变了(`ea16033…`→`4bcb99…`)。这不影响"ui 是 hit 而非 miss"的结论,但解释了为何同一个包的哈希在两次运行间会变——升级工具链会让全局缓存基线重置。
- **延伸(工程化)**:开启 Remote Cache 后,同事或 CI 可直接复用别人已构建的产物,实现"同一指纹全公司只构建一次"。本次按"日常使用"深度未展开。

## Related

- [[turbo-dependson-build-order]] — 同一张依赖图如何决定构建顺序(^build / 自环)
- [[turbo_persistent]] — dev/persistent 任务为何 `cache: false`(长驻服务不缓存)
- [[pnpm-workspace-symlink-resolution]] — 依赖图的来源:workspace 软链与"谁声明谁才有"
