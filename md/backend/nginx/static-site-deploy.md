# Nginx 静态站 + 反向代理部署速查

从 cocoai.chat / www.cocoai.chat / api.cocoai.chat 三域名合一部署沉淀。单机 Ubuntu + Nginx 1.24,静态站 + FastAPI 反代同机。

---

## 1 · 目录与文件布局（Ubuntu 惯例）

```
/etc/nginx/
├── nginx.conf              主配置(全局、http 块、include)
├── conf.d/                 推荐放业务站点配置
│   └── cocoai.chat.conf
├── sites-available/        备用方案(Debian 风格,和 conf.d 二选一)
├── sites-enabled/          sites-available 的软链
└── ssl/                    (可选)证书

/home/ubuntu/ssl/            证书存放(本项目)
/home/ubuntu/coco/apps/web/  静态站根(git pull 自动更新)
/var/log/nginx/              access.log / error.log
/etc/letsencrypt/live/<域>/  certbot 申请的证书
```

**include 推荐用通配符**,不要硬编码具体文件名:

```nginx
# ❌ 硬编码: 删文件后 nginx -t 直接 emerg
include /etc/nginx/sites-enabled/api.cocoai.chat;

# ✅ 通配符: 目录里有几个就 include 几个
include /etc/nginx/conf.d/*.conf;
include /etc/nginx/sites-enabled/*;
```

---

## 2 · 完整 server block 模板

支持:主站静态 + www 301 + api 反代 + HTTPS。

```nginx
# ═════════ 80 → 443 (全家桶) ═════════
server {
    listen 80;
    listen [::]:80;
    server_name cocoai.chat www.cocoai.chat api.cocoai.chat;
    return 301 https://$host$request_uri;
}

# ═════════ 主站静态 ═════════
server {
    listen 443 ssl http2;          # http2 只在第一个 443 server 声明一次
    listen [::]:443 ssl http2;
    server_name cocoai.chat;

    ssl_certificate     /home/ubuntu/ssl/cocoai.chat_bundle.crt;
    ssl_certificate_key /home/ubuntu/ssl/cocoai.chat.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root  /home/ubuntu/coco/apps/web;
    index index.html;

    location ^~ /design-preview/ { return 404; }  # 屏蔽原型目录
    location / { try_files $uri $uri/ =404; }

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/javascript image/svg+xml application/xml+rss;

    location ~* \.(png|jpg|jpeg|ico|woff2?|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    location ~* \.(html|css)$ { expires 10m; }
    location ~ /\. { deny all; }
}

# ═════════ www → 主域名 ═════════
server {
    listen 443 ssl;                # 注意这里没有 http2,否则 redefined warn
    listen [::]:443 ssl;
    server_name www.cocoai.chat;

    ssl_certificate     /home/ubuntu/ssl/www.cocoai.chat_bundle.crt;
    ssl_certificate_key /home/ubuntu/ssl/www.cocoai.chat.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    return 301 https://cocoai.chat$request_uri;
}

# ═════════ API 反代 → FastAPI ═════════
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name api.cocoai.chat;

    ssl_certificate     /home/ubuntu/ssl/api.cocoai.chat_bundle.crt;
    ssl_certificate_key /home/ubuntu/ssl/api.cocoai.chat.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 30s;
        proxy_send_timeout    120s;
        proxy_read_timeout    120s;
    }
}
```

---

## 3 · 常用命令

| 动作 | 命令 |
|---|---|
| 语法检查 | `sudo nginx -t` |
| **重载(改配置后用,不断线)** | `sudo systemctl reload nginx` |
| 重启(断一瞬) | `sudo systemctl restart nginx` |
| 启动 / 停止 | `sudo systemctl start/stop nginx` |
| 开机自启 | `sudo systemctl enable nginx` |
| dump 全部已加载配置(含 include) | `sudo nginx -T` |
| 查监听端口 | `sudo ss -tlnp \| grep nginx` |
| 看版本 | `nginx -v` |

**标准改配流程**: `sudo nginx -t && sudo systemctl reload nginx` —— 语法错误不会重载,保证不把现跑的站搞崩。

---

## 4 · 目录权限(坑最多)

Linux 目录的 `x`(执行位)= "允许进入/遍历"。Nginx 跑在 `www-data`,它**不在 `ubuntu` 组**,要访问 `/home/ubuntu/coco/apps/web/` 必须每一级父目录都给 other 加 `x`:

```bash
# 给进入目录的权限
sudo chmod o+x /home /home/ubuntu

# 递归加读权限(o+rX 只给目录加 x,文件只加 r,不会误把文件标成可执行)
sudo chmod -R o+rX /home/ubuntu/coco/apps/web
```

验证 `www-data` 真读得到:
```bash
sudo -u www-data cat /home/ubuntu/coco/apps/web/index.html | head -3
```

**典型症状**: 浏览器 403/404,error.log 里是 `stat() "/home/xxx/" failed (13: Permission denied)`。

---

## 5 · SSL 证书

### 方案对比

| 方案 | 有效期 | 自动续期 | 多域名 |
|---|---|---|---|
| **certbot + Let's Encrypt** | 90 天 | ✅ systemd timer 自动 | ✅ `-d a.com -d b.com` 一张搞定 |
| **腾讯云免费证书(TrustAsia DV)** | 1 年 | ❌ 手动重签 | ❌ 单域名,多域名要分别申请 |

### certbot 自动化

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d cocoai.chat -d www.cocoai.chat \
  --email hinson0@qq.com --agree-tos --redirect -n
```

- 自动改你的 nginx conf(加 443 server、加 80→443 跳转、改 ssl_certificate 路径)
- 证书签发到 `/etc/letsencrypt/live/<域>/fullchain.pem`
- `systemctl status certbot.timer` 确认自动续期已开

### 腾讯云流程

1. 控制台 → SSL 证书 → 免费证书申请(TrustAsia DV)
2. 每个域名单独申请(`cocoai.chat`、`www.cocoai.chat` 各一张)
3. DNS 验证: 腾讯云自动在 DNSPod 加 `_dnsauth` TXT 记录(**续签要保留,别删**)
4. 签发后下载 Nginx 格式,得到 `*_bundle.crt` + `.key`
5. `scp` 到服务器 → `chmod 600 *.key` → 改 ssl_certificate 路径 → reload

### 验证证书域名

```bash
echo | openssl s_client -servername cocoai.chat -connect cocoai.chat:443 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName
# 期望 subject=CN=cocoai.chat  SAN: DNS:cocoai.chat
```

---

## 6 · DNS 解析(DNSPod)

```
*    A    119.45.41.158    ← 泛解析,匹配所有子域名
@    A    119.45.41.158    ← 根域名 cocoai.chat
api  A    119.45.41.158    ← 精确优先于泛
_dnsauth          TXT ...  ← SSL 验证记录,保留
_dnsauth.api      TXT ...  ← SSL 验证记录,保留
```

**优先级**: 精确 > 泛。`api.cocoai.chat` 走 `api`,`xxx.cocoai.chat` 走 `*`,`cocoai.chat` 走 `@`。

**不需要单独加 www A 记录**——已被 `*` 覆盖。除非想精确控制或禁掉其他子域名,那就删 `*` 只留精确记录。

验证:
```bash
dig cocoai.chat +short        # 119.45.41.158
dig www.cocoai.chat +short    # 119.45.41.158
dig api.cocoai.chat +short    # 119.45.41.158
```

---

## 7 · 常见坑速查

| 症状 | 根因 | 修法 |
|---|---|---|
| `protocol options redefined for 0.0.0.0:443` | 多个 server 在 443 重复声明 `http2` | `http2` 只在**一个** 443 server 的 listen 里写,其他写 `listen 443 ssl;` |
| `open() "/etc/nginx/sites-enabled/xxx" failed (2: No such file)` | 删了文件但 nginx.conf 硬编码了该路径 | 改成通配符 `include sites-enabled/*;` |
| `ERR_CERT_COMMON_NAME_INVALID` 浏览器红锁 | 证书 CN/SAN 和访问的 host 不匹配 | 每个域名配自己的证书(腾讯云),或用 certbot 一张覆盖多域名 |
| 403 / 404 首页访问不了 | `www-data` 进不了 `/home/ubuntu/` | `chmod o+x` 一路开权限(见第 4 节) |
| 502 Bad Gateway(反代) | 后端没跑 / 端口不对 | `ss -tlnp \| grep :8000`,对上 `proxy_pass` 端口 |
| 拍照上传 413 | `client_max_body_size` 默认 1m | `client_max_body_size 20m;` |
| 长请求 504 | ASR/OCR 超时 | `proxy_read_timeout 120s;` |

---

## 8 · 日志与排错

```bash
# 实时看错误(配置错、权限、后端挂都在这)
sudo tail -f /var/log/nginx/error.log

# 实时看访问日志
sudo tail -f /var/log/nginx/access.log

# 本地回环测(不经过 DNS)
curl -k -I https://127.0.0.1 -H "Host: cocoai.chat"

# 指定 host 模拟外网访问
curl -I https://cocoai.chat  # 注意 DNS 要生效
```

---

## 9 · 部署更新流程

**静态文件改动**(无需 reload):
```bash
# 本地
git add apps/web && git commit -m "chore(web): 改文案" && git push

# 服务器
cd ~/coco && git pull
```

**Nginx 配置改动**(必须 reload):
```bash
sudo vim /etc/nginx/conf.d/cocoai.chat.conf
sudo nginx -t && sudo systemctl reload nginx
```

**证书续签**(腾讯云 1 年一次):
```bash
# 控制台重新申请 → 下载 → scp 覆盖 → chmod 600 → reload
scp new_bundle.crt new.key ubuntu@<IP>:~/ssl/
ssh ubuntu@<IP> "chmod 600 ~/ssl/*.key && sudo systemctl reload nginx"
```

---

## 10 · 备案提醒

国内 IP + 绑域名访问必须备案已**接入**到当前服务商。CVM 的默认放行可能让你误以为"能访问",但实际上腾讯云会在绑域名时校验备案号,没备案接入会被强制拦截。

- 跨服务商的备案: 腾讯云控制台 → 备案 → 接入备案(免费,审核 1-3 天)
- 国内公网 IP 不走备案就只能用 IP 访问,域名必须备案
