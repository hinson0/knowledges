# docker exec -it 进入 MySQL 容器命令逐部分拆解

> 来源:`fastapi_web/src/learning_demo/1455.md`(2026-05-11 流水笔记)

## 命令原文

```bash
docker exec -it mysql-demo mysql -uroot -proot123
```

用来进入一个正在运行的 MySQL 容器并打开 MySQL 命令行客户端。

## 逐部分拆解

### `docker exec`

在一个**已经运行**的容器内执行命令(区别于 `docker run`,后者是启动新容器)。

### `-it`

两个参数的组合:

- `-i`(interactive):保持标准输入打开,这样你能输入指令
- `-t`(tty):分配一个伪终端,让界面有正常的交互体验(光标、回显等)

进入交互式命令行几乎都要带 `-it`。

### `mysql-demo`

容器的名字(或 ID)。这个容器需要事先存在并处于运行状态,可以用 `docker ps` 查看。

### `mysql -uroot -proot123`

这部分是在容器**内部**执行的命令,启动 MySQL 客户端:

- `mysql`:MySQL 自带的命令行客户端
- `-uroot`:以用户 `root` 登录(`-u` 和用户名之间可以没有空格)
- `-proot123`:密码是 `root123`(注意 `-p` 和密码之间**不能有空格**,否则 `root123` 会被当成要连接的数据库名)

## 整体效果

进入 `mysql-demo` 这个容器,以 root 身份(密码 root123)登录 MySQL,进入 `mysql>` 提示符,之后就可以执行 SQL 语句了。

## 坑/Why

**Why:** 在命令行直接写明文密码有两个问题:

1. 会留在 shell 历史记录里
2. MySQL 启动时会警告 `Using a password on the command line interface can be insecure`

**How to apply:** 更安全的写法是只写 `-p`,回车后再交互式输入密码:

```bash
docker exec -it mysql-demo mysql -uroot -p
# Enter password: ******
```

## 关联

- `pg-mvcc-experiment.md` — 同类容器命令用于 psql / pageinspect 扩展安装
