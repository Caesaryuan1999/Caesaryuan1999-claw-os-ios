# AUDIO-REF-01：上传成功音频引用

## 基线与变更

独占 r3-20260918-ios，分支 codex/r3-20260918-ios；基线 6e5670f0475b70b51256cdfa1a2588bbefd988f0。生产仅 Tinodios/MessageInteractor.swift 成功完成分支原827一行 ref→srvUrl。ctrl200/url门禁不变；初始 mid:uploading 草稿分支原718保留；其他附件与消息协议/存储不变。

原错误：上传已经得到服务端 url，audio 构造仍从旧 ref 占位创建 Drafty；file/image/video 使用 srvUrl。发送后音频实体因而指向 mid:uploading 而非上传结果。由 root/backend 固定源独立确认。

## 证据层级

Windows 实际读取旧生产分支/完整 draftyAudio/实际 URL.relativize，保全 red-source.json，旧完成分支 ref 与要求 srvUrl 不符（RED）。源修后 GREEN。verify_source_adapter.py 执行与 CI 同一提取器，使用隔离真实 Git 源快照：旧错误分支拒绝、新分支成功、重复 case 拒绝、HEAD 后源码漂移拒绝，4/4符合预期。不是 Windows Swift 或 Drafty 运行证据。

Mac 准备两方法，加入原 TinodeSDKTests 类与既有 selector：
- testUploadedAudioConsumerReplacesPlaceholderWithServerReference：编译源片段的旧分支在真实 Drafty 中仍产 mid；新分支产服务端相对地址且无 mid，duration/preview/size/mime 不变、无 val。
- testInitialAudioConsumerKeepsPlaceholderAndOriginalMetadata：初始占位分支与真实 Drafty 元数据保留。

准确覆盖称“生产分支源码适配 + 真实 Drafty”，不称整个 MessageInteractor 实例、UIKit 上传回调、HTTP 上传或服务端接收。只有合成 BaseURL、UploadDef 输入被适配；构造语句、完整 draftyAudio、URL.relativize 来自源码，Drafty 来自真实 SDK。Mac 此两方法 NOT_RUN，待随 VOICE 下一累计候选运行；CI20固定6e不包含本修复。

## 恰三测试/CI接线文件

1. TinodeSDKTests/TinodeSDKTests.swift：新增2方法；原41方法不改断言。
2. TinodeSDK.xcodeproj/project.pbxproj：仅新增测试来源 build/ci-generated/AudioUploadConsumerFixture.swift 的引用/编译项，App不编译该文件。
3. Scripts/ci/verify_publish_outcomes_macos.sh：SDK测试前严格提取固定HEAD源码，缺失、重复、格式变化、worktree/blob不一致均FAIL，无fallback。旧分支原字节及基线blob固定保全，完整helper哈希绑定。生成文件只在build，metadata写入既有static.json以随CI保留。不把新代码加到CI20已冻结提交。

提取器的输入仅 MessageInteractor.swift 与 Utils.swift，无 SharedUtils/凭据/私有配置。Utils只读。生成代码不复制完整App、更不启动Cache/网络。固定源blob、helper及生成体SHA可在 source-adapter-checks.json 和下轮CI static.json核对。

本地单独运行 SDK XCTest 前必须先执行 CI 脚本中 AUDIO_UPLOAD_SOURCE 准备块（参数为一个已有合法JSON报告路径），或运行 verify_source_adapter.py 生成同字节测试来源。此项是有意的测试准备依赖：文件缺失时构建失败，不静默跳测试。Windows准备不会声明pod/Xcode可用。后续生产helper若变化，哈希门禁必须经源审更新，禁止绕过。

## 数量、检查与回退

候选预期202原生 = SDK43 + UIrunner155 + VLC host4；真实App离线导航3另列。两新方法尚未Mac执行。CI19旧196通过/4VLC失败、6e宿主修复待CI的事实不变。Windows4源码adapter检查、bash -n、diff --check通过。

VOICE未完成 MediaRecorder/Cache 两文件保留原SHA，未stage。回退本修复需回退生产一行和其三测试接线，不能删旧用户数据、改变发送状态或认为已有mid坏消息自动修复。旧已发错误音频不在本修复中自动重传；修复只作用此后上传成功的audio构造。
