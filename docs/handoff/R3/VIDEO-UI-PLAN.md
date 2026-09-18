# R3 VIDEO-UI — 只读落地任务包

日期：2026-09-18。状态：PLAN / NOT_IMPLEMENTED。冻结源版本：74075fec5334a1e2325b2b194974828afdd6f2f3；分支 codex/r3-20260918-ios。本单元只新增此报告，不修改生产、测试、工程、共享设计或协议。

## 结论与最小边界

建议下一独立 UI 单元恰好 2 个生产文件：

1. Tinodios/VideoPreviewController.swift：真实播放/音量/准备分享的显示状态、文字动作、可访问性、元数据和恢复提示；复用现有 VLC 对象与 740 owner/source/attempt/导出门禁。
2. Tinodios/Base.lproj/Main.storyboard：只调整 scene MGh-dV-dd1 / controller gfT-SI-43h，保留 ShowVideoPreview 路由和原有连接；改为安全区内可滚动内容、视频画布和明确的文字控制区。

不必修改 zh-Hans/Main.strings：现有 gfT-SI-43h.title（257）与 Hah-A8-0yd.title（278）已经是“视频预览”。新状态文字可在上述控制器内按本批已有中文显示方式设置；其他语言及路由不全文替换。复用 Utils.swift:21–121 的 ClawTheme，不改共享主题。LargeFileHelper / ClawSecondaryUIState / UiUtils / SDK / DB / SendImageBar 及其传输、发送语义均不在视觉实施边界。

若后续要求新增可由存储 unit target 直接运行的显示状态 helper，应先单列批准 ClawSecondaryUIState.swift 第 3 生产文件及其真实消费者测试；不能以控制器未参与编译的镜像数组测试代替 UIKit。当前最小 2 文件方案不承诺现有离线身份导航测试覆盖视频。

## 已读取设计与适配依据

- 按 figma-design-to-code 技能实际调用 get_design_context 并查看返回截图：file CreMqit00K1MAJju69YoOv，暂停 160:1886、播放 160:1920、失败 158:1888。对应原型 161:941 / 161:978 仅作为共享交接引用，未执行真人 Present 或声音/分享操作。
- 共享 FIGMA_HANDOFF.md:40–44、PAGE_STATE_MATRIX.md:176–180、COPY_GLOSSARY.md:205–213 明确 iOS 动作为“分享视频”，不是保存到相册；旧表中“保存视频”不作为本平台新文案依据。
- 设计：24pt 内容边距、20pt 纵向间距、12pt 圆角、52pt 播放/声音/分享按钮；浅色 A 背景与 surface，画面保持黑色/深色视频容器。原生 UINavigationBar 与返回手势保留，不复制 Figma 的假状态栏/固定 390pt 宽度。
- 海边矢量、00:24、8.6MB、周末海边.mp4 都是设计示例；实现只使用真实 VLC 画面与 VideoPreviewContent，不植入示例媒体、时长、大小或文件名。
- 复用 ClawTheme.background/surface/ink/muted/primary 与 font（UIFontMetrics + 系统字体）；不为示例 Noto 字体另装字体资源。styleSecondaryButton 本身背景透明，需要在此页设置 surface 与 buttonRadius 才能对应白色按钮。

## 实际路由、连接与现状证据（行号均相对 740）

| 位置 | 已确认事实 | UI 实施约束 |
| --- | --- | --- |
| MessageViewController+MessageCellDelegate.swift:738–760 | 既有消息 entity val/ref → .remote → ShowVideoPreview；两者都不存在时不会进入预览 | 不新增缺失 entity 的上游路由；控制器收到无效 ref 时应有可见恢复 |
| MessageViewController+SendMessageBarDelegate.swift:188–201 | 选择视频 → .local，duration/size 初始为 0 | 本地发送场景不得被远端“分享视频”替换，0 大小不虚称已知 0B |
| MessageViewController.swift:787–790；Main.storyboard:2318 | prepare 注入 previewContent 和 replyPreviewDelegate；segue Sf1-B5-1DJ → gfT-SI-43h | 保留原 push 导航与回到聊天 |
| Main.storyboard:4487–4608 | 画布 9da-W1-wGM 和 controlsView U3w-v0-LZx 四边重叠，铺满 safeArea G0u-7c-sXh；当前没有滚动容器/元数据/错误正文 | 只重排这个 scene，不能按全屏固定帧盖住导航/安全区 |
| Main.storyboard:4502–4555 | slider HIz-fY-dpa；时间 aza-Xk-MXu / DtN-H7-Ovv 固定高24；播放 YKO-G2-ljq 固定70×70图标；静音 dbI-Af-LGw 最小44×44图标 | 取消不适合动态字的固定24高度；文字按钮最小52pt、可增长；保留可拖动进度 |
| Main.storyboard:4597–4603 | 7个 outlet：controlsView/currentTimeLabel/durationLabel/playPauseButton/spinner/videoSlider/videoView | 新增 mute/share/metadata/error 连接需逐项核实，不留下断开的 IBOutlet |
| Main.storyboard:4589–4593；VideoPreviewController.swift:124–144 | 右导航按钮 vUM-ge-cBl → saveVideoButtonClicked；运行时标题“分享视频”；本地来源隐藏此按钮 | 新正文分享 UIButton 必须调整控制器动作接线，不能只换视图 |
| VideoPreviewController.swift:246–255 / 327–336 | 播放中图标 alpha 降0.2；声音只有图标，无明确中文；未强制设置初始静音 | 新文字按钮保持可读；标题从 player.isPlaying / audio.isMuted 得出，不能照原型默认“开启声音” |
| VideoPreviewController.swift:340–419 | playing/opening/error/ended/stopped/paused 有分支，buffering 仅固定 debugPrint；错误 toast，无错误正文；时间委托更新 slider/label | 使用实际事件渲染，不假装已有完整可见状态 |
| VideoPreviewController.swift:188–234 / 422–476 | 离开停播/取消分享/失效 source；仅本地通过 SendImageBar 获得 inputAccessoryView 和 firstResponder；本地缩略图后原发送通知 | 远端不引入键盘依赖；本地字幕/回复/发送一次性门禁完整保留 |

## 布局具体实施建议

保留 videoView 为 player.drawable。内容视图用 UIScrollView + 垂直 stack，连接 contentLayoutGuide 四边和 frameLayoutGuide 宽度；safeArea 下方留20–24pt底部间距。视频容器维持深色、12pt圆角，默认接近设计304pt但不把固定高度叠加成不可滚动的屏幕；横屏/小屏和无障碍字号均允许滚动到动作。真实内容保持 aspect-fit，不拉伸视频。

视频下依次为播放/时间/声音区、可拖动进度、真实文件资料、全宽“分享视频”，失败时显示恢复正文及“返回聊天”。设计没画 slider 不代表删除现有 seek 功能；其状态以 duration>0 且 player.isSeekable 判定。常规宽度两个动作可并排，时间可单独占行；可访问性字号时改纵排/自动换行，不能硬套设计104+118+104宽度。

文件名多行或尾截断且读屏可读全名；缺失文件名显示“视频附件”，时长未知显示“时长未知”，size<=0或缺失不展示虚构数值。使用传入值/已获得的 player 长度；不为展示大小额外读取全文件或发网络请求。

现分享 action 的 guard sender as? UIBarButtonItem（VideoPreviewController.swift:277–280）是明确接线限制。建议在同控制器把“启动现有分享”的方法与按钮表现分开，正文 UIButton 入口调用同一方法，用捕获本次按钮/状态的 restore 闭包更新 UI；继续让 ClawOwnedFilePresentation.complete 消费 Result。不得保留一个不可见的导航按钮来假装新按钮已经接线，也不能绕过 context/source/attempt 守卫。

## 播放与导出必须是两组独立状态

| 真实输入 | 建议显示/可用动作 | 不可宣称 |
| --- | --- | --- |
| setup 来源无法解析 / 空数据 / owner 不再有效 | 显示“视频暂时无法播放”和返回；会话失效按现有操作结束提示，不启动新 owner 请求 | 不显示能完成修复的“重试播放”，不从新账号补源 |
| VLC opening | 画布内 spinner +“正在加载视频…”；播放/seek未就绪禁用，返回保持可用 | 不捏造下载百分比，不等同分享文件准备 |
| VLC buffering | 显示“正在缓冲…”；以实际事件结束 loading，保持取消/返回；不重复调用 play 伪重试 | 不把 buffering 当已播放或永久错误 |
| VLC playing | 显示“暂停”；真实当前时间/总时长；可seek才启用slider | 不因设计为 paused 就改变现有远端自动播放 |
| VLC paused | 显示“播放”；保留真实进度 | 不重新创建播放器或换媒体URL |
| VLC ended | 显示“重新播放”；使用现有 stop/position=0/play 路径 | 不把结束当下载失败 |
| VLC stopped（当前来源仍有效） | 当前可重新开始时显示“播放”；离开/owner失效后的回调不渲染 | 不因离开触发的 stopped 恢复旧页面 |
| VLC error | 标题“视频暂时无法播放”，说明“请检查网络连接，或返回聊天后重新打开。”；“返回聊天”真实 pop；停止spinner，禁无依据的播放/seek | VLC未提供HTTP证据时不写“无权”或断言仅网络原因；不画空转的重试 |
| audio存在且 isMuted=true / false | “开启声音” / “静音”；无audio时禁用且说明暂不可用 | 不假定设计示例表示实际初始静音 |
| 可分享的远端来源、未准备 | “分享视频”，点击仍走740安全导出，与播放是否paused无关 | 暂停不等同下载完成 |
| 本次安全导出进行中 | “正在准备分享…” +独立loading，禁止重复提交；返回可用并取消旧attempt | 不复用播放器spinner，不显示发送/相册进度 |
| Result成功且原owner/source/attempt仍有效 | 使用现有 UiUtils main 再门禁后打开系统分享；恢复按钮 | 不提示“已保存到相册”或把系统面板出现视为分享完成 |
| HTTP403 / 网络/写入失败 | 展示现有 ClawFileTransferError 安全文案；网络/写入可再次点击“分享视频”形成新attempt；403只提示原错误并返回 | 不能把HTTP403转换成播放VLC错误，也不反复重试无权限 |
| invalidURL / invalidData / redirect拒绝 | 保留失败说明/返回，不画“重试即可成功”的专用动作 | 不放开URL、redirect或改用全局后台下载绕过失败 |
| 离开 / 换账号 / 旧attempt晚完成 | 继续740禁止消费/清理自有导出；新页面不被旧loading/错误写入 | 不以UI更新为由降低会话世代门禁 |

播放失败和独立下载成功并非互斥（例如本机解码不支持某文件）。最小视觉批应保持既有安全分享能力：有有效远端来源时可另显示“分享视频”，但不能称该文件已可播放；若来源本身无效则禁用。系统分享关闭返回后不自动重启下载或声称已分享成功。

## 深色、动态字号、VoiceOver 与键盘约束

- 深色视频画布不变，外围使用 ClawTheme 动态色；trait变化更新必要CGColor，禁止 setInterfaceColors 继续把整个新A内容区强制黑底。原生导航外观由已有主题提供。
- 按钮最小52pt，不沿用共享 touchTarget=48 冒充52；用 minimum height 和内容padding允许字号增高。文字 UIFontMetrics + adjustsFontForContentSizeCategory，多行说明/错误/文件名；不通过缩小字体隐藏溢出。
- 播放按钮读屏标签随实际动作在“播放/暂停/重新播放”切换；声音同理，按钮状态与isEnabled一致。spinner用简短加载描述，时间标签不做每帧 live announcement。
- 进度为可调整控件，标签“播放进度”，value表达实际已播放/总时长；只有可seek才提供调整。声音未就绪、分享准备中均说明禁用原因。装饰画布/重复时间可避免重复聚焦；焦点顺序为导航→播放→进度→声音→资料→分享/恢复。
- 远端来源沿现有 canBecomeFirstResponder=false，不出现字幕键盘，不依靠键盘隐藏/显示才露出播放器按钮。iOS最低14（pbxproj:1341等），不得无条件使用iOS15 keyboardLayoutGuide。
- 本地来源仍为发送预览：保留 SendImageBar 的字幕键盘、回复、发送动作。新滚动区需兼容原 accessory 的可视占位，不能让新分享按钮覆盖发送栏；此次不改 SendImageBar 或发送协议。

## 实施后的验证计划与当前界限

本报告没有新增测试方法或运行构建。740现有准备数量仍为 SDK41 + storage155 =196 原生方法，另真实App离线身份导航3；其中VIDEO新增14方法仍待精确Mac候选运行。上次root验证的是e903的SDK41+storage141与导航3/冷启动，不能转记为740通过。

下一视觉批首先做 scene XML/outlet/action/constraint 检查和完整App编译；保持740生产安全回归的原断言。真实UI验证需实际视频fixture或可授权账号路径，当前3个身份导航方法不能达到登录后的聊天视频，也不能证明VLC播放、seek、声音或system share成功。

建议实际验收矩阵：远端paused/playing/ended、opening/buffering、无效源/VLC错误、独立分享准备与失败、退出/换账号晚回调，以及本地发送预览不回归；小屏/横屏、浅深色、默认及最大可访问性字号、VoiceOver调整进度、分享返回。应分别记录真实播放器、下载helper、UI截图和系统面板证据；不能用纯状态helper冒充VLC/设备行为。

当前已核实的是源路由、连接、约束、实际Figma上下文和安全状态接口；视频新布局、VLC内部重定向/缓存、真实播放/分享、动态字号和VoiceOver运行均未验证。Figma Present未验。保留e903密码截图/IME与实际accessibility断言不一致的既存证据，本报告不扩大身份或视频安全审计。
