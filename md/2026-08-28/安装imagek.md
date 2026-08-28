复盘下来就是一条很清楚的依赖链：

1. 一开始 `composer install` 失败，因为项目要求：

```text
ext-imagick
```

但本机 PHP 8.5 没装 `imagick` 扩展。

2. `imagick` 不是 ImageMagick 本身：

```text
PHP
 ↓
imagick PHP 扩展
 ↓
ImageMagick 底层图片库
```

所以先装：

```bash
brew install imagemagick
```

再装：

```bash
pecl install imagick
```

3. Homebrew 安装 ImageMagick 时，阿里云镜像缓存异常，出现：

```text
No such file or directory @ rb_sysopen
Bottle missing
```

你当前配置了：

```bash
HOMEBREW_API_DOMAIN=阿里云
HOMEBREW_BOTTLE_DOMAIN=阿里云
```

处理方式是临时取消镜像、清缓存、走官方源。

4. `pecl install imagick` 第一次又失败，原因是：

```text
pkg-config not found
```

`pkg-config` 的作用是：**编译扩展时告诉编译器 ImageMagick 的头文件、库文件在哪里。**

所以补装：

```bash
brew install pkgconf
```

5. 再执行：

```bash
pecl install imagick
```

最终成功：

```text
install ok: imagick-3.8.1
Extension imagick enabled in php.ini
```

现在整条链路是：

```text
ImageMagick       底层图片处理库
    ↑
pkg-config        编译时帮助定位 ImageMagick
    ↑
imagick.so        PHP 扩展
    ↑
PHP 8.5
    ↑
Composer 项目
```

最后验证：

```bash
php -m | grep imagick
php --ri imagick
composer install
```

核心记住一句就行：

> Composer 缺 `ext-imagick` → 安装 ImageMagick 底层库 + PHP imagick 扩展；如果 PECL 编译找不到底层库，再检查 `pkg-config`。
