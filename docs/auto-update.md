# MoliShot 应用内更新

从 0.8.0（build 16）开始，菜单栏和应用菜单提供「检查更新…」。默认每天检查一次；下载、安装和重启由用户确认。Debug 构建不启动更新器。

更新由 Sparkle 2.10.1 处理。更新订阅固定为：

https://github.com/gusibi/MoliShot/releases/latest/download/appcast.xml

每个正式 Release 同时包含 DMG、更新 ZIP 和带 Ed25519 签名的 `appcast.xml`。DMG 用于首次安装，ZIP 用于更新。更新包在解压前校验，订阅文件也必须通过签名验证。

## 签名和首次迁移

这里使用两套独立身份：

- 自签名代码签名证书：让不同版本满足相同的 designated requirement（DR，系统识别应用的身份要求）。发布证书指纹固定在 `Resources/update-signing-certificate.sha1`。
- Sparkle Ed25519 密钥：验证更新包和订阅文件来自发布者。公钥固定在 `project.yml` 和 `scripts/package-update.py`。

私钥不属于代码仓库。当前维护机器的签名材料位于：

`~/Library/Application Support/MoliShotSigning/`

目录权限 700，文件权限 600。必须安全备份整个目录。后续版本始终复用它；换电脑时安全恢复，不重新生成。证书与更新密钥任一丢失，都可能需要一次手动迁移。不要让用户自行重签新版本。

已有 ad-hoc 版本没有更新器，且其 DR 绑定旧代码哈希。因此首次迁移到 0.8.0 应预期需要手动安装、系统放行和重新授予屏幕录制/辅助功能权限。之后是否能保留授权，要在实际 macOS 上验证；固定签名身份不等于已经验证 TCC 权限延续。

自签名证书不提供 Apple Developer ID 的 Gatekeeper 信任或公证。此方案不改系统信任设置、不重置或修改 TCC 数据库，也不把私钥分发给应用用户。

## 配置 GitHub Secrets（发布前一次性完成）

若三项 Secret 尚未齐备，tag workflow 只执行版本检查与测试，跳过签名、安装包上传和 Release 创建。仅推送 tag 不代表已经发布可下载安装包。

在 `gusibi/MoliShot` 仓库 Settings → Secrets and variables → Actions 添加：

| Secret | 来源 |
| --- | --- |
| `MOLISHOT_CODE_SIGN_P12_BASE64` | `code-signing.p12` 的单行 Base64 |
| `MOLISHOT_CODE_SIGN_P12_PASSWORD` | `p12-password.txt` 文件内容 |
| `MOLISHOT_SPARKLE_PRIVATE_KEY` | `sparkle-private-key.txt` 文件内容 |

若使用已登录的 GitHub CLI，可在维护机器运行以下命令。命令直接从文件读取，不在终端打印私钥：

```bash
signing_dir="$HOME/Library/Application Support/MoliShotSigning"
openssl base64 -A -in "$signing_dir/code-signing.p12" \
  | gh secret set MOLISHOT_CODE_SIGN_P12_BASE64 --repo gusibi/MoliShot
gh secret set MOLISHOT_CODE_SIGN_P12_PASSWORD --repo gusibi/MoliShot \
  < "$signing_dir/p12-password.txt"
gh secret set MOLISHOT_SPARKLE_PRIVATE_KEY --repo gusibi/MoliShot \
  < "$signing_dir/sparkle-private-key.txt"
```

CI 在临时目录恢复材料，在临时钥匙串中导入 P12，按从内到外顺序签署 Sparkle 辅助程序、框架和主应用，然后删除临时钥匙串。不修改登录钥匙串或系统信任。发布前检查代码证书指纹和内置更新公钥；不匹配则失败。

`setup-update-signing.sh` 是首次建立身份的工具，需要 OpenSSL 3。本仓库已经建立发布身份，**不要再运行它为现有用户换一套密钥**。它在目标目录存在时拒绝覆盖。

## 本地打包与发布

本地需要已接受许可的完整 Xcode、XcodeGen、Python 3.9+、网络及原有签名材料：

```bash
make dmg
```

输出到 `dist/`：`MoliShot.dmg`、`MoliShot-v版本号.zip`、`appcast.xml`。脚本先签名，再打包；打包后不要再改 `.app`、ZIP 或 XML 的内容，否则必须重新签名。

发布新版本时：

1. 在 `project.yml` 同步修改 `MARKETING_VERSION` / `CFBundleShortVersionString`，并递增 `CURRENT_PROJECT_VERSION` / `CFBundleVersion`。
2. 运行 `xcodegen generate` 和测试，提交本次发布内容。
3. 推送与显示版本一致的 `v版本号` tag。Release workflow 检查版本一致性，构建并上传产物。
4. 确认该正式版本为 GitHub Latest，且订阅和 ZIP 可下载。

每个 appcast 包含当前完整安装包，不依赖先前的小版本。不能把预发布版本设为这条稳定订阅的 Latest，也不要给历史版本重新发布为 Latest。必须严格递增 build number；Sparkle 按 build number 判断更新顺序。

自动更新保留应用安装位置和 Bundle ID `com.molishot.app`；只替换应用包。设置、历史和暂存数据在应用包外，更新代码不删除或迁移它们。应用应安装在可写的持久位置，不应从 DMG 或下载隔离产生的临时位置运行。若目标目录需要管理员权限，安装器可能要求系统授权。

若存在截图编辑、贴图、OCR 窗口或正在采集/取色，安装会等待。保存并关闭这些窗口后，再选择菜单中的「安装已下载的更新…」。

## 验证

2026-11-01 本机验证：完整源码使用 macOS 26.5 SDK 编译通过；99 项应用测试和 2 项发布测试通过。隔离测试应用使用独立 Bundle ID，已经走通同一自签名身份下的 Sparkle 下载、校验、原位替换和重启。篡改 ZIP 或 appcast 会被拒绝。未改动当前安装，未执行真实截图权限迁移。完整 Xcode archive 受本机未接受许可限制，CI 归档仍待首次远端执行。

无需 Xcode 的发布元数据测试：

```bash
python3 -m unittest discover -s scripts/tests
```

正常的应用测试：

```bash
make test
```

发布前必须做一次真实 A → B 验证：

1. 备份当前安装和签名材料。在固定位置安装用同一发布身份签名的 A。
2. 授予屏幕录制和辅助功能权限，完成真实截图和全局热键操作；记录设置、截图历史与暂存内容。
3. 发布或在隔离测试订阅提供更高 build 的 B。由 A 内的更新器下载、校验、安装并重启。
4. 确认运行路径和版本已变为 B；重复真实截图/热键操作，并检查数据和系统授权。
5. 重启系统后再次检查；同时覆盖下载失败、损坏包被拒绝和编辑窗口阻止重启的情形。

相同 DR 的静态检查不能代替上述权限测试。如果特定 macOS 版本仍要求重新授权，应记录该系统版本和实际错误；不要以自动重签或自动重置权限作为补救。

参考：[Sparkle 接入](https://sparkle-project.org/documentation/)、[发布更新](https://sparkle-project.org/documentation/publishing/)、[Apple DR 说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。
