# CLAW OS iOS GitHub Actions 打包说明

这个流程用于没有 Mac 的情况下，用 GitHub Actions 的 macOS runner 生成 `.ipa`，再上传到第三方苹果签平台。

## 关键限制

第三方平台要求上传的是已经由 Xcode 导出的 `.ipa`，并且 IPA 内必须包含：

- `Payload/*.app/embedded.mobileprovision`
- `Payload/*.app/Info.plist`
- Info.plist 中的 Bundle ID 与签名使用的 Bundle ID 一致

因此 GitHub Actions 仍然需要 Apple 签名资料来完成一次原始导出。第三方平台之后可以再重签。

## GitHub Secrets

在 GitHub 仓库中打开：

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

添加以下 secrets：

```text
APPLE_TEAM_ID
IOS_CERTIFICATE_P12_BASE64
IOS_CERTIFICATE_PASSWORD
IOS_APP_PROFILE_BASE64
IOS_EXTENSION_PROFILE_BASE64
IOS_KEYCHAIN_PASSWORD
```

建议 Bundle ID：

```text
主 App: app.veilping.clawoschat
通知扩展: app.veilping.clawoschat.TinodiosNSExtension
```

如果第三方签名平台要求固定 Bundle ID，运行 workflow 时改成平台要求的 Bundle ID。

## 没有 Mac 如何生成 p12

可以在 Windows 或 Linux 上使用 OpenSSL 生成私钥和 CSR。

```bash
openssl genrsa -out ios_distribution.key 2048
openssl req -new -key ios_distribution.key -out ios_distribution.csr
```

然后到 Apple Developer 后台：

```text
Certificates, Identifiers & Profiles -> Certificates -> + -> Apple Distribution
```

上传 `ios_distribution.csr`，下载 Apple 返回的 `.cer` 文件，再转换为 `.p12`：

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey ios_distribution.key -in distribution.pem -out ios_distribution.p12
```

`IOS_CERTIFICATE_PASSWORD` 就是导出 `.p12` 时设置的密码。

## 生成 mobileprovision

到 Apple Developer 后台创建两个 App ID：

```text
app.veilping.clawoschat
app.veilping.clawoschat.TinodiosNSExtension
```

再创建两个 Distribution provisioning profile。第三方签常用 `Ad Hoc`，如果平台要求其他类型，以平台要求为准。

下载后得到两个 `.mobileprovision` 文件：

```text
主 App profile
通知扩展 profile
```

## 在 Windows 上转 Base64

PowerShell：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\ios_distribution.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\app.mobileprovision")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\extension.mobileprovision")) | Set-Clipboard
```

分别粘贴到对应的 GitHub Secrets。

## 运行打包

进入 GitHub 仓库：

```text
Actions -> Build iOS IPA -> Run workflow
```

输入：

```text
app_bundle_id: app.veilping.clawoschat
extension_bundle_id: app.veilping.clawoschat.TinodiosNSExtension
export_method: release-testing
```

成功后在 workflow run 页面下载 artifact：

```text
claw-os-ios-ipa
```

里面包含导出的 `.ipa`。把这个 IPA 上传到第三方苹果签平台即可。

## 常见失败

`Missing required GitHub secret`

说明 GitHub Secrets 没填完整。

`No signing certificate "Apple Distribution" found`

说明 `.p12` 不正确，或 `.p12` 不包含私钥。

`No profiles for ... were found`

说明 Bundle ID 和 provisioning profile 不匹配。

`IPA does not contain embedded.mobileprovision`

说明导出不是签名 IPA，不能上传到第三方平台。
