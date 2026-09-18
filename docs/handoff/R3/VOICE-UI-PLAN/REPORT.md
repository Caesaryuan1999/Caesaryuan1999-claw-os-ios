# VOICE-UI — 只读实施任务包

建议下一视觉单元限定 **4 个生产文件**，保留 inputAccessoryView、录音 lease、播放器和消息提交入口。复用 R3.D1 / ClawTheme，将紧凑图标条改为真实状态驱动的文字面板。本次只有文档，不实施视觉。

## 基线与证据

- 独占 `work/r3-20260918-ios` / `codex/r3-20260918-ios`，代码 `785461b2006dbc0260472ebfe3cd36907fcbca27`；开始 tracked dirty=0。未跟踪 artifacts 与两份旧 VOICE WIP 保全目录不动。
- CI22/run35338111488 由总控运行，43 SDK + 163 UI runner + 4 VLC host = **210 原生方法**，导航3另列，实际结果待总控。本任务不新增测试计数。
- `source-map.json` 固定7个定向阅读文件的blob/raw SHA；生产、测试、CI均未改，不推送、不重封累计包。
- Recorder/Cache/Interactor/文件责任/C3/AUTH不属于视觉范围。现有录音可靠性候选与新UI分别验收。

已按 figma-design-to-code 实际 get_design_context 并查看五张原图；文件 `CreMqit00K1MAJju69YoOv`，摘要见 `figma-read.json`。

| Figma节点 | 真实设计内容 |
|---|---|
| 95:1408 | 按住录音，松开发送；左滑取消、上滑锁定；实时波形/时长 |
| 173:1952 | 锁定后主“停止录音”，次“发送语音”“取消录音” |
| 173:2012 | 预览主“发送语音”，次“试听”“放弃录音”，尚未发送 |
| 173:2072 | 正在试听，已播/总时长，次动作“暂停试听” |
| 177:1982 | 中断后保留预览；“录音已暂停，请试听后再发送。语音尚未发送，不会自动继续录音。” |

共同依据为根 `DESIGN_SPEC.md:13–37`、`COPY_GLOSSARY.md:3–17/253–261`、`PAGE_STATE_MATRIX.md:15`、`FIGMA_HANDOFF.md` step181/187。设计组件历史R2/C2注释不是新协议。示例联系人、00:12、消息和静态波形不进产品；只移植面板，不复制React/390×844绝对坐标或替换原导航。

## 精确4文件边界

| 生产文件 | 视觉接线 | 保留边界 |
|---|---|---|
| `Tinodios/widgets/SendMessageBar.xib` | audioView重排标题/波形/说明/文字动作；52pt最小高度，可滚动内容和约束/outlet | 原输入、附件、回复编辑预览、peer-disabled、send长按recognizer/action身份 |
| `Tinodios/widgets/SendMessageBar.swift` | 纯呈现状态、主题、动态字号、VoiceOver、中文；面板测量/收展、手势坐标稳定；专用语音发送仅路由stopAndSend | 原动作、60pt滑动阈值、方向互斥、松开发送，不加权限/文件操作 |
| `Tinodios/MessageViewController+SendMessageBarDelegate.swift` | 已有voiceUI门禁后的真实时长/VLC time/状态/权限结果传面板 | start/stopForPreview/player.play/pause/提交入口和owner/recorder校验不变 |
| `Tinodios/MessageViewController.swift` | 中断恢复结果映射持续提示；必要面板高度刷新与非模态遮罩 | voiceScope/voiceUI/retire/discard/sendAudioAttachment/Data清理不改；不修改消息inset算法 |

`Utils.swift`中的ClawTheme、MediaRecorder、Keyboard扩展只读复用。若运行反例需要改键盘算法，先报具体依赖，不借视觉重写聊天布局。

## 真实状态与动作映射

| 真实触发/源码位置 | 面板呈现与行为 |
|---|---|
| Bar187–241，空输入按住 | 原话筒入口；读屏补完整松开发送/左滑取消/上滑锁定；不把tap改成开始 |
| Delegate253–261，requesting/granted/denied | 中性提示、不计时；grant“已允许使用麦克风，请再次按住录音”；绝不从回调启动 |
| Delegate225–240，actual didStart/update | 按住录音，真实timer/采样；开始成功才呈现录制 |
| Bar227–234/542–552，上滑锁定 | 主停止、次发送/取消。停止只进入预览；发送由原提交判断；取消只本次未交录音 |
| Delegate229–234，actual didFinish | 已完成/真实总时长与preview，发送/试听/放弃，明确尚未发送 |
| Delegate265–295，VLC playing && isPlaying | 正在试听、实际已播/总时长；暂停试听；不按点击乐观显示成功 |
| VC802–813，paused | 预览保留；再次试听沿同一player/时间，不回零、不称重新录音 |
| VLC ended/stopped | 预览保留；下一次可按原逻辑从头试听 |
| VC354–368/778–824，inactive/interruption | 同owner同页保留停止后的预览；回前台显示177:1982完整提示；待授权只取消意图 |
| VC836–865，短于3秒/不可读/本地拒绝 | 保留可处理预览和准确原因；不静默隐藏，不写服务器已拒绝或已发送 |
| submitRecordedAudio返回true | 关闭本次面板，原上传/消息UI接续；只代表Data被原入口接收，不是ACK。源文件由4f052负责 |
| 离页/退役 | 原lease清理，当前面板隐藏；不借新Cache owner，不留A账号波形/时长 |

允许增加纯展示细分（按住、锁定、预览、试听、试听暂停、中断预览、提示），不增加持久状态。现longPaused混合停止/暂停/播放结束，须从已有真实回调区分说明。真实VLC time由回调读取，不用动画timer假装实际播放进度。

## 布局与可访问性

1. **沿inputAccessoryView。** VC164–168/391–397已有flexibleHeight；Bar269–287用XIB闭合约束。不能present新录音VC：VC772–775会合法丢弃lease。面板在accessory内扩展，遮罩如需要只能是当前页非模态sibling，不变成新录音owner，不透传消息区误触。
2. **自适应高度。** 当前XIB audioView `4PB-Gh-5Iz`的`sCc-uV-pp7`=40，运行Bar525–526改为按钮高度+8。新布局按内容拟合；动作最小52pt，大字可增高，窄屏/横屏内部滚动且所有关键动作可到达，不能缩字裁切。
3. **稳定长按坐标。** 当前began用bar本地坐标，changed减起点（Bar192–237）；面板扩大/键盘收起会移动坐标系。计划用同一window坐标计算位移，保留recognizer/mic对象、-60阈值和互斥方向。不得因布局合成lock/delete，必须实际手势验证。
4. **安全区只算一次。** XIB root `UC5-i1-la2`，底链preview→audio→input→peerDisabled→safeArea.bottom（358–391）应闭合。VC614–628读取实际accessory高度；Keyboard26–56已使用系统frame与accessory项。不要另加keyboardHeight/home-indicator常量。测无/有/外接键盘、旋转、消息锚点与重复空白。
5. **保留文字流。** hidden恢复输入、附件和pending reply/edit；正文四行上限/组合态/滚动沿原方法。停止/试听不清待回复编辑、不强开键盘；有效录音仍沿现resignFirstResponder。
6. **Dynamic Type/深色。** 用Utils29–64/100–120动态色和UIFontMetrics，标题20/动作16/说明14且可换行。Bar405–409当前仅audio隐藏时刷新字号，需覆盖活动面板。更新动态CGColor。锁定主“停止录音”，预览/试听主“发送语音”，最多一个强主动作。
7. **VoiceOver。** Bar327–330的“暂停录音”实际pausePlayback，改“暂停试听”；“删除录音”改准确“放弃录音”。真实时长可读、不每30ms抢读；波形不拆成大量元素。状态切换适量announcement与稳定焦点；若启遮罩，消息区暂退出可访问序列，关闭恢复。首次授权完成提示再次按住，不假装录音中。
8. 不改音频route/通话/后台录音/录音时长规则或权限政策。手势用户意图与已封文件责任不能由视觉组件重建。

## 审计中新发现，必须独立先修

**VOICE-RESET-01/P1：** Bar92的`sendButtonConstrains:CGPoint!`仅longPressed.began193赋值；resetRecordingState462→resetRecordingGesture470/471直接解包。VC首次viewWillDisappear772→discardVoiceRecording826/833只要view已加载就reset，即使从未录音。首次进入聊天直接返回是完整源码反例；此次未Mac动态复现，CI22身份导航不覆盖聊天返回。

总控已核准独立单文件修复：snapshot可选；未开始手势时保留现有约束，有snapshot才恢复且消费清空；仍复位slider/size/record flags，不能用CGPoint.zero冒充初始布局；重复reset/下一gesture不覆盖新布局。真实XIB/实际方法测试范围另外明确，不能混进本视觉提交。此依赖已获准，待实施，不把新UI开始当已关闭。

## 验收与未验边界

- Windows：XIB结构/outlet/action闭合，原recognizer与动作对照，4文件diff，Recorder/Cache/Interactor/SDK/DB不变，无示例时长/假波形数据。这些只叫静态检查。
- Mac：完整App/XIB编译，保留当前210+导航3原选择（RESET新增方法后按真实计数更新），不得删断言。Recorder8是AV边界注入的实际类测试，不是XIB/麦克风/页面测试。
- UI矩阵：浅/深色、默认/辅助大字、窄屏/横屏；按住/锁定/停止/试听/暂停/结束/放弃；面板收展与手势阈值；输入法/回复编辑/附件返回/外接键盘；首次授权/拒绝/中断保留/离页退役；短录音/读失败。原PNG与几何并存，断言实际hittable/keyboard/控件状态，截图不代替动作验收。
- 当前真实App导航仅离线身份流程，不能绕过登录进入聊天；没有获准添加生产录音测试开关。完整聊天自动化需要合法合成会话，或另批准的真实组件宿主依赖接线。未具备时明确NOT_RUN，不写复制Boolean/镜像控件充当真实消费者。
- 系统麦克风、声音/播放、中断/route、设备VoiceOver和跨端真实发送单列待验。本报告或CI22不能关闭这些验收。

下一步由总控依据CI22与独立复核冻结视觉任务。当前不提供新包、不重封累计补丁；未来视觉回退仅对应独立视觉提交，不能回退账号隔离/录音可靠性/文件清理。
