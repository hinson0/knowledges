# Ubuntu + oh-my-zsh 配置 pnpm 子命令补全

## 触发问题

> 在 Ubuntu + oh-my-zsh 下，让 `pnpm <Tab>` 出现子命令补全。

## 关键结论

- 核心步骤只有三步：生成 pnpm 的 zsh 补全文件、把补全目录加入 `fpath`、清缓存并重启 zsh。
- 补全文件名必须是 `_pnpm`，不要写成 `pnpm` 或 `_pnpm.zsh`。
- `fpath=(~/.zsh/completions $fpath)` 要放在 `source $ZSH/oh-my-zsh.sh` 前面。
- 使用 oh-my-zsh 时，一般不需要手动加 `autoload -Uz compinit` 和 `compinit`，因为 oh-my-zsh 会处理。

## 1. 生成 pnpm 的 zsh 补全文件

```bash
mkdir -p ~/.zsh/completions
pnpm completion zsh > ~/.zsh/completions/_pnpm
```

注意文件名必须是：

```bash
_pnpm
```

不要写成：

```bash
pnpm
_pnpm.zsh
```

## 2. 修改 ~/.zshrc

打开：

```bash
nano ~/.zshrc
```

找到：

```bash
source $ZSH/oh-my-zsh.sh
```

在它前面加：

```bash
fpath=(~/.zsh/completions $fpath)
```

最终大概是：

```bash
export ZSH="$HOME/.oh-my-zsh"

fpath=(~/.zsh/completions $fpath)

plugins=(git node npm)

source $ZSH/oh-my-zsh.sh
```

## 3. 清缓存并重启 zsh

```bash
rm -f ~/.zcompdump*
exec zsh
```

然后测试：

```bash
pnpm <Tab>
```

## 检查命令

确认补全文件存在：

```bash
ls -l ~/.zsh/completions/_pnpm
```

确认补全目录进入了 `fpath`：

```bash
print -l $fpath | grep completions
```

## 一句话版

```bash
mkdir -p ~/.zsh/completions
pnpm completion zsh > ~/.zsh/completions/_pnpm
# 然后在 source $ZSH/oh-my-zsh.sh 前加：
# fpath=(~/.zsh/completions $fpath)
rm -f ~/.zcompdump*
exec zsh
```
