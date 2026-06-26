# install-php-extensions 构建失败 (exit code 100)

## Trigger Question

> (Dockerfile 第 9 行)
> `RUN install-php-extensions pdo_mysql mbstring zip bcmath gd exif pcntl intl imagick`
> failed to solve: process "/bin/sh -c install-php-extensions ..." did not complete successfully: exit code: 100
> 为什么来着 刚没清掉了

> In Number.php line 453:
> The "intl" PHP extension is required to use the [format] method.

背景：`FROM php:8.3-cli` 的镜像里用 `mlocati/docker-php-extension-installer` 的 `install-php-extensions` 脚本一次性装多个 PHP 扩展，构建在这一层挂掉（exit 100）；终端刷屏后真正报错被冲走，只剩最后那行退出码。随后跑 Laravel 应用又冒出 "intl required" —— 两个报错其实是同一个根因。

## Key Takeaways

- **exit code 100 = 脚本内部 `apt-get` 的退出码**，不是 PHP 扩展编译本身失败。`install-php-extensions` 会先 `apt-get update && apt-get install` 装每个扩展的系统依赖（imagick→`libmagickwand-dev`、gd→libpng/jpeg/freetype 等）。
- 最常见诱因是**网络 / Debian 镜像源拉不到包**；`imagick` 是这串里最重、最容易失败的扩展。光凭 100 只能定位到 "apt 失败"，**具体哪个包必须看被刷掉的明文日志**。
- **下游连锁**：扩展没进镜像 → 运行镜像缺 `intl` → Laravel `Number::format()` 走 `NumberFormatter` → `ensureIntlExtensionIsInstalled()` 检测 `extension_loaded('intl')` 为 false → 抛 `The "intl" PHP extension is required`。所以 `Number.php` 报错是构建失败的症状，不是新问题。
- 诊断：`docker run --rm <img> php -m | grep -iE '^intl$|^imagick$'` 逐镜像查谁缺扩展；`docker history <img>` 看构建历史里是否根本没有 `RUN install-php-extensions` 这一层（缺层 = 用旧 Dockerfile 构建的旧镜像）。
- **改代码不用重建**（`./:/workspace` volume 挂载），但 **PHP 扩展装在镜像层里、不在挂载卷**，加扩展必须重建镜像才生效 —— 这就是改了 Dockerfile 扩展行不重建仍报 "intl required" 的原因。

## Code Example

```bash
# 1) 无缓存重跑构建,强制全量明文日志并存盘(把被刷掉的真因捞回来)
docker build --no-cache --progress=plain \
  -f docker/php/Dockerfile -t cms-php:debug . 2>&1 | tee /tmp/php-build.log

# 2) 在日志里定位真因
grep -nE "E:|Unable to|Failed to fetch|Could not|Hash Sum|imagick|libmagick" /tmp/php-build.log
#   Failed to fetch / Could not resolve 'deb.debian.org' / Hash Sum mismatch → 网络/源问题
#   libmagickwand-dev / imagick 报错                                        → imagick 依赖问题

# 3) 逐个镜像确认哪个缺扩展(intl/imagick)
docker run --rm <image> php -m | grep -iE '^intl$|^imagick$'

# 4) 看某镜像构建历史是否缺 install-php-extensions 那一层
docker history <image>
```

对应的 Dockerfile 片段（pin 到固定脚本版本保证可复现）：

```dockerfile
FROM php:8.3-cli
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/download/2.11.12/install-php-extensions /usr/local/bin/
RUN install-php-extensions \
    pdo_mysql mbstring zip bcmath gd exif pcntl intl imagick
```

## Pitfall / Why

**结论**：`install-php-extensions ... imagick` 报 exit 100 时，先怀疑 apt（网络/源），而不是去改 PHP 扩展代码。

**Why**：这一整行被 `/bin/sh -c` 当成一条命令跑，脚本内部某步 `apt-get` 失败就把 100 透传出来。同机器上 `ce-php83-runner`、`cms-center-in-docker` 等镜像 intl+imagick 都装成功过，证明环境本身能装 —— 所以单次 100 多半是构建那一刻的网络抖动 / base 镜像漂移。

**How to apply**：(1) 用 `--no-cache --progress=plain | tee` 重跑抓真因；大概率重试即过。(2) 若日志明确指向 imagick/libmagickwand-dev，再单独处理 imagick。(3) 修好构建后**必须重建并重起运行镜像**（见 [[docker-compose-rebuild-no-cache]]），否则应用还在用缺 intl 的旧镜像，`Number.php` 报错不会消失。

## Related

- [[docker-compose-rebuild-no-cache]] — 改完 Dockerfile/扩展后如何无缓存重建并让容器真正换新镜像
- [[cms-create-super-admin]] — 镜像装好 intl 后才能正常跑 system:init 建管理员

---
Source: distill from CC session
Date: 2026-06-26
Rounds covered: round #2 - #3
