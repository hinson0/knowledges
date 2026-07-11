# 删除老旧的pnpm

## 步骤

- `which pnpm` 确定是在哪里.
- `realpath {上面输出的路径}` 我是npm安装的
- `npm uninstall -g pnpm` 卸载
- `hash -r` 刷新
- `which -a pnpm` 再次确认
- `pnpm --version` 确认版本号

---

# macOS 多版本 pnpm、PATH 与 Store 冲突排查指南

## 1. 问题现象

执行安装命令：

```bash
pnpm add -D drizzle-kit typescript @types/node @types/pg tsx oxlint vitest
```

出现错误：

```text
ERR_PNPM_UNEXPECTED_STORE Unexpected store location

The dependencies at ".../node_modules" are currently linked from the store at:
~/Library/pnpm/store/v11
```

同时检查版本：

```bash
which pnpm
pnpm -v

which pn
pn -v
```

得到：

```text
/opt/homebrew/bin/pnpm
pnpm 版本：10.33.0

~/Library/pnpm/pn
pn 版本：11.11.0
```

这说明电脑中存在多个 pnpm 命令入口，并且当前执行的 `pnpm` 不是预期的新版本。

---

## 2. 核心概念

### 2.1 `which pnpm`

```bash
which pnpm
```

用于查看当前终端实际会执行哪个 `pnpm`：

```text
/opt/homebrew/bin/pnpm
```

系统会按照 `PATH` 从左到右查找命令，找到第一个后立即使用。

---

### 2.2 `which -a pnpm`

```bash
which -a pnpm
```

用于列出 `PATH` 中能够找到的所有 `pnpm`：

```text
/Users/a114514/Library/pnpm/pnpm
/opt/homebrew/bin/pnpm
```

区别是：

```bash
which pnpm
```

只显示优先执行的第一个。

```bash
which -a pnpm
```

显示全部候选命令。

---

### 2.3 `PATH`

查看当前 PATH：

```bash
echo $PATH
```

假设输出顺序如下：

```text
/opt/homebrew/bin:/Users/a114514/Library/pnpm:...
```

那么 `/opt/homebrew/bin` 排在前面，系统会优先执行：

```text
/opt/homebrew/bin/pnpm
```

如果希望优先使用 `~/Library/pnpm`，应将它放到 PATH 前面：

```bash
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"
```

注意必须是：

```bash
"$PNPM_HOME:$PATH"
```

不能写成：

```bash
"$PATH:$PNPM_HOME"
```

---

## 3. 判断 pnpm 是怎么安装的

### 3.1 检查命令是否为符号链接

```bash
ls -l /opt/homebrew/bin/pnpm
```

或者：

```bash
readlink /opt/homebrew/bin/pnpm
```

示例输出：

```text
../lib/node_modules/pnpm/bin/pnpm.cjs
```

完整目标相当于：

```text
/opt/homebrew/lib/node_modules/pnpm/bin/pnpm.cjs
```

这通常表示该 pnpm 位于 npm 的全局模块目录中，不一定由 Homebrew 的 keg 管理。

---

### 3.2 为什么 `brew uninstall pnpm` 会失败

执行：

```bash
brew uninstall pnpm
```

如果出现：

```text
Error: No such keg: /opt/homebrew/Cellar/pnpm
```

说明 Homebrew 的 Cellar 中没有 pnpm 软件包。

虽然命令位于：

```text
/opt/homebrew/bin/pnpm
```

但这不代表一定是通过：

```bash
brew install pnpm
```

安装的。

`/opt/homebrew/bin` 也可能存放 npm 全局安装创建的符号链接。

---

### 3.3 检查是否由 npm 全局安装

```bash
npm prefix -g
npm ls -g --depth=0 pnpm
```

如果能够看到 pnpm，可以使用：

```bash
npm uninstall -g pnpm
```

卸载旧版本。

卸载后刷新 shell 命令缓存：

```bash
hash -r
```

然后重新检查：

```bash
which -a pnpm
pnpm -v
```

---

## 4. 推荐解决方案

目标是让：

```bash
pnpm
```

指向：

```text
~/Library/pnpm/pnpm
```

并使用新版本。

### 第一步：确认新版本入口存在

```bash
ls -l ~/Library/pnpm/pnpm
~/Library/pnpm/pnpm -v
```

如果输出预期的新版本，说明新 pnpm 本身没有问题。

---

### 第二步：卸载旧的 npm 全局 pnpm

```bash
npm uninstall -g pnpm
```

然后执行：

```bash
hash -r
```

检查旧入口是否消失：

```bash
which -a pnpm
```

---

### 第三步：设置 `PNPM_HOME`

打开 zsh 配置文件：

```bash
nano ~/.zshrc
```

或者使用 VS Code：

```bash
code ~/.zshrc
```

加入：

```bash
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"
```

保存后重新启动 shell：

```bash
exec zsh
```

也可以临时重新加载：

```bash
source ~/.zshrc
```

---

### 第四步：验证最终结果

```bash
which pnpm
which -a pnpm
pnpm -v
pnpm store path
```

预期：

```text
/Users/a114514/Library/pnpm/pnpm
```

版本应为目标新版本。

---

## 5. 如果旧 pnpm 无法通过 npm 卸载

先确认文件：

```bash
ls -l /opt/homebrew/bin/pnpm
ls -ld /opt/homebrew/lib/node_modules/pnpm
```

只有确认它们确实是废弃的旧 pnpm 后，才手动删除：

```bash
rm /opt/homebrew/bin/pnpm
rm -rf /opt/homebrew/lib/node_modules/pnpm
```

如果权限不足：

```bash
sudo rm /opt/homebrew/bin/pnpm
sudo rm -rf /opt/homebrew/lib/node_modules/pnpm
```

然后：

```bash
hash -r
exec zsh
```

再次验证：

```bash
which pnpm
pnpm -v
```

手动删除应作为最后方案，优先使用对应的包管理器卸载。

---

## 6. 为什么切换 pnpm 后会出现 Store 错误

pnpm 不会像普通 npm 一样，在每个项目中完整复制全部依赖。

它会把依赖保存在统一 Store 中，然后将项目的：

```text
node_modules
```

链接到 Store。

例如，当前项目原来的 `node_modules` 可能关联到：

```text
~/Library/pnpm/store/v11
```

切换 pnpm 安装方式、版本或 Store 配置后，当前 pnpm 可能准备使用另一个 Store，于是出现：

```text
ERR_PNPM_UNEXPECTED_STORE
```

本质是：

```text
现有 node_modules 使用的 Store
≠
当前 pnpm 准备使用的 Store
```

---

## 7. 修复项目中的 Store 冲突

先确认当前 pnpm 已经是正确版本：

```bash
which pnpm
pnpm -v
pnpm store path
```

然后进入项目根目录，而不是某个子应用目录：

```bash
cd /Users/a114514/Documents/openspec
```

先尝试：

```bash
pnpm install
```

如果仍然出现 Store 冲突，重建 `node_modules`：

```bash
rm -rf node_modules
pnpm install
```

Monorepo 中还应检查子目录是否存在单独的 `node_modules`：

```bash
find . -name node_modules -type d -prune
```

通常只需要删除项目根目录的 `node_modules`。如果子项目曾被单独安装过，可能也需要清理对应目录。

一般不要删除：

```text
pnpm-lock.yaml
```

锁文件用于保持依赖版本一致，与 Store 链接冲突不是一回事。

---

## 8. 重新安装开发依赖

Store 修复后：

```bash
pnpm add -D drizzle-kit typescript @types/node @types/pg tsx oxlint vitest
```

其中：

```bash
-D
```

等价于：

```bash
--save-dev
```

依赖会写入：

```json
{
  "devDependencies": {}
}
```

---

## 9. 推荐的完整排查顺序

以后遇到 pnpm 版本异常，可以依次执行：

```bash
which pnpm
which -a pnpm
pnpm -v

type -a pnpm

ls -l "$(which pnpm)"
readlink "$(which pnpm)"

echo "$PATH"

npm prefix -g
npm ls -g --depth=0 pnpm

pnpm store path
pnpm config get store-dir
```

其中：

### `type -a pnpm`

```bash
type -a pnpm
```

比 `which -a pnpm` 更完整，它还可以发现：

- shell alias
- shell function
- PATH 中的可执行文件

例如：

```text
pnpm is an alias for ...
pnpm is /Users/a114514/Library/pnpm/pnpm
pnpm is /opt/homebrew/bin/pnpm
```

如果 `which pnpm` 的结果和预期不一致，优先使用：

```bash
type -a pnpm
```

检查是否存在 alias 或 shell function。

---

## 10. 临时切换与永久切换

### 临时切换

只对当前终端窗口生效：

```bash
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"
hash -r
```

验证：

```bash
which pnpm
pnpm -v
```

关闭当前终端后失效。

---

### 永久切换

把下面内容写入：

```text
~/.zshrc
```

```bash
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"
```

然后：

```bash
exec zsh
```

---

## 11. 常用命令速查

查看当前使用的 pnpm：

```bash
which pnpm
```

查看所有 pnpm：

```bash
which -a pnpm
```

更完整地查看命令来源：

```bash
type -a pnpm
```

查看版本：

```bash
pnpm -v
```

查看符号链接目标：

```bash
readlink "$(which pnpm)"
```

查看 PATH：

```bash
echo "$PATH"
```

查看 pnpm Store：

```bash
pnpm store path
```

查看是否配置了自定义 Store：

```bash
pnpm config get store-dir
```

刷新 shell 命令缓存：

```bash
hash -r
```

重启当前 zsh：

```bash
exec zsh
```

重新安装项目依赖：

```bash
rm -rf node_modules
pnpm install
```

卸载 npm 全局安装的 pnpm：

```bash
npm uninstall -g pnpm
```

---

## 12. 最终原则

处理多版本 pnpm 时，需要分清四件事：

1. 当前执行的是哪个命令：

```bash
which pnpm
```

2. 系统中还有哪些同名命令：

```bash
which -a pnpm
type -a pnpm
```

3. 命令是由哪个安装方式创建的：

```bash
readlink "$(which pnpm)"
npm ls -g --depth=0 pnpm
brew list pnpm
```

4. 当前项目的 `node_modules` 使用哪个 Store：

```bash
pnpm store path
```

正确处理顺序是：

```text
先统一 pnpm 命令和版本
→ 再确认 Store 路径
→ 最后重建项目 node_modules
```

不要一看到 `/opt/homebrew/bin` 就直接认定它是 Homebrew 安装的，也不要在 pnpm 命令版本尚未统一时反复重装项目依赖。
:::
