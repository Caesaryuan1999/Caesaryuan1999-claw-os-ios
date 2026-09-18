# CI20-HOST-LINK-01

基线：c0971f929dc3550683817a59cb768fb389a3fc1f（包含已封 AUDIO-REF-01；VOICE WIP 未纳入）。

## 原始失败与依据

CI20 固定 6e5670f0475b70b51256cdfa1a2588bbefd988f0，run 35334232330 / job 105565274934。SDK 41、原 UI runner 155 方法通过；新 host 已编译链接，但 dyld 在测试启动前 signal abort：FBLPromises.framework/FBLPromises 不存在。4 VLC 方法 NOT_RUN；导航、打包、冷启动未执行。这不是又一次“4 个播放断言失败”。

原 artifact 10542697308：76,343,020 字节，SHA256 4f774c5b5abed15d0f9691ef399dea660e6363d353a2839569b9fd0102c30f54。原 storage.log 第 14415 行 host debug dylib 和第 16737 行测试 bundle 的真实 clang 命令均携带主 App 的 Firebase/FBLPromises 等框架；第 18069–18070 行 dyld 指向 host debug dylib。安全摘要和原命令 SHA 保存在 ci20-link-red.json。

工程 project Debug/Release 的 baseConfigurationReference 是 devel/prod.xcconfig；两者第 6 行 include 主 App 的 Pods-Tinodios 配置。新 target 的自有 CocoaPods flags 又继承 project 设置，形成窄宿主链接了主 App 框架而只嵌入其自有依赖的失配。

## 最小修改

仅 Podfile、Podfile.lock 两个测试依赖配置文件。post_install 明确只匹配 TinodiosVLCProbeHost/TinodiosVLCProbeTests：读取各自 aggregate 的生成 OTHER_LDFLAGS，移除 inherited 标记，在对应 user target 配置写入明确 override。保留其自身生成的系统库和 MobileVLCKit/Kingfisher/SQLite/SwiftKeychainWrapper，拒绝混入 Firebase/FBLPromises/WebRTC 等 App 依赖。没有给空宿主增加 Firebase，也没有手抄固定全套 linker 参数。

Podfile.lock 只改变 PODFILE CHECKSUM；PODS、DEPENDENCIES、SPEC CHECKSUMS 和版本不变。原主 App、UI runner 配置、VLC 默认参数、4 方法/断言/8 秒/120 秒上限、测试 selectors、生产源码全部不在本次提交范围。

CocoaPods 官方 1.15.2 的生成设置会为复数项添加 inherited，OTHER_LDFLAGS 由自有 libraries/frameworks 构成：[build_settings.rb](https://raw.githubusercontent.com/CocoaPods/CocoaPods/1.15.2/lib/cocoapods/target/build_settings.rb)。post_install 在 user project integration 前运行；修改保存到 user project：[installer.rb](https://raw.githubusercontent.com/CocoaPods/CocoaPods/1.15.2/lib/cocoapods/installer.rb)、[user_project_integrator.rb](https://raw.githubusercontent.com/CocoaPods/CocoaPods/1.15.2/lib/cocoapods/installer/user_project_integrator.rb)。实际 CocoaPods 生命周期和最终 Mach-O 依赖仍由下一次 Mac 验证。

## 验证层级与交接

Windows：12 项源码/锁/原始证据检查，git diff --check；没有 Ruby（Windows、当前 WSL 均无），不称 Ruby hook、CocoaPods、Swift、dyld 已执行通过。必须由下一轮准确 Mac 候选验证：两宿主实际 link 命令不再携带主 App Firebase 依赖；host 成功启动；原 4 探针实际生成 AV/VLC 分列证据。仍不预判 VLC 渲染/redirect/缓存安全。

本提交累计原生期望 202 = SDK 43（AUDIO 新 2 尚待 Mac）+ UI runner 155 + hosted VLC 4；真实导航 3 单列。VOICE 新 8 方法和 6 生产 WIP 全部保留工作区且未纳入；不要把其数量或行为算进本候选。未推送或触发 CI。
