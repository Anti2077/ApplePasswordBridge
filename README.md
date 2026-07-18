# 密码桥（Apple Password Bridge）

一个 macOS 菜单栏工具。当 Apple“密码”显示浏览器扩展授权验证码时，工具会激活符合应用规则的 iCloud 密码扩展授权窗口并填入六位码。

## 系统要求

- macOS 14 或更高版本
- Xcode 15.3 或更高版本（Swift 5.10）
- Apple 的 iCloud 密码浏览器扩展

## 安装

从 [GitHub Releases](https://github.com/Anti2077/ApplePasswordBridge/releases) 下载 DMG，把“Password Bridge”拖入“Applications”。当前下载版本使用临时签名，首次启动时请在 Finder 中右键点击应用并选择“打开”。

也可以克隆仓库后从源码构建：

```sh
make app
mkdir -p /Applications
cp -R "dist/Password Bridge.app" /Applications/
open "/Applications/Password Bridge.app"
```

## 使用

首次运行后，从菜单栏钥匙图标中授予：

- 辅助功能：观察授权窗口，并向 Firefox 输入验证码。
- 屏幕录制：仅当辅助功能无法读取验证码时，截取 Apple“密码”的单个授权窗口进行本地 OCR。

自动识别失败时，按 `Control+Option+Command+P`，或点击菜单中的“立即填入”。菜单提供三档按键速度：兼容 140ms、稳健 80ms、极速 40ms。

应用规则支持两种模式：

- 白名单：仅扫描列表中的应用，首次运行默认包含 Firefox。
- 黑名单：扫描最靠前的普通应用，但排除列表中的应用。

Firefox 已完成端到端验证；其他浏览器需使用能显示 iCloud 密码六格授权窗口的 Apple 扩展。

## 安全边界

- 验证码来源限定为 Apple“密码”或 Apple 密码扩展助手窗口，并要求同一窗口同时命中自动填充授权文案和六位码。
- 填入目标必须符合应用规则，并同时匹配 iCloud 密码标题、浏览器扩展 URL 和六格输入框。
- 验证码只在内存中保留 45 秒，不写入日志、磁盘或剪贴板。
- OCR 使用 macOS Vision 在本机完成，不进行网络请求。

## 开发

```sh
make test
make app
make dmg
```

项目使用 Swift Package Manager，没有第三方依赖。提交和拉取请求会通过 GitHub Actions 自动运行测试。

DMG 发布、Developer ID 签名和 Apple 公证流程见 [发布文档](docs/RELEASING.md)。

## 开源许可

本项目采用 [MIT License](LICENSE) 开源。

“Apple”、“iCloud”和“macOS”是 Apple Inc. 的商标。本项目为独立开源项目，与 Apple Inc. 无隶属、认可或赞助关系。
