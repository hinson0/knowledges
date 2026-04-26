# Android 明文 HTTP 流量策略

## 核心规则

**Android 9 (API 28) 起，默认禁止所有明文（HTTP）网络流量。** 只允许 HTTPS。

这是 Android 的 Network Security Configuration 安全特性，目的是防止中间人攻击和数据窃听。

## 表现

- app 发起 HTTP 请求时直接失败
- 错误信息：`network request failed`、`CLEARTEXT communication not permitted`、`java.io.IOException: Cleartext HTTP traffic not permitted`
- HTTPS 请求不受影响

## 为什么开发时没问题？

| 环境                  | 行为        | 原因                                                                             |
| --------------------- | ----------- | -------------------------------------------------------------------------------- |
| Expo Go               | HTTP 正常   | Expo Go 自己的 manifest 已开启 `usesCleartextTraffic="true"`（需要连本地 Metro） |
| Android Studio 模拟器 | HTTP 正常   | debug build 默认允许明文                                                         |
| 独立 APK (release)    | HTTP 被拦截 | 使用项目自己的 AndroidManifest，遵循系统默认策略                                 |

## 解决方案

### 方案一：全局允许明文（简单粗暴）

在 `AndroidManifest.xml` 的 `<application>` 标签加属性：

```xml
<application
    android:usesCleartextTraffic="true"
    ... >
```

适用场景：开发阶段、或服务端暂时无法用 HTTPS（如 IP 直连无证书）。

### 方案二：Network Security Config（精确控制，推荐）

1. 创建 `android/app/src/main/res/xml/network_security_config.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- 只对指定域名/IP 允许明文 -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">119.45.41.158</domain>
    </domain-config>
</network-security-config>
```

2. 在 `AndroidManifest.xml` 引用：

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ... >
```

优点：只对特定地址开放 HTTP，其他请求仍强制 HTTPS，更安全。

### 方案三：升级到 HTTPS（最终方案）

配好 HTTPS 后就不需要以上任何配置，Android 默认行为即可。

## 版本历史

| Android 版本       | API Level | 明文 HTTP 默认行为 |
| ------------------ | --------- | ------------------ |
| Android 8.1 及以下 | ≤ 27      | 允许               |
| Android 9          | 28        | **禁止**           |
| Android 10+        | 29+       | 禁止（继承）       |

## Expo / React Native 特别注意

- `expo prebuild` 会重新生成 `AndroidManifest.xml`，手动改动可能被覆盖
- 更持久的做法是通过 Expo config plugin 注入，或在 `app.json` 中配置：

```json
{
  "expo": {
    "android": {
      "usesCleartextTraffic": true
    }
  }
}
```

但注意：prebuild 后仍需确认 manifest 是否正确生成。

## 建议重新 prebuild 一次让两边对齐：

cd apps/mobile && npx expo prebuild --platform android --clean

这样 AndroidManifest.xml 就完全由 app.json 驱动生成，不用担心手动改动丢失的问题。

★ Insight ─────────────────────────────────────
Expo 的 android/ 目录有两种管理方式：

Managed（推荐）： 不提交 android/ 到 git，每次 expo prebuild 自动生成，app.json 是唯一真相源
Bare： 提交 android/ 到 git，手动维护 manifest，但和 app.json 可能脱节（你现在的情况）
你的项目已经把 android/ 提交了（bare workflow），所以两边都要保持一致，或者考虑用 prebuild --clean 重新生成。
─────────────────────────────────────────────────

## 几个命令

```bash
cd apps/mobile
npx expo prebuild --platform android --clean
cd android
./gradlew clean
./gradlew assembleRelease
adb install -r app/build/outputs/apk/release/app-release.apk
```

- ./gradlew clean — 删除所有之前的编译产物（build/ 目录），确保从零开始
- ./gradlew assembleRelease — 重新编译生成 release APK
  合起来就是"先清干净，再从头编译"。

- 这个是在连接usb后直接安装的命令
  adb install -r app/build/outputs/apk/release/app-release.apk
