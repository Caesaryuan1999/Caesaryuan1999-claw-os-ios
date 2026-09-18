# VOICE-UI-01 — 真实录音状态面板

起点 `0a7ba4470318e72064fe753ad2434b8a11329e72`，独占 `work/r3-20260918-ios` / `codex/r3-20260918-ios`。开始 tracked clean；原 artifacts、VOICE WIP-CI19/20 保全目录不改。仅以下四个生产文件；未修改测试、CI、PBX、Recorder、Cache、Interactor、SDK、DB、协议或文件所有权。

| 文件 | 实际变更 |
|---|---|
| Tinodios/widgets/SendMessageBar.swift | 纯呈现状态、真实时长、52pt文字动作、ClawTheme/动态字/读屏；按内容测量并限制面板高度，同一个window计算原手势位移 |
| Tinodios/widgets/SendMessageBar.xib | audioView内竖向stack/scroll内容，标题、真实波形、说明、停止/发送/试听/暂停/放弃；原输入/回复/附件/长按对象保持 |
| Tinodios/MessageViewController+SendMessageBarDelegate.swift | 原voiceUI门禁后的录音duration/amplitude与实际VLC time进入面板；权限及Recorder/播放器动作分派逐字未改 |
| Tinodios/MessageViewController.swift | 当前页非模态遮罩、可用高度、中断提示；原owner/retire/discard/提交方法逐字未改 |

## 设计与动作

已实际调用 Figma get_design_context 并查看 `CreMqit00K1MAJju69YoOv` 的 95:1408、173:1952、173:2012、173:2072、177:1982；详细来源保留在前置 `VOICE-UI-PLAN`，计划提交1c88c771。使用 R3.D1 / 现有 ClawTheme，不复制设计示例人物、时间或波形。设计面板映射到原 inputAccessoryView，没有新模态录音页。

- 按住：实际didStart之后显示“正在录音”，真实采样/时长；松开发送、左滑取消、上滑锁定沿原60pt阈值和互斥方向。按住期间原话筒/recognizer保留；空白脚部给原活动按钮留位。
- 锁定：主“停止录音”，次“发送语音”“取消录音”。停止沿stopForPreview；发送只进入原stopAndSend，按钮不宣告服务器成功。
- 完成：主“发送语音”，次“试听”“放弃录音”，说明语音尚未发送。放弃仍只清本次未提交lease。
- 试听：由原播放器playing/isPlaying确认，显示真实VLC已播/录音总时长；“暂停试听”。暂停后“继续试听”仍使用原播放器；结束后保留原采样预览，不将波形重置为空。
- 中断：现有同owner同页有效预览上持续显示“录音已暂停，请试听后再发送。语音尚未发送，不会自动继续录音。”；首次授权仍只提示再次按住，没有回调auto-start。

短于原3秒、读取失败、本地拒绝等仍由原VC提示并保留预览；上传失败沿已封32f的“录音上传未完成，请重新录制后发送。”，本批不增加重新上传功能。

## 布局边界

- stack中的五个文字动作最小52pt，优先级999用于UIStackView隐藏约束；动态字可增高，多行不缩字。标题20/说明14/动作16来自UIFontMetrics主题。深浅色使用语义色，背景blur改systemMaterial。
- 使用实际当前view可用高度，内部scroll溢出可滚动。原keyboard/inset算法、safeArea底链和pending reply/edit不改；只让原VC读取变化后的accessory实际高度。
- 手势起点和changed位置来自同一捕获window；窗口身份变更时不应用移动。原snapshot捕获/复位三个完整方法及原60pt阈值不变，避免因面板高度变化推导出滑动。
- 遮罩只覆盖当前聊天内容，导航保留；不会触发另一控制器的viewWillDisappear。显示期间消息列表退出读屏序列，关闭恢复；状态announcement只在状态动作处，实际计时更新不每帧抢读。波形不拆成读屏元素。
- 设计差异：保持iOS既有输入附件、长按原按钮及导航；受限高度使用内部滚动，不使用Figma固定390×844坐标。没有额外试听seek功能，也不修改VLC默认参数。

## 已执行检查

`rtk python -X utf8 -B docs/handoff/R3/VOICE-UI-01/check_source.py`：19项源码/XML检查通过，见source-checks.json。包括全部outlet/action闭合、唯一对象ID、五按钮52pt、完整原手势对象、普通输入/回复/附件子树逐字保留、capture/reset原3个固定SHA、完整原owner/提交方法比对。旧Objective-C selector longPressedWithSender映射实际Swift longPressed(sender:)；检查器明确记录该继承映射。

`rtk python -X utf8 -B Scripts/ci/run_static_policies.py --report ...`：44/44源策略通过，见static-policies.json。`git diff --check`通过。**均非Swift编译或XIB加载证据。** 本批没有镜像UI测试、演示数据、生产测试开关或新增原生方法。

原CI适配器的3个完整capture/reset方法哈希未变，现有选择和断言不改。下一精确候选仍预期44 SDK + 167 UIrunner + 4 VLC = **215原生**，真实身份导航3另列。RESET4的showAudioBar是明确的呈现spy，不能当新XIB/完整聊天页已运行。

总控刚确认 **CI23/0a7**：SDK44与UIrunner167全部通过（含Recorder8/RESET4）；VLC4有3通过/1 reopen-403-timeout失败，导航/打包/冷启动未运行。本次后继视觉代码不在CI23中。VLC观测通过也不是播放安全通过；其问题单独处理，不混本提交。

## 待验证与恢复

| 场景 | 本批证据 |
|---|---|
| 新App/XIB编译、实际面板加载 | NOT_RUN，待总控精确Mac候选 |
| 浅/深色、默认/辅助大字、窄屏/横屏、所有按钮可达 | 仅源码约束；实际布局/截图/VoiceOver NOT_RUN |
| 按住/松开/锁定/取消，同window坐标与面板扩展 | 源码路由；真实手势 NOT_RUN |
| 键盘/安全区/外接键盘、回复编辑/附件往返 | 原对象/算法保留；新面板交互 NOT_RUN |
| 首次授权/拒绝/中断/退役/账号切换 | 原可靠性方法及门禁保留；系统麦克风/设备事件 NOT_RUN |
| 真实声音采集/试听、跨端发送与服务端ACK | NOT_RUN；不据UI或原生计数宣称通过 |

不要以身份离线导航替代真实聊天验收，亦不得用生产后门进入合成聊天。Windows不能生成可安装iPhone IPA。总控后续Mac App ZIP/准确SHA才能用于同模拟器验证；签名、推送和真机仍另列。

本单元unit.patch仅四生产文件；累计安全包与正向恢复的实体哈希单列manifest，禁止混入SharedUtils、真实推送/签名、Pods、build、runtime、工具或证据巨量。应用在已保全且基线匹配的新树；不覆盖旧dirty原目录。视觉回退只反向撤回此单元，不回退VOICE-RESET、quote、录音lease及清理修复；不对不匹配/dirty工作区强制应用。
