下面是一份本地打包速查（不走 EAS 云），全部在 apps/mobile/ 下执行。

0. 前置一次性

cd /Users/a114514/coco/apps/mobile
pnpm install # 装 JS 依赖
npx expo prebuild # 首次 / 原生配置变更时，生成 ios/ android/
npx expo prebuild --platform android --clean # 这个是清空之前的

## 还有一个同样的清除命令:

加上 --clean 参数（如 npx expo prebuild --clean）意味着完全删除现有的 ios/ 和 android/ 目录，
然后从零开始重新生成。这能确保获得一个与当前配置完全一致的、干净的原生项目，常用于解决一些棘手的构建问题。
但请注意，这会覆盖掉你手动在 ios/ 和 android/ 目录里做的任何修改。

1. Android 本地打 release 并装到真机

# 连一台真机（开启 USB 调试）后：

npx expo run:android --variant release --device

# 只产物、不自动装：

cd android && ./gradlew assembleRelease

# 产物: android/app/build/outputs/apk/release/app-release.apk

adb install -r android/app/build/outputs/apk/release/app-release.apk

生成 aab（上架用）：

cd android && ./gradlew bundleRelease

# 产物: android/app/build/outputs/bundle/release/app-release.aab

2. iOS 本地打 release（需要 Mac + Xcode）

npx expo run:ios --configuration Release --device # 真机
npx expo run:ios --configuration Release # 模拟器

# Xcode 手动归档（上架/ad-hoc）: 打开 ios/<project>.xcworkspace → Product → Archive

3. 只导出 JS Bundle（OTA、调试、校验环境变量内联结果）

npx expo export # 默认：web + 通用 JS
npx expo export -p android # 仅 Android bundle
npx expo export -p ios # 仅 iOS bundle

# 产物在 dist/

校验 .env 是否真被打进 bundle：

npx expo export -p android
grep -oE "api\.cocoai\.chat|119\.45\.41\.158" dist/\_expo/static/js/android/_.hbc 2>/dev/null \
 || grep -oE "api\.cocoai\.chat|119\.45\.41\.158" dist/\_expo/static/js/android/_.js

4. 常见清理（打包异常时）

# JS / Metro 缓存

pnpm start --clear # Metro
rm -rf node_modules .expo && pnpm install

# Android

cd android && ./gradlew clean && cd ..

# iOS

cd ios && rm -rf build Pods && pod install && cd ..

# 一步清掉 prebuild 产物重新生成

npx expo prebuild --clean

5. 体检

npx expo-doctor # 检查依赖版本、配置冲突

---

★ Insight ─────────────────────────────────────

- EXPO*PUBLIC*\* 是 构建时 内联的：Metro 在打 bundle 时把 process.env.EXPO_PUBLIC_API_URL 替换成字符串常量 —— 改 .env 必须重打
  bundle 才生效，热重载不行。校验内联结果的那条 grep 就是用来排查"改了 .env 却没生效"这类 bug 的。
- expo run:ios/android = prebuild + 原生编译 + 装机，一条命令搞定，但严格要求本机装 Xcode/Android SDK。云端 EAS build
  的价值就是让你跳过本地原生环境。
- --variant release (Android) 和 --configuration Release (iOS) 才让 **DEV**=false —— 这是你 lib/config.ts 分流 prod/dev URL
  的关键，调试时请务必用这俩 flag 验 prod 链路。
  ─────────────────────────────────────────────────

---

在你给出的这个流程里：

```bash
cd apps/mobile
npx expo prebuild --platform android --clean   # 删除 android 目录后重新生成
cd android
./gradlew clean                                # 清理构建产物
./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
```

**这里的 `./gradlew clean` 实际上是多余的。**  
因为 `npx expo prebuild --clean` 已经把整个 `android/` 文件夹删掉并重新生成，里面根本还没有任何构建产物（`build/` 目录不存在），`clean` 任务也就没什么可清理的，只是空跑一下，不会出错，但也没必要。

---

### ✅ 什么时候**真正需要**执行 `./gradlew clean`？

`./gradlew clean` 的作用是删除项目里的 `build/` 目录（`app/build/` 等），清除所有编译生成的 `.class`、`.dex`、资源合并缓存、APK 等。**下次构建会完全从头编译**。

通常遇到下面这些情况时，才需要手动 clean：

| 场景                                                       | 为什么需要 clean                                                   |
| ---------------------------------------------------------- | ------------------------------------------------------------------ |
| **切换构建变体 / 签名配置后出现奇怪错误**                  | 比如从 debug 切到 release，资源、混淆缓存可能冲突                  |
| **升级或降级了原生依赖**（如 react-native 版本、Expo SDK） | 旧 ABI 或编译缓存可能导致链接错误、缺少符号                        |
| **修改了原生代码但增量编译没生效**                         | 改动了 `MainApplication.java`、`MainActivity` 等，但 AS 没重新编译 |
| **出现无法解释的构建失败**                                 | 比如 `Duplicate class`、资源合并冲突、`D8/R8` 报错等               |
| **正式发布前想要一个绝对干净的构建**                       | 确保产出完全由当前源码生成，不留任何旧缓存                         |

---

### 🧹 它和 `expo prebuild --clean` 的区别

| 命令                        | 清理了什么                                                                                                             |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `npx expo prebuild --clean` | 删除**整个 `android/` 和 `ios/` 目录**，然后根据 `app.json` + 插件重新生成原生工程文件。这是 JavaScript 层面的“重置”。 |
| `./gradlew clean`           | 只清除 Android 工程的 **构建缓存（`build/`）**，不动任何源码、配置。                                                   |

简单说：

- **prebuild --clean = 重新生成原生壳工程**
- **gradlew clean = 把已经编译出来的东西删掉**

---

### ⚠️ 什么时候**不需要**执行

- 刚刚跑完 `expo prebuild --clean`（像你那样）
- `android/` 目录是全新的，还没构建过
- 日常小改动，增量编译完全正常

在这些情况下强行 `clean` 只会白白增加下一次构建的耗时（因为要重新编译所有代码和资源）。

---

### 🚀 针对你的流程，可以更清爽地写成

```bash
cd apps/mobile
npx expo prebuild --platform android --clean
cd android
# ./gradlew clean   <-- 可以省掉
./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
```

这样就够了。只有在构建报错、或你怀疑缓存有问题时，再补上 `./gradlew clean` 然后重新构建即可。
