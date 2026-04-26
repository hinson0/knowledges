# pnpm Workspace 知识点

## 目录结构

pnpm monorepo 典型布局：

```
project-root/
├── pnpm-workspace.yaml    # 声明 workspace 包的位置
├── package.json           # 根级依赖和脚本
├── pnpm-lock.yaml
├── apps/                  # 可独立运行的应用
│   └── mobile/            # 每个 app 有自己的 package.json
├── packages/              # 共享库，被 apps 引用
│   └── shared/
└── supabase/              # 基础设施（不受 pnpm 管理）
```

- **`apps/`** — 可部署的终端应用
- **`packages/`** — 被 apps 引用的内部库，不单独部署

## 混合语言 monorepo

pnpm 本质是 Node.js 包管理器，**不管理 Python 依赖**。Python 后端（用 uv/pip）放在 `apps/` 下只是目录组织，不受 pnpm 管理。

两种常见做法：

1. **放在 `apps/` 内**：目录统一，`apps/backend` 没有 `package.json` 的话 pnpm 会忽略它
2. **平级放置**：把 `backend/` 移到根目录，语义更准确——workspace 里只有 JS/TS 项目

## node_modules 机制

pnpm 的依赖存储是三层结构，和 npm 平铺不同：

1. **全局 store**（`~/Library/pnpm/store/`）— 硬盘上每个包版本只存一份
2. **根 `node_modules/.pnpm/`** — 硬链接到全局 store
3. **各子包 `node_modules/`** — 符号链接到根 `.pnpm/`

好处：多个子包依赖同一个包时，磁盘只存一份。这是 pnpm 比 npm/yarn 省空间的核心原因。

## pnpm install 行为

在根目录执行 `pnpm install` 会一次性安装所有 workspace 子包的依赖：

1. 读 `pnpm-workspace.yaml`，找到所有子包
2. 读每个子包的 `package.json`，收集全部依赖
3. 统一下载到根 `node_modules/.pnpm/`
4. 在每个子包的 `node_modules/` 里创建符号链接

**不需要** cd 进每个子目录单独 install。

## 常用命令

### 依赖管理

```bash
pnpm install                          # 安装所有 workspace 依赖
pnpm add <pkg> -w                     # 给根目录加依赖
pnpm --filter mobile add <pkg>        # 给指定子包加依赖
pnpm --filter mobile remove <pkg>     # 给指定子包删依赖
```

### 运行脚本

```bash
pnpm dev                              # 运行根 package.json 里的 dev 脚本
pnpm --filter mobile dev              # 运行指定子包的脚本
pnpm -r run build                     # 所有子包递归执行 build
```

### 查看信息

```bash
pnpm ls --depth -1 -r                 # 列出 workspace 所有包
pnpm why <pkg>                        # 查看某个依赖被安装的原因
pnpm outdated -r                      # 检查所有包的过期依赖
```

### 清理

```bash
pnpm store prune                      # 清理全局 store 中未引用的包
```

### --filter（最核心）

```bash
pnpm --filter <包名> <命令>            # 对指定包操作
pnpm --filter "mobile..." build       # mobile 及其所有依赖包都 build
pnpm --filter "./apps/*" dev          # 按目录路径匹配
```
