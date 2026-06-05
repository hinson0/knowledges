# WSL / Ubuntu 里让 Vim 支持系统剪贴板

## 触发问题

> 在 WSL / Ubuntu 里让 Vim 支持 `+clipboard`，并能把 Vim 内容复制到系统剪贴板。

## 关键结论

- Vim 支持系统剪贴板的核心是：**安装带 `clipboard` 编译选项的 Vim 版本**。
- Ubuntu 默认的 `vim-tiny` 经常是 `-clipboard`，不能直接用系统剪贴板寄存器。
- 最简单修法是安装 `vim-gtk3`。
- 在 WSL 里，即使 Vim 有 `+clipboard`，它的剪贴板也不一定稳定等于 Windows 剪贴板。
- WSL 下更稳的万能方案是直接使用 `clip.exe`，尤其是 Vim 里的 `:w !clip.exe`。

## 检查当前 Vim 是否支持 clipboard

```bash
vim --version | grep clipboard
```

如果看到：

```text
-clipboard
```

说明当前 Vim 不支持系统剪贴板。

## 安装支持 clipboard 的 Vim

```bash
sudo apt update
sudo apt install vim-gtk3
```

装完再检查：

```bash
vim --version | grep clipboard
```

目标是看到：

```text
+clipboard
```

## Vim 内复制到系统剪贴板

复制全部内容到系统剪贴板：

```vim
:%yank +
```

或者：

```vim
ggVG"+y
```

## WSL 下更稳的 clip.exe 方案

在 WSL 里，`+clipboard` 不一定自动等于 Windows 剪贴板。更稳的方式是直接把内容管给 `clip.exe`。

复制文件内容：

```bash
cat ~/.zshrc | clip.exe
```

复制 Codex 配置：

```bash
cat ~/.codex/config.toml | clip.exe
```

在 Vim 里把当前 buffer 写入 Windows 剪贴板：

```vim
:w !clip.exe
```

这条命令不依赖 Vim 的 `+clipboard`，在 WSL 里很实用。

## 建议

推荐同时做两件事：

```bash
sudo apt install vim-gtk3
```

并记住 WSL 下的万能招：

```vim
:w !clip.exe
```

前者让 Vim 具备 `+clipboard` 能力；后者直接对接 Windows 剪贴板，在 WSL 场景下更稳。
