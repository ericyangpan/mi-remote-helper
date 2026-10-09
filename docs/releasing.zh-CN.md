# 发布准备

[English](releasing.md) · **简体中文**

## 源码

- 软件采用 GPL-3.0-only，保留 `LICENSE`、`THIRD_PARTY_NOTICES.md`、上游归属与字体许可证。
- 小米照片不属于软件许可范围；中英文 README 与 App 内第三方声明均有版权及删除说明，目前没有可再分发授权记录。
- 公开源码不包含 `Signing.local.xcconfig`、私钥、证书导出文件、公证凭据及本机构建产物。
- 每个二进制版本须标明精确源码版本，在同一发布位置提供对应源码、配置与构建说明，但不包含私有签名密钥。
- 公共构建默认使用 arm64 与临时签名，维护者本地签名覆盖文件不属于源码发布内容。

## 已签名下载包

开发证书与临时签名适用于本地构建。公开下载采用 Developer ID Application 证书、Hardened Runtime 及 Apple 公证。本仓库不提供这类证书或凭据，也不声称已有公证产物。

安装自己的 Developer ID Application 证书后，在独立目录构建，以免影响日常使用版本。将两个占位值替换为自己的姓名和团队 ID：

```sh
xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Distribution \
  CODE_SIGN_STYLE=Manual \
  'CODE_SIGN_IDENTITY=Developer ID Application: YOUR NAME (YOUR_TEAM_ID)' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ENABLE_HARDENED_RUNTIME=YES \
  'OTHER_CODE_SIGN_FLAGS=--timestamp' build

codesign --verify --deep --strict --verbose=2 \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
```

上传前运行 `python3 scripts/check-release-security.py "build/Distribution/Build/Products/Release/Mi Remote Helper.app" --distribution`。[安全策略](security.zh-CN.md)说明了 Release 空 entitlement 白名单及权限边界。

应用的 Release 配置关闭基础权限注入，并启用 Hardened Runtime。公证前，使用 `codesign -d --entitlements - --xml` 和 `codesign -d --verbose=4` 检查签名：`com.apple.security.get-task-allow` 必须不存在或为 false，必须包含 runtime 标志，Developer ID 签名必须包含可信时间戳。严格签名校验本身不会检查这些发行条件。参见 [Apple 公证问题排查](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)。

交互运行 `xcrun notarytool store-credentials`，创建名为 `mi-remote-notary` 的钥匙串配置。不要将密码或 API 私钥放入仓库。提交后确认状态为 Accepted，再执行 stapling 与校验：

```sh
ditto -c -k --keepParent \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app' \
  build/MiRemoteHelper-notarization.zip
xcrun notarytool submit build/MiRemoteHelper-notarization.zip \
  --keychain-profile mi-remote-notary --wait

# Run only after the submission is Accepted.
xcrun stapler staple 'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
xcrun stapler validate 'build/Distribution/Build/Products/Release/Mi Remote Helper.app'
spctl --assess --type execute --verbose=2 \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app'

ditto -c -k --keepParent \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app' \
  build/MiRemoteHelper-arm64.zip
```

上传用 ZIP 不是最终下载包；公证通过并完成 stapling 后需重新打包。使用另一台 Apple Silicon Mac 验证蓝牙、辅助功能、输入监控、登录启动及实际听写。Hardened Runtime 和公证不代表硬件兼容性已验证。

将对应源码压缩包放在最终 App ZIP 的同一发布位置。必须从构建所用的精确已提交版本生成，不使用其他分支或有未公开修改的工作区：

```sh
# Run at the exact committed revision used to build the release.
git archive --format=zip --output=build/MiRemoteHelper-source.zip HEAD
```

参考：[Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[GPL-3.0 第 6 条](https://www.gnu.org/licenses/gpl-3.0.html#section6)。
