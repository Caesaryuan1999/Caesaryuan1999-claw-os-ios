# VIDEO-OWNED-02 — 原账号完整下载与独立播放文件责任

起点 `abc23071b23671323d7bce89340ea6ffb513cb3b`；其中 abc2307 是 CI24 的独立 VLCTime 编译修正，不属于本单元。原 TEST-PROBE-403 为 758b062、VOICE-UI 为 e6d0aa9。本单元仅改以下两生产文件，另两既有测试文件和一处必要方法数量策略。未改协议、VLC 参数/版本、数据库、录音、上传后台会话、Storyboard 或私有配置。

| 文件 | 实际改动 |
| --- | --- |
| Tinodios/VideoPreviewController.swift | remote ref 完整 owned 下载完成后才将独立本地文件交 VLC；每次播放独立 player/lease；可见主线程 common 约 250ms owner 检查；原 owner/attempt 回调门禁；准备与按原因恢复文案；独立分享下载 |
| Tinodios/ClawSecondaryUIState.swift | 可选下载预算、真实卷空间/累计和最终字节检查；播放文件 lease 及异步停止责任；自有导出清理返回结果，失败保留注册责任 |
| TinodiosUITests/OwnedImageTests.swift | 新增 8 个实际预算/下载/lease 方法，真实 SDK/SQLite/临时文件；可控 URLProtocol 和停止通知边界明确 |
| TinodiosUITests/VLCPlaybackProbeTests.swift | 新增 3 个真实 HTTP/VLC 方法；原 4 方法全文不变，复用原空前台 host、默认 VLC、8 秒解码条件和 120 秒单方法上限 |
| Scripts/ci/test_owned_image_policy.py | 保留原 21 方法前段计数，再核累计 29；其他原策略不删减 |

## 原问题与修复边界

`red-source.json` 保留修改前完整 blob/SHA 和直接源码反例：remote ref 经 addAuthQueryParams 交 VLC；owner 失效的两个播放器回调只 return；下载没有资源上限。这是源码证据，不是 Windows Swift 红测。

既有 CI23 真实 VLC 依赖观测已证明直接 URL 路径会跟随 302/307，原 owner 退休仍可继续读/解码；只有 Location 明文带合成查询参数时，目标见该参数，不把未带参数的目标描述成自动泄漏。该探针没有实例化 VideoPreviewController。原 403 不完整失败、renderer 内部 CALayer 警告继续保留，不由本单元抹去。

生产远端入口现在复用 ephemeral owned URLSession 完整 200 下载：同源捕获 header、外源合法 HTTPS 匿名、拒绝所有 redirect、禁共享 cache/cookie。结果回主线程复核原 context/source 后才 `VLCMedia(url: file)`。不再将原远端 URL 或鉴权 query 交给播放入口。原本地选择文件仍不归本页删除；inline InputStream 和本地 SendImageBarDelegate 发送方法保持原行为，后者全文比对未改。

下载前从原 owner 捕获已协商 maxFileUploadSize，沿用现有 8 MiB 缺省。单操作实际可用空间预检为 `2 × maximum + 16 MiB`，乘加溢出/非正上限拒绝。进度检查声明/实际累计字节，未知长度仍限制实际字节；URLSession 临时文件和最终保全文件均再查大小/完整长度。可选 budget 默认 nil，保持其他下载调用者兼容。它不是全进程磁盘预留，不能承诺进度回调前零瞬时超量，也不能承诺后台续传。

播放与系统分享各用独立 UUID 文件。每个 lease 的 stop、state、detach、releaseMedia 捕获同一个实际 player，旧 lease 不引用控制器后来 player。owner 门禁返回后才执行 VLC/UI/文件操作，不在 SDK/Cache 锁内等待主线程。页面离开/source 更换/deinit 取消原下载与可见 timer，并退休该 lease；原账号失效还关闭本页本地发送 accessory，不能用后来 owner 恢复。

**停止不是立即完成。** 官方 VLCKit 3.6 `stop` 调用 `libvlc_media_player_stop_async`；`state` 是缓存状态。lease 在曾请求 play 时要求同 player 的真实状态通知且实际 state 为 stopped，不能用初始 state 0 当证明。立即停止请求/撤 drawable 后，保留文件到该条件成立；固定 5 秒未确认只标 cleanupPending，停止计时而保留本 attempt/observer/文件责任。晚到该 player 的停止事件仍可回收。未确认时不 unlink、不 forcekill、不反复 stop，不影响新 player。删除失败保留导出注册与 lease 责任。连续失败/无停止事件会保留进程内对象和临时文件；没有跨重启自动清理保证，也没有磁盘全擦除承诺。

官方机制依据（不是精确二进制重建）：[VLCMediaPlayer.m 3.6.0](https://raw.githubusercontent.com/videolan/vlckit/3.6.0/Sources/VLCMediaPlayer.m)。部署 Pod/实际 binary/header/runtime 仍由既有 Mac 取证步骤记录。

## 页面映射

已实际读取 Figma file `CreMqit00K1MAJju69YoOv` 的 188:2002 与 189:2003 截图/上下文，沿用既有 A 主题、原导航与 52pt 动作，未新增无效“重试播放”。

- 准备：“正在准备视频”；“视频下载完成后即可播放。返回聊天将取消本次加载。”；“取消并返回”。
- 网络未完成：“视频未加载完成”；“请检查网络后，返回聊天重新打开视频。”；“返回聊天”。
- 403、会话失效、超出本机预览限制、空间不足、空间查询不可用、写入/完整性/redirect 各给对应原因。
- 完整有效源已取得但 VLC 播放失败，保留 166:1918 的“你可以返回聊天后重新打开，或分享原文件。”及“分享视频”。

整文件准备会增加首帧等待，替代远端边下边播/Range。250ms 是可见主线程调度间隔，不是即时撤权承诺；线程阻塞可延迟，播放器停止本身异步。不承诺后台播放。

## 原生方法与证据等级

现有 class-wide selectors 自动包含新增方法：`TinodiosUITests/OwnedImageTests` 与 `TinodiosVLCProbeTests/VLCPlaybackProbeTests`；PBX 现有生产 helper 归属 TinodiosDB/App、原测试文件和 host 链接已存在。因此不需要改 PBX、Podfile、selector 或依赖版本。

新增 8 UIrunner 方法：

1. `testVideoBudgetChecksTwoCopiesReserveOverflowAndRealFilesystem`
2. `testVideoDownloadRejectsKnownAndUnknownLengthOversize`
3. `testVideoBudgetRechecksActualFileAndPreservesBoundedDownload`（含截断 200）
4. `testVideoDownloadSpaceFailuresNeverStartTransport`
5. `testPlaybackLeaseRejectsRetiredOwnerAtQueuedMainConsumption`
6. `testPlaybackLeaseRequiresStoppedEventAndRetainsFileAfterTimeout`
7. `testPlaybackLeaseOfflineOwnerAndLocalSourceArePreservedUntilRetirement`
8. `testPlaybackRetirementCannotStopNewAttemptOrDeleteShareFile`

新增 3 前台 VLC host 方法：

1. `testOwnedDownloadedFileProducesRealVLCFrameTimeAndSeek`
2. `testOwnedLeaseRetirementStopsRealPlayingAndPausedVLCBeforeFileRemoval`
3. `testLocalPlaylistExternalReferenceRecordsRealVLCNetworkBehavior`

UIrunner 使用真实生产 helper、SDK/SQLite、URLSession 和磁盘文件；URLProtocol、停止通知/播放器闭包是受控边界，不称实际 VLC。对应真实 VLC host 方法使用同一生产下载/lease、真实 socket HTTP、AVAssetWriter 原片、AVAssetReader 对照、实际帧/time/seek/停止状态。owner 检查直接调用生产 lease，并未驱动完整 VideoPreview 页面或其 250ms UI timer。完整 UIKit 页面、设备、system share 和真实服务仍 NOT_RUN。

累计 **226 原生期望 = SDK44 + UIrunner175 + VLC host7**，另真实离线导航3。原211 SDK/UIrunner方法及原4 VLC方法不删除，新增方法尚未执行 Mac。

**本地 fileURL 不等于任意容器网络隔离。** M3U 方法只包含唯一合成本机 loopback 引用，固定观测窗记录是否实际请求；访问则明确 `CONFIRMED_SECONDARY_NETWORK_ACCESS`，未访问仅 `NOT_OBSERVED_NOT_NETWORK_ISOLATION_PROOF`。未静默改格式白名单、参数或替换播放器。实际结果将决定后续最小取舍，不能以该观测方法绿宣称整体播放安全。

## 当前检查与 CI 分层

- Windows：32/32 定向源码检查；44/44 既有源码策略；git diff --check。原4 VLC及原21 OwnedImage方法全文比对一致。检查不是 Swift 编译或原生运行。
- CI24 精确758：SDK44通过，App因 VOICE Delegate.time 可选链编译失败，其他 NOT_RUN；独立 abc2307 修正后由 root 跑 CI25。本单元不属于该候选。
- CI25/abc2307 结果待 root，不能记到本单元。新候选 Mac 原生226/导航3/页面均待运行。

## 应用与回退

交 root 固定提交审查后才进入其授权 CI；本代理不 push/dispatch。单元 patch 以 abc2307 为起点，必须在已保全相同起点的隔离树正向应用并核 blob/mode。回退本单元会重新暴露已确认的远端播放/owner 风险，只供受控排查，不能把回退包当已验安全版本；不动用户库、C3 状态、签名和私有配置。
