# VLC 原生行为取证候选

本单元仅测试/CI接线，生产仍为已通过 CI17 的 e6e07aff。未改 VLC、SDK、协议、数据库或 VideoPreviewController。未自行 push/dispatch。

## 实际修改范围

- TinodiosUITests/VLCPlaybackProbeTests.swift：4个真实依赖测量方法；Network 的真实 TCP socket 服务只绑定127.0.0.1动态端口，重定向还验证目标属于本轮活动服务注册端口；AVAssetWriter生成64×64、3秒红/蓝H264 MP4；实际VLC statistics、time、videoOut与原始PNG snapshot。
- Tinodios.xcodeproj/project.pbxproj：只增加一个测试文件的reference/buildfile/group/实际测试Sources。
- Scripts/ci/verify_publish_outcomes_macos.sh：安装pod后记录3.6.0实际simulator头/二进制SHA，沿原storage invocation加一个class selector；原导航调用保留。
- Podfile已经通过app_pods给TinodiosUITests引入MobileVLCKit，不需修改；Podfile.lock亦无变化。实际代码边界3文件，少于已批准4文件。

196个旧原生方法的源文件与选择保持，导航3保持；本次新增4个VLC测量方法。下一Mac期望原生200（SDK41 + storage159），另导航3；这只是候选数量，尚未实际运行本单元。

## fixture断言与安全观测

四方法名及接线检查见 wiring-checks.json。正常基线必须满足：实际读取、decoded/displayed计数、64×64 videoOut、时间进展>=150ms、VLC原始snapshot颜色正确。重定向和退休方法各自先跑同字节正常解码控制，不能用损坏fixture得出“没有危险行为”。

受控server首请求、原owner.logout后真实context失效、可观察终态和真实stop是fixture条件；缺事件或超时会失败。body释放有持久布尔屏障，避免请求已记录而header回调未到时release丢失。VLC的async stop要观测stopped，不能将error/ended当作已经停止。失败后保留JSON阶段、数值metrics、原生失败和已取得的真实PNG；不记录完整URL/query/凭据。stop超时保留播放器到测试进程结束，避免无证强制销毁，不宣称已清理。

安全记录独立使用：
- CONFIRMED_GAP_REDIRECT_FOLLOWED：实际本机目标被访问，是否携密另看安全布尔；显式Location带合成query不能误称VLC自行泄漏。
- CONFIRMED_GAP_PLAYER_NOT_BOUND_TO_OWNER：实际owner退休后仍读取/解码，不代表实际VideoPreview页面退出路由已被运行。
- CONFIRMED_GAP_OLD_CONTENT_REUSED：换内容/403后仍有旧帧；不直接推断磁盘持久缓存或跨账号利用。
- NOT_OBSERVED_THIS_FIXTURE：此有界样本未观测到；不是全协议安全证明。

测量可完成并使XCTest方法通过，同时JSON记录CONFIRMED_GAP；总控必须独立读安全观察，不能将200个方法绿称为播放安全。另有明确fixture失败时整个方法失败，不转成skip。没有假VLC、URLProtocol替代、生产guard镜像或真实VideoPreview覆盖声称。

## 依赖可追溯性

CI对实际 Pods/Local Podspecs/MobileVLCKit.podspec.json 验证版本3.6.0与归档SHA1a5077beeb7bf943a3fbbb91523752e50a10d490a3046cb9808d906784ddbc36，选择iOS simulator slice，记录VLCMedia/VLCMediaPlayer/VLCLibrary三个头的SHA及所需API存在、framework二进制SHA/声明版本和架构；不下载网上新头替代。JSON经TEST_RUNNER_CLAW_VLC_POD_EVIDENCE传入原生并随附件保存，另记实际library.version/changeset，缺任何安装证据失败。

TEST_RUNNER_前缀按[Apple官方测试环境说明](https://developer.apple.com/documentation/xcode/environment-variable-reference)使用。VLC statistics/snapshot与async stop依据固定[3.6.0对应头/源码](https://raw.githubusercontent.com/videolan/vlckit/c73b779f/Headers/Public/VLCMediaPlayer.h)，最终仍由实际Mac头和编译裁定。

## 当前实际验证

- 现有源策略44/44通过；这是源码层，不是Swift执行。
- 实际新增CI Python证据代码抽取执行5/5：合法fixture通过；错误版本、错误归档SHA、缺API、slice越界均fail-closed。使用临时合成pod树，仅验证脚本边界，不冒充实际Pods。
- Git Bash对完整CI脚本bash -n通过；原196源文件和旧selector顺序逐字/集合对应不变，Podfile和lock不变。
- diff --check通过；PBX新增ID/reference计数与实际Sources接线检查通过。
- Windows未执行Swift编译、VLC解码或HTTP行为；没有给这4方法标PASS。未知UI runner上的视频输出/快照能力若失败要保留Mac事实，不能改成假图或仅playing状态通过。
- 测量限额见实施前PLAN；不扩大播放器范围。全部结果走已有storage.xcresult/log，不增加workflow权限、真实服务、签名或推送。

原FINAL-E6E07AFF包不重封为新候选；它仍对应已验证生产/CI基线。待总控独立审查精确提交后执行新的Mac测量，本单元只提供决定最小播放修复的证据。
# Attachment export follow-up to ef50ca3

The initial probe commit is `ef50ca3afed19781186fc5c79d5617521eaf2909`. Its four native methods are unchanged. This follow-up modifies only the existing CI shell script and `.github/workflows/ios-smoke.yml`; cumulative code/wiring scope is four files. Podfile and production remain unchanged.

The existing EXIT-trap attachment exporter now runs the same implementation for `navigation.xcresult` and `storage.xcresult`. On the Mac runner it first captures current `xcrun xcresulttool help export attachments` and requires both `--path` and `--output-path`, then executes the confirmed export command. Original PNG/JSON and the original xcresulttool `manifest.json` remain unmodified in `storage-attachments/`. Fixed `storage-export-status.json` records each exported file's SHA-256/size, PNG dimensions, JSON observation identification, command result, and elapsed time. Workflow uploads `storage-export*` and `storage-attachments/**` even on failure.

Missing storage bundle is `NOT_RUN`. A present bundle with failed export, no PNG, or no VLC observation JSON is `FAIL`; successfully exported evidence is only `PASS_EXPORTED_ONLY` with `NOT_ASSESSED_BY_EXPORT`. This does not assert that all four probes passed or that their security observations are safe. An existing test failure always retains its original exit status, even if either export succeeds or fails; when tests succeeded, either export failure fails the step. One export failure cannot be overwritten by the other export succeeding.

Windows validation: the actual embedded exporter ran against controlled subprocess boundaries in 13 cases (original bytes/hash, absent bundles, help/command failure, timeouts, malformed/missing PNG/JSON). The actual cleanup shell function ran five combinations covering original-test failure priority and either export failing. All 18 passed; Bash syntax and diff checks passed. These are adapter/CI tests, not execution of Apple's tool or native VLC. Expected Mac counts remain 200 native (SDK 41 + storage 159) plus navigation 3; new four VLC methods and this export await Mac execution. Original `source-manifest.json` describes the ef50ca3 probe; `attachment-export-source-manifest.json` describes the two-file follow-up.
