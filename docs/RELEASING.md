# 签名、公证与 DMG 发布

## 三种状态

| 状态 | 下载后的体验 | 需要什么 |
| --- | --- | --- |
| 临时签名（ad-hoc） | 需要在 Finder 中右键“打开” | 免费，可直接构建 |
| Developer ID 签名 | 能识别开发者，但仍可能被 Gatekeeper 拦截 | Apple Developer Program |
| Developer ID 签名并公证 | 正常双击安装，推荐公开发布 | Apple Developer Program 和 Apple 公证 |

## 1. 获取 Developer ID 证书

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/)；个人账号也可以。
2. 打开 Xcode，进入 Settings > Accounts，登录开发者账号。
3. 选择账号和 Team，点击 Manage Certificates。
4. 点击 `+`，选择 `Developer ID Application`。
5. 用下面的命令确认钥匙串已经安装证书：

```sh
security find-identity -v -p codesigning
```

输出中应出现类似：

```text
Developer ID Application: Your Name (TEAMID)
```

证书和私钥只保存在钥匙串中，不要提交到 Git 仓库。

## 2. 配置 Apple 公证

在 [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) 创建 API Key，记下 Issuer ID 和 Key ID，并下载一次性的 `.p8` 文件。然后存入钥匙串：

```sh
xcrun notarytool store-credentials "password-bridge-notary" \
  --key "/path/to/AuthKey_KEYID.p8" \
  --key-id "KEYID" \
  --issuer "ISSUER_ID"
```

`.p8` 文件是秘密凭据，不要提交到仓库或发给其他人。

## 3. 生成正式 DMG

将证书名称替换为钥匙串中显示的完整名称：

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="password-bridge-notary" \
make dmg
```

脚本会依次构建 Apple Silicon 和 Intel 版本、合并为通用 App、启用 hardened runtime 签名、创建 DMG、提交 Apple 公证，并把公证票据装订到 DMG。

发布前验证：

```sh
hdiutil verify "dist/Password Bridge-1.0.0-universal.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "dist/Password Bridge-1.0.0-universal.dmg"
```

## 4. 发布到 GitHub Releases

确认版本号与 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 一致，再运行：

```sh
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 \
  "dist/Password Bridge-1.0.0-universal.dmg" \
  --title "Password Bridge 1.0.0" \
  --notes-from-tag
```

每个版本号只能使用一次。发布修复版本时先把版本号改为 `1.0.1`，再重新构建、打标签和创建 Release。
