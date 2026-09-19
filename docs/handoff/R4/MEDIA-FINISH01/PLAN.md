# 普通 AU 播放可靠性计划（待总控冻结）

基线 `86cf0fa87a28946c56a87e1e3eb67a51e4dbaa84`；分支 `codex/r3-20260918-ios`；本端 `work/r3-20260918-ios`。本报告重新读取固定源码，只提交本目录文档。cb296 录音限时、1fa8 连续宽度、B02 及原失败证据保持。没有生产、测试、Pod、项目成员、selector、协议或数据库修改，没有推送/CI。

## 1. 真实链路与本批需要关闭的窗口

| 固定源码 | 已确认的行为与影响 |
| --- | --- |
| `MessageViewController+MessageCellDelegate.swift:696–713` | AU 原图标点击进入 cell 的播放/seek；当前 entity 索引未完整核合法范围，seek 可接受非有限值。方案只补 AU 消费入口，不扩其他媒体。 |
| `MessageCell+VLCMediaPlayerDelegate.swift:47–64` | 远端 ref 动态取 `Cache.tinode` 两次，拼鉴权 query 后直接交给 VLC；inline 则交 InputStream。没有绑定原页面 owner。metadata `Int32(duration)` 对大值有溢出风险。 |
| 同文件 `14–32, 66–99` | delegate 没有核当前 player 身份；调用 play 后立即显示播放，不依据实际成功；seek 的延迟 pause 动态取 cell 新 player，旧任务可能作用到新媒体。 |
| `MessageViewController+MessageCellDelegate.swift:654–665` | 普通音频回调遍历 cell 全部 attachment，混排多个 AU 时没有按 key 精确更新。 |
| `MessageCell.swift:205–228` 与 `MessageViewController.swift:433–436, 865–927` | cell 回收会 stop，但没有 attempt/owner 门禁；页面离开、inactive、音频中断的现有受保护流程主要针对录音及试听，普通 AU 未完整接入。 |
| `MessageViewController+SendMessageBarDelegate.swift:62–110` | 录音开始与录音试听需要明确终止普通 AU；普通音频更换为另一引擎后不能继续只依赖旧 VLC 指针互斥。 |

以上为源码反例，不称本轮已在 iPhone 或模拟器重现。此前 CI26 已实际观察到 VLC 本地 playlist 仍可引发 secondary HTTP 请求；不能把「先安全下载，再交 fileURL 给 VLC」作为该风险的关闭证据。既有真实 VLC 结果继续保留，不替换播放器默认参数掩盖它。

## 2. 精确五生产文件

1. `Tinodios/MessageCell+VLCMediaPlayerDelegate.swift`：保留现有文件及来源版权，在此承载普通 AU 的 owner/attempt 控制器、`AVAudioPlayer(data:)` 适配与 AV delegate。不给普通 AU 的播放器 URL/stream，不保留 VLC fallback。文件名暂不重命名以免新增项目接线。
2. `Tinodios/MessageCell.swift`：普通 AU 控制器引用与窄 delegate 状态接口；回收/deinit 退休；绑定原消息和 entity key。原布局、点击区域、录音条无变化。
3. `Tinodios/MessageViewController+MessageCellDelegate.swift`：AU 专用合法索引/类型检查；捕获原页面 owner、UID、generation、topic、消息身份、entity key；当前控制器身份门禁与指定 attachment 更新；有限 seek；失败时原文件安全下载动作。
4. `Tinodios/MessageViewController.swift`：页面普通 AU 唯一播放责任、inactive/中断/离页清理、主线程可见期间 owner 检查。与原录音试听 VLC 指针分离；保留显示锚点及连续宽度实现。
5. `Tinodios/MessageViewController+SendMessageBarDelegate.swift`：只在原 `.start` 和 `.playbackStart` 成功进入条件后退休普通 AU，防重叠采集/播放。cb296 的 stopAndSend、到限、finish 顺序、发送及文件责任逐字保持。

复用且不修改 `ClawSecondaryUIState.swift` 内 `ClawOwnedImageContext`、`ClawOwnedFileDownload`、`ClawVideoDownloadBudget` 与 `ClawMediaFiles`。现有 budget 虽以 Video 命名，其显式 maximumBytes 构造、磁盘预检和完整文件约束可直接用于音频。不复用依赖 VLC stopped 通知的 `ClawOwnedPlaybackLease` 来伪装 AV 生命周期。

不修改 FormatNode / MultiImageTextAttachment / SendMessageBar / XIB / MediaRecorder / Cache / Interactor / SDK / DB。新版 48pt、声波、整气泡点击属于下一视觉包；本批不扩大旧 24pt 图标点击范围。

## 3. 格式兼容与安全恢复

当前 iOS `MediaRecorder.swift:184–190` 实际产生 `.m4a`、MPEG4 AAC、16kHz、单声道；Android 固定 `c8b23a3ddcd967f3a8bc98fb9de9b73e085313f9` 的 `MessagesFragment.java:1558–1564` 是 MPEG_4 + AAC、16kHz、24kbit/s。此两条证明当前录音格式，不代表所有历史语音都相同。

AU 保存 mime/ref/val/duration，原 VLC 消费没有只准 AAC 的限制。因此旧 Ogg/Vorbis、Ogg/Opus、其他容器可能存在；本轮没有用户历史样本，也没有当前平台 AVAudioPlayer 对所有这些格式的运行证明。**不能把 Opus 编码支持等同 Ogg 容器可播放。** 新路径只按实际 `AVAudioPlayer(data:)` 解码结果接受，不按扩展名或 MIME 假装解码成功；不支持或损坏时明确失败，绝不隐式转回 VLC URL、网页或另账号请求。

建议提示与恢复：

- 解码不支持/损坏：「当前设备暂时无法播放这段语音，请联系发送者重新发送。」保留原消息、原时长与数据，不裁剪、不转换后写回、不循环自动重试。
- 下载/传输失败：「语音未加载完成，请检查网络后重试。」只有当前原 owner/page 仍有效时允许用户再次点原图标启动新 attempt。
- 403：「当前账号无权播放这段语音。」不把 inline 附带值当远端失败的权限回退。
- 已退出/换号/页面退休：取消并清本次播放责任，不在后来页面弹旧错误。
- 超本地预览限额：「语音文件过大，暂时无法在本机播放。」不误称服务器拒绝上传，不改已有消息。

超限或不支持格式不剥夺原文件的访问权限。在该失败提示提供显式「下载原文件」时，复用 `ClawOwnedFileDownload` 和 `UiUtils.presentFileSharingVC(for:presentation:from:)`，原 owner/context/attempt 与当前页面复验，按原文件下载预算落 UUID 文件，交系统分享/保存到文件；不套用 8MiB **播放内存**上限，不把文件载入普通 AU 播放器，也不自动发请求。内联则按现安全 UUID 文件工具导出原字节。仍须满足原文件资源预算与权限；失败准确说明，不能承诺任何大小都可下载。AU 不是原 EX 文件行，因此不能写成「旧 AU 点击已有这个入口」：总控已接受此窄恢复动作列入第 3 源，待本 PLAN 整体冻结后实施，不新增页面，不调用动态 Cache 的旧兼容入口。

Apple 的 [AVAudioPlayer Data 初始化接口](https://developer.apple.com/documentation/avfaudio/avaudioplayer/init(data:)) 与 [归档音频指南](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html) 支持内存音频与 Core Audio 格式这一方向；归档文档不是当前 OS 的全格式兼容矩阵。以真实 AAC 与 Ogg/Opus fixture 测实际结果；不从文档推出所有版本一致或任意容器绝对网络隔离。

## 4. 下载、内存与 playlist 边界

本地完整压缩音频输入上限：`min(原 owner 协商 maxFileUploadSize, 8 * 1024 * 1024)`，缺省 8MiB，非正限额拒绝。**总控已接受该预览资源取舍，待本 PLAN 整体冻结后实施；它不是新上传/协议限制。** 内联 Data 和下载完整 Data 都受同一上限；传输 expected/累计字节、保全文件最终长度、读入前后 Data.count 均核。复用 budget 的 `2 * maximum + 16MiB` 磁盘预检，不把它称磁盘预留或总解码内存上界。压缩输入 8MiB 也不保证系统解码额外内存不增长；只允许页面单一活动 AU，不预取整个聊天。

权限路径使用创建该页面时的原 owner，先确认 Cache slot、SDK session generation、UID/Store UID 和消息 topic/身份，再捕获 context/headers，锁外开始网络。纯 WebSocket 离线不阻断本账号 inline 或已加载内存音频。

远端 ref 使用现 `resourceURL` 规则；凭据严格同 scheme/host/port origin，只由 captured owner 生成 headers。现有合法外源 HTTPS 可以匿名下载，绝不带服务凭据；拒外源 HTTP、userinfo、非 HTTP(S)、mid 占位、无效地址。不是为了本包扩展可访问外源。沿用 ephemeral download、无 cookies/共享 cache/credential storage、禁止全部 redirect、严格 HTTP200、错误一次完成。协议相对 `//host` 按解析后的 origin 判定，不能当同源。

完整文件保全到 UUID 专属目录后，核长度再读 Data，解码器**只收到字节**，不收到 ref、URL、baseURL、query、header、路径或播放列表 resolver。M3U/PLS 等播放列表不是受支持音频，必须失败；即便伪装 audio MIME/`.m4a` 也不能借旧 VLC 处理。负向实测包括本地 playlist 的唯一 loopback secondary endpoint，以及容器外部引用样本；仅有限样本零请求，不把它升级成任意恶意格式形式证明。若实际 AV 解码仍触发外部引用请求，保持失败并交总控冻结格式边界，不增加 VLC fallback。

Data 成功移交本 attempt 后原下载导出文件不再是播放器输入，可按原 UUID 所有权删除；失败/取消/退役清该 attempt 临时文件，清理失败保留 URL 责任重试，不碰本地用户文件。此包不增加持久播放缓存；同一 attempt 暂停恢复用原 Data/player，跨页重新进入可能重新下载。

## 5. 回调、真实时间与生命周期

所有普通 AU UI/engine 操作在主线程，AV/network 调用不在 SDK/Cache 锁内。每次加载关联不可变 owner+UID+generation+topic+消息身份+entity key+attempt；网络及 AV 回调必须同时匹配当前 controller/engine/attempt。先退休旧 attempt 再开始新请求，旧结果只清自己的资源。混排只更新对应 AU key。

状态为准备/播放/暂停/完成/失败；准备期不通知 attachment「正在播放」。仅实际 `play()` 成功且 `isPlaying` 为真才显示播放；进度读取当前 engine 的 `currentTime`/`duration`，不用 timer 累加模拟时间。元数据不送入 `Int32`，不用于猜测真实播放完成。时间必须 finite，actual duration > 0；seek 比例 finite 且 clamp 到 0...1，位置夹在实际 duration 范围。旧 >60 秒语音正常读取/显示，不应用新录音限额裁剪。

暂停继续同一 engine，不重建/不重下；重复准备点击不产生并行下载。用户切另一 AU、cell 回收、页面离开/deinit、后台/inactive、中断均停止对应 engine、取消 timer/download、断 delegate 并释放 Data，不自动恢复播放。录音开始/试听前退休普通 AU；普通 AU 开始时先暂停现录音试听而不删除待发录音。系统会话只由当前播放责任处理，旧 cleanup 不去关闭新录音的共享 audio session。

可见期间采用原方案 250ms main/common 检查 owner 退休；每次操作/回调仍即时复验，离开后取消检查。**轮询不是零延迟停声保证**，主线程调度可延迟；本轮不重写 Cache 退出通知机制。原 owner 失效后，旧播放器无权创建新网络或展示新账号内容。

## 6. 原生证据计划与接线

复用 `TinodiosUITests/VoiceLayoutTests.swift`，现有 `TinodiosVoiceLayoutTests` App-hosted target，现 selector `Scripts/ci/verify_publish_outcomes_macos.sh:399` 已选整类。不新增 target/PBX/selector/Pod/workflow。保留当前 11 方法、其他已封测试及全部旧断言；可在此文件新增有限实际消费者方法与自有窄 fixture。实现冻结后给精确方法数，本计划不把用例组假算方法数。

必要覆盖组：

1. 真 AVAudioPlayer + 现场生成 AAC/M4A 或 PCM：播放成功、实际 currentTime 推进、暂停不推进、继续同 engine、结束；不以 fake engine 代替解码结论。
2. 真实 cell/VC AU 入口：准备不假播、双点击不双下、多 AU 仅指定 key、旧 player/旧下载晚回调、消息索引失效拒绝；原 11 renderer/录音方法保持。
3. 原 owner+实际 SDK/Store 门禁与真实 URLSession/loopback HTTP：同源捕获 headers、外源匿名、redirect/403/无效 ref、超限/未知长度；fake slot 只控制生命周期屏障，报告不称真实登录。
4. inline/完整下载输入：AAC 成功、损坏/Ogg/Opus 明确实际解码结果、不支持不 fallback；M3U/PLS/伪装 MIME/容器外链请求计数为零，保留原始合成 bytes/hash，不只测字符串过滤。
5. 实际 page inactive/离页/cell reuse/owner retire 后状态与资源：晚结果不写新 cell；录音/试听与普通播放互斥，cb296 到限和文件责任不变。
6. finite time、负/未知/极大 metadata、历史 >60、seek NaN/越界、同 engine 身份；不通过改 metadata 伪造实际时长。

HTTP fixture 在 start 之前设置 newConnectionHandler，资源在首个可能失败前注册 teardown；专用有强引用串行 delegate queue，不沿用已修 CI39/42 错误。原声真实输出、听筒/扬声器硬件、通话打断、多设备、后台 OS 调度仍单列设备 NOT_RUN。UI 只测本批实际入口，不能称完整生产聊天/所有格式安全验收。

## 7. 锁定依赖、当前验证与后续

`Podfile.lock` 仍 MobileVLCKit 3.6.0，spec checksum `8fe98ae53b7464f32e4bdf527cc7d53053e4d3a5`。视频与录音试听仍用 VLC，所以普通 AU 改为 AVAudioPlayer 不会自动解除 App 构建依赖。

本轮获准的一次官方固定 archive HEAD 已执行：`vlc-availability.json`，2026-09-19T06:24:32Z，curl exit28/约10秒超时，无重定向跟随、无 body 下载、无 TLS 绕过/重试。只证明此 Windows 路由失败，不推导 GitHub runner 状态。声明中的 archive hash不是本轮下载校验。CI43 两次下载失败原件保留；无依赖变化不重跑、不升级 Pod、不换非可信镜像。

本轮只读源码/官方资料与一次 HEAD；Swift/UIKit/AVAudioPlayer/下载 fixture **NOT_RUN**。既有 321 native +3 navigation 仍为待执行数量，不继承 CI33/34 的通过到当前 86cf。后续：总控冻结五源、8MiB 预览规则和兼容取舍 → 本端独立实现及限定测试 → 固定差异独立审 → 依赖可用时总控精确授权 Mac CI；本端不推送/派 CI。

本 PLAN 回退只需不应用后继实现，不影响已封源。将来实现用独立提交和反向窄 patch 回退；不能因此重新开放旧不受保护 URL 播放作为安全降级。
