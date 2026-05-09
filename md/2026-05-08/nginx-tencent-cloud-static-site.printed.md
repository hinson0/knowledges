# 腾讯云上新建静态站点的 Nginx 配置流程

> 以 `qiyue.cocoai.chat` 为例,跑通"GitHub → 服务器 → SSL → Nginx 静态站"的全链路。

## 流程概览

1. 仓库推到 GitHub
2. SSH 到腾讯云服务器,把 GitHub 仓库的地址拉到一个文件夹
3. 如需 SSL:腾讯云上申请免费 SSL 证书,下载 Nginx 版本
4. 配置 Nginx 站点 conf:`./xxx.conf`
5. 上传证书到服务器
6. `reload nginx` 起服务

## Nginx 静态站点配置(conf 模板)

```nginx
# ═════════ 主站 (静态) ═════════
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name cocoai.chat;

    ssl_certificate     /home/ubuntu/ssl/cocoai.chat_bundle.crt;
    ssl_certificate_key /home/ubuntu/ssl/cocoai.chat.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root  /home/ubuntu/coco/apps/web;
    index index.html;

    location ^~ /design-preview/ { return 404; }
    location / { try_files $uri $uri/ =404; }

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/javascript image/svg+xml application/xml+rss;

    location ~* \.(png|jpg|jpeg|ico|woff2?|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    location ~* \.(html|css)$ {
        expires 10m;
    }
    location ~ /\. { deny all; }
}
```

新建站点时主要改这几个字段:

- `server_name cocoai.chat;`
- `ssl_certificate     /home/ubuntu/ssl/qiyue.chat_bundle.crt;`
- `ssl_certificate_key /home/ubuntu/ssl/qiyue.chat.key;`
- `root /home/ubuntu/qiyue;`
- `index index.html;`

## 上传 SSL 证书到服务器

`scp` 命令格式:

```sh
scp 本地文件路径 ubuntu@服务器IP:/远程目标路径
```

### 上传证书文件

```sh
scp ~/Downloads/cocoai.chat/Nginx/cocoai.chat_bundle.crt ubuntu@你的服务器IP:/home/ubuntu/ssl/
```

### 上传私钥文件

```sh
scp ~/Downloads/cocoai.chat/Nginx/cocoai.chat.key ubuntu@你的服务器IP:/home/ubuntu/ssl/
```

### 实际操作日志

```sh
# a114514 @ Mac in ~/crt_key/qiyue.cocoai.chat_nginx [12:21:05]
$ scp qiyue.cocoai.chat_bundle.crt qiyue.cocoai.chat.key ubuntu@119.45.41.158:~/ssl/
ubuntu@119.45.41.158's password:
qiyue.cocoai.chat_bundle.crt    100% 4439   130.5KB/s   00:00
qiyue.cocoai.chat.key
```

服务器上 `~/ssl/` 下的样子:

```sh
drwxr-x--x 10 ubuntu ubuntu 4096 May  8 11:54 ../
-rw-rw-r--  1 ubuntu ubuntu 4431 Apr 16 14:44 api.cocoai.chat_bundle.crt
-rw-------  1 ubuntu ubuntu 1700 Apr 16 14:44 api.cocoai.chat.key
-rw-rw-r--  1 ubuntu ubuntu 4447 Apr 22 22:03 cocoai.chat_bundle.crt
-rw-------  1 ubuntu ubuntu 1700 Apr 22 22:03 cocoai.chat.key
-rw-rw-r--  1 ubuntu ubuntu 4439 May  8 12:21 qiyue.cocoai.chat_bundle.crt
-rw-rw-r--  1 ubuntu ubuntu 1700 May  8 12:21 qiyue.cocoai.chat.key
-rw-rw-r--  1 ubuntu ubuntu 4447 Apr 22 22:03 www.cocoai.chat_bundle.crt
```

## 起 Nginx 站点服务

配置改完后必须 reload:

```sh
sudo systemctl reload nginx
```

## 验证

打开 https://qiyue.cocoai.chat/

## 关键经验

- 证书文件命名规则:`<domain>_bundle.crt` + `<domain>.key`
- 私钥权限是 `600`(`-rw-------`),证书是 `664`(`-rw-rw-r--`)
- 改完 conf 一定要 `reload`,不要 `restart`(reload 不断连接,restart 会断)
