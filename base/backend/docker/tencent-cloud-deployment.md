# 腾讯云 Docker 部署全流程

## 环境准备

### 安装 Docker（国内服务器）

`download.docker.com` 在国内被墙，必须用腾讯云镜像源：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.tencent.com/docker-ce/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://mirrors.tencent.com/docker-ce/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

### 配置 Docker Hub 镜像加速

`/etc/docker/daemon.json` 只加速 Docker Hub（`docker.io`），**不能加速 `ghcr.io`**：

```json
{
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
}
```

```bash
sudo systemctl daemon-reload && sudo systemctl restart docker
```

> ⚠️ `ghcr.io`（GitHub Container Registry）无法通过 registry-mirrors 加速，需要在 Dockerfile 里绕开。

---

## Dockerfile 最佳实践（Python + uv）

### 关键点

1. **不能用 `COPY --from=ghcr.io/astral-sh/uv`**，ghcr.io 在国内被墙
2. 改用 pip + 腾讯云 PyPI 镜像安装 uv（pip `-i` 与 uv `--index-url` 参数不通用，原理见 production-deployment.md §4）
3. `pyproject.toml` 先于源码复制，利用 Docker layer 缓存（原理见 production-deployment.md §5）

```dockerfile
FROM python:3.13-slim

# 用腾讯云 PyPI 镜像安装 uv（避免访问 ghcr.io）
RUN pip install -i https://mirrors.tencent.com/pypi/simple/ uv

WORKDIR /app

COPY pyproject.toml uv.lock ./
# uv sync 走腾讯云镜像
RUN uv sync --frozen --no-dev --index-url https://mirrors.tencent.com/pypi/simple/

COPY . .

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
```

### entrypoint.sh

```bash
#!/bin/sh
set -e

echo "运行数据库迁移..."
uv run alembic upgrade head

echo "启动 FastAPI 服务..."
exec uv run gunicorn main:app \
  -k uvicorn.workers.UvicornWorker \
  --workers 4 \
  --bind 0.0.0.0:8000 \
  --timeout 120 \
  --graceful-timeout 30 \
  --access-logfile - \
  --error-logfile -
```

> worker 数量建议：CPU 核心数 × 2（详见 production-deployment.md §2）；各参数含义见 production-deployment.md §3

---

## docker-compose.yml

```yaml
name: coco

services:
  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: coco
      POSTGRES_USER: coco
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-coco}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coco"]
      interval: 5s
      timeout: 5s
      retries: 5

  backend:
    build:
      context: ./apps/backend
    restart: unless-stopped
    ports:
      - "8000:8000"
    env_file:
      - ./apps/backend/.env
    environment:
      DATABASE_URL: postgresql+asyncpg://coco:${POSTGRES_PASSWORD:-coco}@db:5432/coco
    depends_on:
      db:
        condition: service_healthy

volumes:
  postgres_data:
```

> `depends_on: condition: service_healthy` 确保 PostgreSQL 完全就绪后再启动后端，避免迁移时连不上数据库。

---

## Docker vs systemctl

有了 Docker，业务服务不再需要 systemctl 管理：

```
# 以前
systemctl → PostgreSQL
systemctl → uvicorn
systemctl → Nginx

# 有了 Docker
systemctl → Docker（只管这一个）
  └── docker compose
      ├── db
      └── backend
```

`restart: unless-stopped` = 相当于 `systemctl enable`，服务器重启后自动拉起。

---

## 常见坑

### `CREATE TYPE IF NOT EXISTS` 不支持

PostgreSQL **不支持** `CREATE TYPE IF NOT EXISTS`（只有 TABLE/INDEX/SCHEMA 等支持）。

本地没暴露此问题的原因：本地数据库已有 `alembic_version` 记录，迁移不会重复执行。服务器全新空库才会触发。

**修复**：直接去掉 `IF NOT EXISTS`，Alembic 保证迁移只执行一次。

---

## HTTPS 配置（Nginx 反向代理）

### 端口说明

- 对外暴露 443（HTTPS），无需在 URL 里指定端口
- Nginx 监听 443，内部转发到 Docker 容器的 8000
- `https://api.cocoai.chat` = 自动走 443 → Nginx → 8000

### Nginx 配置

```nginx
server {
    listen 80;
    server_name api.cocoai.chat;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name api.cocoai.chat;

    ssl_certificate /home/ubuntu/ssl/api.cocoai.chat_bundle.crt;
    ssl_certificate_key /home/ubuntu/ssl/api.cocoai.chat.key;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### SSL 证书（腾讯云免费证书）

1. 腾讯云控制台 → SSL证书 → 申请免费证书
2. 域名填子域名（如 `api.cocoai.chat`）
3. 验证方式选**自动DNS验证**（域名在腾讯云则自动完成）
4. 下载 Nginx 格式，得到 `.crt` 和 `.key` 两个文件
5. 上传到服务器：`scp *.crt *.key ubuntu@IP:~/ssl/`

> 免费证书 90 天有效期，可手动续签。每个子域名需单独申请，通配符证书需付费。

### Nginx 启用配置

```bash
sudo ln -s /etc/nginx/sites-available/api.cocoai.chat /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## 部署命令速查

```bash
# 首次部署
docker compose up -d --build

# 更新代码后重新部署
git pull
docker compose down   # ⚠️ 不要加 -v，加了会销毁数据库 volume！
docker compose up -d --build

# 查看日志
docker compose logs -f backend
docker compose logs -f db

# 重启服务
docker compose restart backend
```
