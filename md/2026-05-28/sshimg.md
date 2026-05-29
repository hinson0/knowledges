# 📌 知识点:如何把本地截图发送到远程 Claude Code

## 背景 / 为什么不能直接粘贴

- 我的运行环境:**本地 Mac(iTerm2)→ SSH → 远程 EC2(别名 `xlarge`)→ tmux → Claude Code**。
- Claude Code 进程跑在 **EC2** 上,只能看见 **EC2 的文件系统**,看不到你 Mac 的剪贴板。
- tmux 配的 OSC 52 剪贴板**只能传文本**,图片字节穿不过这条链路。
- 所以「Ctrl+V 粘贴图片」这条路在远程场景**不可用**,唯一可行的是:**把图变成 EC2 上的文件,再用路径引用**。

## 核心三步

```
本地截图 → 本地敲 sshimg → 把它打印的路径粘进 Claude Code
```

## 一次性准备(已完成)

```bash
# 1) 本地装工具:把剪贴板里的 PNG 落地成文件
brew install pngpaste

# 2) 本地 ~/.zshrc 加入函数(改完 source ~/.zshrc)
sshimg() {
  local name="img-$(date +%Y_%m_%d_%H_%M_%S).png"
  pngpaste "/tmp/$name" || { echo "剪贴板里没有图片,先截图(Ctrl+Shift+Cmd+4 截到剪贴板)"; return 1; }
  scp "/tmp/$name" "xlarge:~/material_turbo/.tmp/$name" && \
  echo "✅ 在 Claude Code 里粘这个路径:  ~/material_turbo/.tmp/$name"
}
```

> EC2 端 `~/material_turbo/.tmp/` 目录已建好,且已加入 `.gitignore`(PR #3),临时图不会被误提交。

## 日常用法

1. **截图到剪贴板**:`Ctrl + Shift + Cmd + 4` 框选(必须带 `Ctrl`,否则会存成桌面文件而非进剪贴板)。
2. **本地终端**敲 `sshimg`。
3. 把它打印的路径(如 `~/material_turbo/.tmp/img-2026_05_28_10_14_39.png`)**粘进 Claude Code 输入框**。

## 关键细节

- 文件名用 `%Y_%m_%d_%H_%M_%S` 可读时间戳,保留到**秒**防止同分钟内覆盖。
- 截图已是文件时,跳过 `sshimg`,直接 `scp ~/Desktop/xxx.png xlarge:~/material_turbo/.tmp/`。
- 我是用**视觉**读像素,所以设计稿、报错截图、网页布局、手绘草图都能看 —— 配合 Atlas 原型移植,贴设计图比文字描述准得多。

---

现在把它存进项目记忆:
