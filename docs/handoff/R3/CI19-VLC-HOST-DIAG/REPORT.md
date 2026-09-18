# CI19 VLC 真实失败与最小宿主补证方案

本报告只读诊断固定 af6d85c81893cb689607fdeb0b9f266c8cc24d25。当前分支 codex/r3-20260918-ios，文档 HEAD c1338e7bc22f5ebc5f5e3c9d3edad9d7a6f7eb88。MediaRecorder/Cache 两文件未完成 WIP 已另行保全，不属于本单元，不 stage、不声称可编译。

## 已确定的证据

- CI19 run 35330793250 / job 105554427449：SDK 41/41；原 storage 155/155；新增 VLC 四方法均 playback 失败，无 skip。导航/打包/冷启动 NOT_RUN。
- 原 artifact 10541226567：66,568,799 bytes；SHA256 f9c750011b96c1590ea0e9c24ce6bbebd8111573504d86134f78798aab77330e。根保全目录 artifacts/integration/20260918/R3-ios-ci19-evidence/ios-01-a-20260918-094123。
- 四 JSON 都标 INCOMPLETE_OR_FAILED / NO_SAFETY_CONCLUSION。基础播放 observed decoded=91、displayed=0、hasVideoOut=false、timeMs=0、width=height=64；返回体读取已发生，尚无真实可见帧证据。不能把 decoded 计数当成成功图像解码，也不能仅 cached time=0 判定内部时钟。
- 原 storage.log:17367 开始 VLC suite；17372 明确 TinodiosUITests-Runner 进程创建 player。随后是 FFmpeg get_buffer/thread_get_buffer/decode_slice_header/no frame 链。其日志没有提供明确 OpenGL/vout/applicationState 的失败原因，无法唯一归因。
- 实际依赖证据已成功：Pod 3.6.0；spec checksum 8fe98ae53b7464f32e4bdf527cc7d53053e4d3a5；运行时 3.0.21 Vetinari / 3.0.21-49-gd1840ca85f。双 lock、实际 headers、simulator binary SHA 已在四 JSON。并未校验下载 archive。
- storage-attachments 中四 MP4 的原 manifest 名称都是 Screen Recording，尺寸 1206×2622，是 XCTest 屏幕录像；根 FFmpeg 成功解码这些附件不证明 64×64 源短片有效。probe clip() 没有附加其 AVAssetWriter 输出原片，tearDown 正常移除临时源文件。该证据缺口必须补。

## 当前源路径及未证候选

project.pbxproj:727–746 的 TinodiosUITests 是 bundle.ui-testing；1545/1567 仅 TEST_TARGET_NAME=Tinodios，没有 TEST_HOST/BUNDLE_LOADER。其业务/存储 XCTest 名字不是 App hosted unit target。

VLCPlaybackProbeTests.swift:246–262 在该 runner 里选择首个 connectedScene（无论其 activationState），没有 scene 则创建 legacy UIWindow；只设置 isHidden=false，未核 UIApplication.state、foregroundActive、keyWindow、实际 drawable.window 和可见 bounds。所有测试没有启动一个承载该 drawable 的前台 App。因此当前宿主是确定缺少前置证据的测试安排；它是否是本次 get_buffer 唯一根因尚未证实。

后台独立复核所读官方 VLC 3.0.21 ios.m：创建输出在 main；背景 UIApplication 会拒绝初始化；非 active 拒绝 makeCurrent；drawable/container 和 framebuffer 失败均有拒绝路径。该源码未显式要求 keyWindow/makeKeyAndVisible、未直接检查 UIScene。官方 tag 与实际 d1840ca85f 二进制不等于逐字映射，不声称改 keyWindow 一定能修好。
来源：https://raw.githubusercontent.com/videolan/vlc/3.0.21/modules/video_output/ios.m 。

AVAssetWriter.completed 只证明写入结束，不是独立读回解码；HTTP Range 源夹具已实际收到读取但没有独立 AVAssetReader 或原文件。不能先排除编码夹具。下一单元必须区分 Apple 解码、VLC 输出与安全观察。

## 拟定最小 7 文件接线

1. TinodiosUITests/VLCPlaybackProbeTests.swift：保留原四方法与默认 VLC 参数；从 UI runner 移到新 hosted unit target；加入源短片原样 XCTAttachment、SHA256、尺寸/帧/PTS/颜色的真实 AVAssetReader 读回结果（解码输出像素，不能 passthrough）。先附原片后验证，失败仍保全。VLC 验证继续 decoded/displayed/time≥150ms/hasVideoOut/64×64 与原 8 秒；不降级为只下载或只解析。
2. TinodiosVLCProbeHost/AppDelegate.swift：独立 UIKit 空 host，只有主窗口和空 view，不导入生产 AppDelegate/Cache/SharedUtils，不自动创建真实账户、连接、Firebase、推送或生产 URL。主窗口 makeKeyAndVisible；probe 只往该前台宿主添加真实 drawable。无新生产 source。
3. Tinodios.xcodeproj/project.pbxproj：增加 application host 与 bundle.unit-test 两 target；TEST_HOST/BUNDLE_LOADER 指向专用 host；unit target 只编译原 probe 与现有 ClawSecondaryUIState 原源码。链接/嵌入同一 TinodeSDK、TinodiosDB 及动态 Pods，不改这些生产文件。原 UI target 移除 probe 单一 source membership，其余保持。
4. Tinodios.xcodeproj/xcshareddata/xcschemes/Tinodios.xcscheme：加入 host unit testable；不使空 host 成为发行/Archive 产品。实际 App 导航仍 TinodiosUITests/IdentityNavigationUITests。
5. Podfile：新 host 使用原 db_pods、Kingfisher ~>5、MobileVLCKit ~>3；嵌套 test inherit! :search_paths。不增加或升级第三方依赖；不把生产 Firebase 等初始化引入空 host。
6. Podfile.lock：同步 Podfile checksum；现有 PODS/DEPENDENCIES/SPEC CHECKSUMS 全部保留。当前 tracked checksum 已落后既有 Podfile，CI 原 pod install 会重写；本次必须与新固定源一致并由 Mac 安装验证。CocoaPods Core 1.15.2 checksum 是源文件 SHA1，Windows 以提交 LF 字节计算，不伪称 Windows 执行 pod install。
7. Scripts/ci/verify_publish_outcomes_macos.sh：将原 UI runner VLC selector 换为新 TinodiosVLCProbeTests/VLCPlaybackProbeTests，原七 storage selectors/SDK41/导航3 不变；同一次 storage.xcresult 收原155+VLC4，避免 duplicate。现有 storage 原始附件导出与 workflow 无须新增文件。

CocoaPods 官方嵌套测试继承用法：https://guides.cocoapods.org/syntax/podfile.html#inherit_bang 。
冻结校验规则：https://raw.githubusercontent.com/CocoaPods/Core/1.15.2/lib/cocoapods-core/podfile.rb （checksum 方法）。

## 证据与失败约束

- 总方法仍 200（SDK41 + 原storage155 + VLC4），真实导航3另列；源片/宿主对照是四方法的夹具步骤，不虚增数量。
- 独立 JSON 记录 UIApplication.state、scene 有无/activationState、window hidden/key/bounds、drawable.window 绑定。必须 active、真实可见 key window 与有效 drawable；存在 scene 时必须 foregroundActive；legacy host 没有 scene 时明确标记而不是伪造 foreground scene。
- 原片 SHA/字节/AVAssetReader 帧与尺寸结果、VLC 真实解码/显示/原PNG、安全场景观察分别列。Apple 读回通过不替代 VLC；VLC 基线不通过就不能给 redirect/退役/cache 安全结论。
- 仍仅合成数据/127.0.0.1；原 120 秒方法总预算、8 秒播放和5秒清理保留，不改 VLC vout/硬件解码参数。
- 不重画 PNG，不把系统 Screen Recording 当源短片。不能归因未采集到的 applicationState 或 GL 错误。
- Mac 构建/实际 hosted 行为待授权精确候选 CI；Windows 只做 project/scheme/selector/依赖静态一致性及 diff 检查。实际 VideoPreview 页面与真机依旧未覆盖。

## 回退与剩余边界

该单元只改测试/接线，生产继续 e6；可回退新测试 host 单元，不动原用户数据/协议/VLC版本。当前 VOICE 两文件 WIP 保留在独占树，另保全 voice-wip.patch（23,559 bytes、SHA256 2df87bd109385eddbe5c331f488bbfd14e5755be0446682242538468adae730e），绝不随此测试提交纳入。若新 host 仍失败，保留其源clip与上下文重新判断，不盲目改 timeout 或播放器生产。

## 已实施候选（等待精确 Mac 验证）

总控批准后实施上述恰 7 测试/CI 文件，未 stage 生产 WIP。专用 host 是独立 bundle app.clawos.tests.VLCProbeHost，legacy UIWindow 生命周期；测试真实核 active，若存在 scene 则核 foregroundActive，记录 scenePresent/legacyLifecycle，不能把无 scene 伪装为有 foreground scene。key/visible/drawable 是本夹具更严格的前置要求，不是已证 VLC 硬要求。VLC 前与取样时的 host 状态均留 JSON。

原 baseline 方法另加同一 bytes 的本地 file 播放/实际 PNG，与随后 loopback HTTP 结果分开。四方法不增加；原 120 秒总预算、8 秒播放条件、5 秒 stop 和真实帧色断言保持。AVAssetReader 在原片附件保全后请求 BGRA 解码，要求 90 帧、64×64、递增 PTS 与实际预期颜色；其结果不是 VLC 通过。读回循环有5秒截止并受原方法总预算约束，不把单次同步 AV API 宣称可强制中断。

Windows 已执行：verify_wiring.py 的 32 项静态 graph/source/锁文件检查 PASS；bash -n PASS；git diff --check PASS。这是源检查，未运行 Xcode、pod install、Swift 或真实 VLC。验证脚本完整解析 OpenStep pbx，原有 graph 仅4对象变化（根group、products、project targets/attributes、移出probe的UI sources）；其余旧目标/链接/测试保留。Podfile.lock 除 checksum 一行外逐字相同，固定版本/依赖/spec 不变。

准确期待数：SDK41；UIrunner155 = Publish4 + Migration62 + Identity30 + Removal9 + Public13 + Secondary16 + OwnedImage21；新host原VLC4；总200。实际App导航3独立。CI19此前只通过原196，新的host结果 NOT_RUN，不能把本地32项静态检查称200原生通过。

Backend 固定官方链进一步确认：VLCKit 3.6 构建脚本 TESTEDHASH dd8bfdba 加49个patch；官方 base ios.m 有后台/active/framebuffer拒绝路径，仍不证明本次二进制错误唯一原因。引用：
https://raw.githubusercontent.com/videolan/vlckit/3.6.0/buildMobileVLCKit.sh
https://raw.githubusercontent.com/videolan/vlc/dd8bfdba/modules/video_output/ios.m
后台报告 backend docs/handoff/R3/IOS-CI19-VLC-RENDERER-DIAGNOSIS.md，固定 5a0ded41。

回退本候选只需回退这7文件（包括source membership、host及Podfile checksum），保留原失败产物与报告；不要撤回生产其他修复。新host不得被打包作正式产品。Windows目前没有Ruby/CocoaPods/Xcode，CocoaPods集成和真实 TEST_RUNNER_→host 环境传递必须由下一Mac确认；缺失仍严格失败，不提供静默默认值。
