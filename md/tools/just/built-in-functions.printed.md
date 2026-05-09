# just 内置函数速查

> 所有以 `_directory` 结尾的函数都可以简写成 `_dir`。

## 路径与文件

| 函数名 | 功能描述 |
| :--- | :--- |
| `justfile()` | 获取当前 `justfile` 的绝对路径 |
| `justfile_directory()` | 获取 `justfile` 所在的**目录**路径 |
| `invocation_directory()` | 获取**执行 `just` 命令时所在的目录**路径，该路径在 `just` 运行任务前不会改变 |
| `just_executable()` | 获取 `just` 可执行文件自身的绝对路径 |

## 系统信息

| 函数名 | 功能描述 |
| :--- | :--- |
| `arch()` | 系统指令集架构，如 `x86_64`, `aarch64` |
| `os()` | 操作系统名称，如 `linux`, `macos`, `windows` |
| `os_family()` | 操作系统家族，返回 `unix` 或 `windows`，适合跨平台脚本 |
| `num_cpus()` | 逻辑 CPU 核心数 (v1.15.0+) |

## 环境变量

| 函数名 | 功能描述 |
| :--- | :--- |
| `env_var(key)` | 读取环境变量，不存在则**报错中断** |
| `env_var_or_default(key, default)` | 读取环境变量，不存在则返回**默认值** |

## 字符串操作

| 函数名 | 功能描述 |
| :--- | :--- |
| `lowercase(string)` | 转小写 |
| `uppercase(string)` | 转大写 |
| `trim(string)` | 移除首尾空白 |
| `quote(string)` | 添加引号，使其在 Shell 中安全使用 |
| `replace(string, from, to)` | 字符串替换 |
| `capitalize(string)` | 首字母大写 |
| `kebabcase(string)` | 转 `kebab-case` |
| `camelcase(string)` | 转 `camelCase` |
| `snakecase(string)` | 转 `snake_case` |
| `titlecase(string)` | 每个单词首字母大写 |

## 其他工具

| 函数名 | 功能描述 |
| :--- | :--- |
| `shell(command, args...)` | 执行 Shell 命令并返回标准输出 (v1.27.0+) |
| `sha256(string)` / `sha256_file(path)` | 计算 SHA256 哈希值 |
| `uuid()` | 生成随机 UUID (v4) |
| `path_exists(path)` | 检查路径是否存在 |
| `error(message)` | 抛出错误并终止运行 |

## 备注

- v1.49.0+ 支持实验性的**用户自定义函数**
- 完整列表参考 [官方手册](https://just.systems/man/en/functions.html)
