# Docker 无缓存重建 + 让运行容器真正换新镜像

## Trigger Question

> 如果一个 Container 已经在跑，然后我需要去重构它，应该去用哪个命令能确保没有缓存？

背景：改了 `docker/php/Dockerfile`（加 PHP 扩展），想无缓存重建镜像，并让已经在跑的容器用上新镜像。项目用 docker compose（service `app`，镜像 `cms-center-in-docker`）。

## Key Takeaways

- **三个"缓存"是三回事，别只记 `--no-cache`**（见下表）。
- 核心坑：`docker compose build` **只产出新镜像、不碰运行中的容器**。只 build 不 up，旧容器仍指着旧镜像跑 —— 必须 `up` 一次容器才换镜像。
- compose 推荐两步：先 `build --no-cache --pull`，再 `up -d --force-recreate`。
- ⚠️ **不要用 `docker compose down -v`** 来"清干净"：`-v` 会删命名卷（本项目有 `mysql-data`）= 清空数据库。只想刷镜像用 `docker compose rm -sf app`。
- 改代码不用重建（volume 挂载）；改 Dockerfile/装扩展才需要这套重建流程。

## Field Table

| 标志 | 作用域 | 解决什么 |
|------|--------|----------|
| `--no-cache` | 构建 | 忽略 Dockerfile 的**构建层缓存**（`RUN install-php-extensions` 等不复用旧结果） |
| `--pull` | 构建 | 重新拉**基础镜像**（如 `php:8.3-cli`），防本地 base 漂移/陈旧 |
| `--force-recreate` | 运行 | 处理**已在跑的容器**：哪怕 compose 觉得没变也强制用新镜像重建容器 |

## Code Example

```bash
# docker compose:无缓存重建镜像 + 强制用新镜像重建容器(推荐两步)
docker compose build --no-cache --pull app
docker compose up -d --force-recreate app

# 想容器层面也彻底干净:先删旧容器再起
docker compose rm -sf app          # stop + 删掉旧 app 容器(不碰数据卷)
docker compose build --no-cache --pull app
docker compose up -d app
```

```bash
# 裸 docker 对照
docker build --no-cache --pull -f docker/php/Dockerfile -t <img> .
docker stop <ctr> && docker rm <ctr>
docker run -d --name <ctr> <img>
```

## Pitfall / Why

**结论**：重建镜像后必须 `up`/重起容器，旧容器不会自动换新镜像。

**Why**：镜像和容器是两个对象。`build` 生成新镜像 ID，但运行中的容器仍绑定它启动时的旧镜像 ID。本会话亲历：旧 `cms-center-app` 镜像构建历史里根本没有 `install-php-extensions` 层（缺 intl），却还能跑，正是"只 build 没换容器/用了旧镜像"的同款现象。

**How to apply**：(1) 要"真·干净"= `--no-cache`（构建层）+ `--pull`（基础镜像）+ `--force-recreate`（容器）三者齐上。(2) 怀疑 base 镜像漂移时一定加 `--pull`，只 `--no-cache` 仍会复用本地旧 base。(3) 清理只删容器用 `rm -sf`，**永远不要随手 `down -v`**，那会连数据库卷一起删。

## Related

- [[install-php-extensions-exit-100]] — 加 PHP 扩展为什么必须走这套重建（扩展在镜像层、不在挂载卷）
- [[cms-create-super-admin]] — 重建出带 intl 的镜像后才能正常跑 artisan 建管理员

---
Source: distill from CC session
Date: 2026-06-26
Rounds covered: round #4
