# Android 真机调试 & 投屏

## 安装 adb + scrcpy

```bash
# scrcpy（投屏工具）
brew install scrcpy

# adb（Android 调试桥）— Homebrew cask 可能校验和过期，手动安装更稳
curl -L -o /tmp/platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
unzip -o /tmp/platform-tools.zip -d /usr/local/

# 加入 PATH
echo 'export PATH="/usr/local/platform-tools:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## 小米手机开启 USB 调试

1. 设置 → 我的设备 → 全部参数与信息 → 连续点击 **MIUI 版本** 7 次 → 提示「已开启开发者模式」
2. 返回设置 → 更多设置 → 开发者选项 → 开启：
   - **USB 调试** ✅
   - **USB 调试（安全设置）** ✅ ← 小米特有，必须开，否则 scrcpy 无法操控

## 连接 & 投屏

```bash
# USB 线连接后（手机上弹授权框，点允许）
adb devices          # 确认设备已识别
scrcpy --no-audio    # 投屏到 Mac
```

## 截图流程

投屏窗口出现后，Mac 上 `Cmd+Shift+4` 截取投屏窗口，直接粘贴到 Claude Code 对话中。
