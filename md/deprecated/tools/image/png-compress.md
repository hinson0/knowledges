# PNG 压缩优化（pngquant）

官网 cocoai.chat 上线前把 5 张截图从 ~3.1MB 压到 ~480KB(6× 缩减),首屏加载明显变快。记录命令与对照。

---

## 工具:pngquant

基于**有损色彩量化**——把 24-bit PNG 转成 8-bit 调色板 PNG。视觉上几乎无感,体积缩减 60%~85%。

### 安装

```bash
# macOS
brew install pngquant

# Ubuntu / Debian
sudo apt install pngquant

# 验证
pngquant --version
```

---

## 常用命令

### 单张压缩(就地覆盖)

```bash
pngquant --quality=70-85 --ext .png --force input.png
```

关键参数:
- `--quality=MIN-MAX` 质量范围(推荐 `70-85`,通用无感)
- `--ext .png` 输出扩展名,默认 `-or8.png`; 写 `.png` 表示覆盖原文件
- `--force` 强制覆盖

### 批量压缩(当前目录所有 png)

```bash
pngquant --quality=70-85 --ext .png --force *.png
```

### 跳过压得更大的结果

```bash
pngquant --quality=70-85 --skip-if-larger --ext .png --force *.png
```

当"压缩后比原来还大"时跳过不写入——小图标、已经是调色板格式的图常见此情况。

### 递归整个目录

```bash
find . -name "*.png" -exec pngquant --quality=70-85 --ext .png --force {} \;
```

---

## 本次实测(CoCo 官网 assets)

```bash
cd apps/web/assets
pngquant --quality=70-85 --ext .png --force *.png
```

| 文件 | 压缩前 | 压缩后 | 比例 |
|---|---|---|---|
| bills.png | 850 KB | 151 KB | 18% |
| chat.png | 763 KB | 128 KB | 17% |
| logo.png | 16 KB | 3 KB | 19% |
| profile.png | 686 KB | 103 KB | 15% |
| stats.png | 634 KB | 94 KB | 15% |
| **合计** | **2.9 MB** | **480 KB** | **16%** |

视觉完全无感,应用截图色彩单纯,压缩前后几乎不可分辨。

---

## 质量参数对照

| `--quality` | 视觉效果 | 适用场景 |
|---|---|---|
| `50-70` | 轻微偏色、色块可见 | 缩略图、占位图 |
| `70-85` | **几乎无感** | **通用推荐** |
| `85-95` | 无法分辨 | 人像 / 渐变背景等高要求 |
| `95-100` | 接近无损 | 没多少意义,不如原图 |

> 范围写法 `70-85` 的含义:pngquant 先以最高质量 85 尝试,若最终文件体积能再小一档但质量不低于 70,就选那个——自动权衡。

---

## 其他工具对比

| 工具 | 类型 | 特点 |
|---|---|---|
| **pngquant** | CLI · 有损 | 批量友好、压缩比高(本文主角) |
| [TinyPNG](https://tinypng.com) | 在线 · 有损 | 拖拽即用,免费额度 500KB/每月 |
| **ImageOptim** (macOS) | GUI · 多引擎 | 拖入即压、默认多算法串联 |
| [Squoosh](https://squoosh.app) | 在线 · 多格式 | 可对比参数、支持 WebP/AVIF |
| **oxipng** | CLI · **无损** | 只做无损压缩,比例 10%~30%,可与 pngquant 串联 |

**终极组合**:先 `pngquant`(有损色彩量化) → 再 `oxipng -o4`(无损再优化),总体可比单用 pngquant 多挤 5~10%。

```bash
pngquant --quality=70-85 --ext .png --force *.png
oxipng -o4 --strip all *.png
```

---

## 注意事项

1. **先备份或走 git**:pngquant 是**有损**压缩,原图找不回来。本项目靠 git 存档。
2. **图标/单色 png 效果有限**:色彩本就少,量化空间不大。
3. **压前 `du -sh *` 记录一下基线**,压完对比更直观。
4. **不会影响 `<img>` 用法**:输出仍是标准 PNG,任何浏览器/App 都能读。

---

## 现代替代:WebP / AVIF

2026 年浏览器对 WebP/AVIF 已全面支持,体积比 PNG 小 25%~55%:

```bash
# WebP (比 PNG 小 25%~35%)
cwebp -q 80 input.png -o output.webp

# AVIF (比 WebP 再小 20%)
avifenc --min 30 --max 40 input.png output.avif
```

但 `<img>` 要用 `<picture>` + `<source type="image/webp">` 做回退较麻烦,**对简单站点 pngquant 后的 PNG 已经够用**。有大流量或移动端性能要求再考虑换格式。
