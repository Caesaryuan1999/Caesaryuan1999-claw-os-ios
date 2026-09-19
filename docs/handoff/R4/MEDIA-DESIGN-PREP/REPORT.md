# 普通 AU 消息媒体只读准备

固定来源：`0ea19847e3b043bc14bfb046d2e1809cf92134e6`，分支 `codex/r3-20260918-ios`。本报告不修改生产、测试、工程或 CI，不重跑原生，不把当前 B02 的 13 状态方法与 5 布局方法预期写成结果。所有源码行号均指该固定 Git 版本。

## 结论与实施顺序

普通 AU 当前是 24pt 扬声器附件加时长，既不是新紧凑气泡，也没有真实播放位置驱动的进度。应分三包：**新录音 60 秒限时** → **普通 AU 播放的输入/账号/页面生命周期** → **紧凑气泡视觉**。第一包已由总控要求优先冻结，准确四源和边界见 [RECORDING-60S.md](RECORDING-60S.md)；本次仍只读。视觉不能掩盖播放器目前的状态和归属缺口。

读取了唯一 DESIGN_SPEC / PAGE_STATE_MATRIX / COPY_GLOSSARY 的 R4-COMPACT-VOICE-V2-20260919，以及 Figma 文件 `CreMqit00K1MAJju69YoOv` 的浅色 `326:1527`、深色 `328:1568` get_design_context，组件 `326:1526`。沿用 UIKit、原 C3/AUTH、消息读取/回执、录音手势及原 Logo；没有生成或发送样例音频。新用户规则覆盖旧样稿中 72 秒示例：新录制最多 60 秒，到时停止采集保留试听/发送，不自动发送；**旧历史超过 60 秒仍真实显示和读取**。

## 从真实消息到播放器

| 环节 | 固定源位置 | 实际行为 |
|---|---|---|
| 数据到富文本 | Tinodios/Utils.swift:658–666 | StoredMessage.attributedContent 使用 FullFormatter 并缓存 NSAttributedString；旋转/字体变化通过 MessageViewController:438–444、716–724 清缓存重布局。 |
| AU 元数据 | Tinodios/format/AbstractFormatter.swift:153–154；FullFormatter.swift:56–71 | Drafty AU 的 val/ref/mime/name/size/duration/preview 与实体 key 原样进入 FormatNode.Attachment；duration 为 Int 毫秒。引用块走 QuoteFormatter，不能把所有含 AU 的消息误判为纯语音。 |
| 实际附件 | Tinodios/format/FormatNode.swift:362–402 | 时长使用 millisToTime；实际生成 MultiImageTextAttachment，24×24 图标后接文本。voiceWidth 只用于足够显示图标的 guard，没有把计算宽度应用到气泡。当前 AU 不生成 WaveTextAttachment。 |
| 绘制更新 | Tinodios/format/MultiImageTextAttachment.swift:29–36；FormatNode.swift:859–879 | play/pause/reset 仅切换两张扬声器图标并 invalidateDisplay；seek 被忽略。不能以这个图标切换声称正在解码。 |
| 点击命中 | Tinodios/widgets/RichTextView.swift:50–98；MessageCell.swift:235–256 | 只有附件字符的真实 glyph 区域产生 audio/toggle-play URL。时长文本/普通气泡空白不是整条播放入口；其余 message 点击保留选择模式。 |
| 原消息定位 | Tinodios/MessageViewController+MessageCellDelegate.swift:220–241、648–650、696–702 | cell.seqId → messageSeqIdIndex → 原消息 Drafty 实体 key；把该实体的 duration/bits/ref 交给 cell.toggleAudioPlayback。不得由显示昵称/当前任意会话合成归属。 |
| 实际播放 | Tinodios/MessageCell+VLCMediaPlayerDelegate.swift:39–79 | 每 cell 持有 VLCMediaPlayer；ref 使用当前 Cache.tinode 解析/附鉴权 query 后交 VLCMedia(url)，inline 使用 InputStream。play() 后立即通知 activate，不等实际 playing 状态。 |
| 位置与结束 | 同上:14–30、82–99；MessageViewController+MessageCellDelegate.swift:271–299 | 当前普通 AU 没有 mediaPlayerTimeChanged；seek 仅用户请求值。ended/error/stopped 调附件 reset。VC 管理 currentAudioPlayer 以暂停前一个，但不能据此推出账号/page 退休已覆盖。 |

duration 的毫秒依据有三条一致链：AbstractFormatter.swift:191–204 先除 1000 格式化；MediaRecorder.swift:201 使用 maxDuration / 1000 调 AV，254 使用 elapsed × 1000 写 Recording.duration；MessageInteractor.swift:735–755、856、977、1046–1053 使用同一个真实 duration 写内联或上传完成后的 Drafty。成功上传 audio 的 ref 已使用 srvUrl，初始 mid:uploading 占位保留，不应因视觉重写这条已封链。

## 几何、方向与身份边界

- MessageViewController.swift:1333–1334 从原消息 from 与 myUID 判收发；1383–1438 计算头像、对齐及独立 metadata。不是从 Figma 示例推断方向。
- 普通气泡最多 min(360pt, 可用列宽扣头像/45pt 远侧留白后的 76%)；content 再扣左右各 14pt（1518、1554）。普通容器最小 94pt/编辑标记 150pt，metadata 在容器外。当前 voiceWidth 为 68 + min(毫秒/1000 × 2, 96)，但 AU builder 没实际采用。
- 新设计 body 为 152/208/264 × 54，尾角额外 7；在窄屏/头像/AX 字号下必须再限可用宽并允许增高。不能把 54pt 附件再无意叠加原上下 28pt padding，也不能改变回执/上传进度的外部位置。
- MessageBubbleDecorator.swift:10–22 当前普通气泡固定无尾角、18 圆角。新 10 圆角和尾角必须显式 AU opt-in，不改变文本、引用、图片、视频、文件。
- 现 326:1526 只冻结三档尺寸，未给时长分档阈值；4/18/72 原示例不是算法。总控冻结阈值后实现；旧 >60 秒仍可落最长视觉档而保留真实时长，不裁剪内容。
- Tinode.swift:648–673 的 URL 信任是 scheme+host+port 相同后才附 query，外源不追加。未发现 Android 同款 scheme-relative trusted=true 分支；仍需原始输入验证和下游重定向取证，不能因此称 VLC 网络安全。
- 录制已有 voiceOwner/UID/sessionGeneration 及 Cache recorder lease；普通消息 cell 播放并未复用这些归属。不得把录音预览已经过的 lifecycle 测试移作普通 AU 证据。

## 有代码依据的可靠性依赖

### AU-R1：duration 窄化前无界限

MessageCell+VLCMediaPlayerDelegate.swift:61–62 在 VLCMedia.length <= 0 且 duration > 0 时执行 Int32(duration)。JSONValue.asInt（TinodeSDK/model/JSONValue.swift:80–84）与 AU 入口均没有上限校验。受控反例可用未知媒体长度与 duration=2147483648；该值在 iOS Int 可表示，Int32 精确转换超出范围会失败。**这是源码可达的数值陷阱，不是本轮已运行的 Swift crash。** 应验证元数据、有限位置值和 VLC 可表示区间；新录制 60 秒规则不能拿来拒绝所有历史长语音。

### AU-R2：普通 AU 的播放状态与生命周期缺少原 owner/attempt 绑定

ref 在点击时两次读取动态 Cache.tinode（52–53），cell 只存实体 key；state callback 不核 player === audioPlayer 或消息身份（14–30）。同 cell 复用/换消息后，旧 stopped 回调可能清新 key/UI；seek 的延迟闭包也读 self.audioPlayer 而非捕获原 player（93–97）。错误/缓冲/实际 playing 没有准确反馈；Loading 连点可再次 play。

MessageVC:432–435、865–881 的 inactive/离页/音频中断只调用录制或录音试听处理；stopRecordingPlayback:905–916 只作用 recordingPlaybackPlayer。普通 currentAudioPlayer 没有同类明确关闭。可复现设计：开始普通 AU → 同页 owner 退休或页面覆盖而 cell 未复用/deinit → 检查真实播放器/网络是否继续；另以旧 player 的异步 stop 回调对照新 cell 播放。**本轮确认缺少门禁，不宣称已运行跨账号数据泄露、实际后台持续播放或服务器越权。**

建议可靠性最小五源白名单：

1. Tinodios/MessageCell+VLCMediaPlayerDelegate.swift：实际 state/time、严格原 player/attempt、输入验证、暂停继续、准备期单任务。
2. Tinodios/MessageCell.swift：绑定 owner/UID/generation/topic/message/entity/attempt 的 cell 播放责任，复用/销毁取消。
3. Tinodios/MessageViewController+MessageCellDelegate.swift：从真实原消息启动/分发，只更新匹配实体，不再枚举同消息所有 AU 一起变状态。
4. Tinodios/MessageViewController.swift：普通 AU 页面/账号/中断退休以及当前 player 管理；不混录制 lease。
5. Tinodios/ClawSecondaryUIState.swift：仅必要的既有 owned context/download/lease 复用适配；无需新增 SDK/wire/DB。

传输需独立冻结：当前 AU 直接 VLC 网络路径绕过已测 ClawOwnedFileDownload。优先复用捕获原 owner 的无重定向 ephemeral 下载，再本地文件播放；同源鉴权/外源 HTTPS 无鉴权、按原限额/空间预算、独立播放文件责任、停止确认后清理。已有 ClawOwnedImageContext:237、ClawOwnedPlaybackLease:503、ClawOwnedFileDownload:599 可复用，但不能仅名字复用就当音频验证通过。整文件准备会增加首播等待；本地 fileURL 也不保证容器不发起次级网络，已知 VLC playlist 边界仍需控制/验证，不把“无 query”当全格式隔离。此处是待总控冻结建议，未替换传输。

## 视觉单元的准确最小边界建议

在可靠性已提供真实状态接口后，建议七个代码文件；不改 FullFormatter 的数据语义或 Utils/DB 的缓存接口：

1. Tinodios/format/FormatNode.swift：AU 附件构造接新 compact renderer，保留实体 key、真实毫秒、混合/引用内容。
2. Tinodios/format/CompactVoiceTextAttachment.swift（新）：渲染 duration/wave/progress 与真实状态，UIFontMetrics，未知 duration 不造百分比；独立与录音 WaveImage 定时动画。
3. Tinodios/MessageCell.swift：整个 AU 气泡有效触区/VoiceOver 动作，选择/长按保留，不能把混合消息其余正文变成音频按钮。
4. Tinodios/MessageCell+VLCMediaPlayerDelegate.swift：只连接已封可靠状态到 attachment，不另造一套 player。
5. Tinodios/MessageViewController+MessageCellDelegate.swift：匹配 entity 的状态/实际 position 消费。
6. Tinodios/MessageViewController.swift：AU 专用尺寸、方向/颜色/内边距、AX/旋转缓存重排，保持 chat viewport 与 metadata。
7. Tinodios/MessageBubbleDecorator.swift：显式 AU 10pt/尾角 opt-in，其余气泡逐字逻辑保持。

这不是现在的编辑授权。最终 exact drawable 资源白名单需按 Figma 导出冻结；当前项目扬声器 glyph 不等于参考的细声波。只读上下文可取得 Figma wave/tail/loading/unavailable SVG，不在本次下载或引入；不临时绘一个貌似相近的新 glyph。若最终实现可在新 attachment 中包含尾角而无需 decorator 改动，可在开工前收缩为六源，不能为了凑数量扩大原 renderer 语义。

Figma 状态对应：Ready 元数据时长；Loading 准备真实源；Playing/Paused 使用实际 player position/time；Unavailable 保留真实原因。暂停点击继续同 player；不是另建 player 从零。实际播放/已听/消息已读/发送回执相互独立，禁止新增已听持久化。背景颜色复用 ClawTheme；无常驻“播放/暂停/继续”文字按钮，但 VoiceOver 必须明确动作。

## 可执行验收分层

- 原生布局：现 App-hosted target 用真实 Drafty → StoredMessage.attributedContent/FullFormatter → 新附件 → 原 MessageCell/MessageViewLayout，320pt/常规宽、收发、AX/light/dark、旋转/复用、单/多 AU、引用+音频、metadata/上传状态。记录真实 PNG 与尺寸、字形/不裁剪、尾角、整条中心/边缘 hit 与 VoiceOver。不要用中性替代 cell 证明生产气泡。
- 播放消费者：原 cell/delegate 的实际方法配真实 VLC、合成音频、本机隔离 HTTP；首帧/真实时间推进、buffering 不提前 Playing、暂停位置/继续、完成、错误、重复点击单任务、旧 player 回调不动新消息、离页/owner 退休、未知/超范围 duration。真实 callback 需来自依赖，不用 timer 冒进度。
- 传输：复用现 owned helper 真实请求验证同源/外源、redirect、限额、空间不足、临时文件寿命；另外针对普通 AU 的真实入口证明使用原 scope。旧视频 14 方法/7 VLC 方法不能代替普通 AU 消费链。
- 录制：见独立限时说明。原 SDK/DB/C3/AUTH/录音/聊天锚点回归全部保留；不为本提案预造方法数量、native 结果或设备通过。
- 本轮实际执行只有固定源码/Figma 只读和文档一致性检查，无 Swift、模拟器、真机、麦克风、网络播放或新 CI。MobileVLCKit 固定 3.6.0；CI43 两次官方下载失败仍由总控记录，未改依赖规避。

## 交付与回退

本目录只有报告与固定 Git blob/SHA 清单。后继源码包须由总控分别冻结录制、可靠性、视觉名单；当前 0ea 的 B02 生产保持。回退本报告仅涉及文档，不替换源文件、旧安全包或共享设计规范。
