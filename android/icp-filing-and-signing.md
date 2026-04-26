# Android APK 签名与 ICP 备案

## 生成 Release Keystore

```bash
keytool -genkeypair -v \
  -storetype JKS \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -keystore apps/mobile/android/app/release.keystore \
  -alias coco-release
```

> **重要**：密码和 keystore 文件务必妥善保存，丢失后无法更新已上架的 App。

## 获取 ICP 备案所需信息

### App 包名

```bash
grep applicationId android/app/build.gradle
# 输出：com.anonymous.mobile（默认值，需在 app.json 里改）
```

包名在 `app.json` 的 `android.package` 字段配置，格式为域名反写：
- 域名 `cocoai.chat` → 包名 `chat.cocoai.app`

### 公钥

```bash
keytool -exportcert -keystore apps/mobile/android/app/release.keystore -alias coco-release \
  | openssl x509 -inform der -pubkey -noout
```

输出格式（去掉 `-----BEGIN/END PUBLIC KEY-----`，合成一行后粘贴到备案表）：

```
MIIBIjANBgkqhkiG9w0BAQE...IDAQAB
```

### 签名 MD5 值

```bash
keytool -exportcert -keystore apps/mobile/android/app/release.keystore -alias coco-release \
  | openssl dgst -md5 -hex
```

输出 32 位十六进制字符串，如 `8b1c674176cf727820dc39a2bdaa7227`。

## 注意事项

- Expo 默认包名是 `com.anonymous.mobile`，上架前必须在 `app.json` 中修改
- 包名一旦上架就**不能修改**
- `debug.keystore` 仅用于开发，上架必须用 `release.keystore`
- 国内服务器（含腾讯云）的域名必须完成 ICP 备案才能正常解析
- `.chat` 等境外注册的域名同样需要备案（只要服务器在国内）
- 备案周期约 2-4 周
