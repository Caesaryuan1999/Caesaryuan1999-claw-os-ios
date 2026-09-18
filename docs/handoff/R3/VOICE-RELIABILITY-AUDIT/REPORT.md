# VOICE 可靠性只读调查与最小单元提案

源码冻结候选：af6d85c81893cb689607fdeb0b9f266c8cc24d25；生产仍与 e6 一致。只新增本报告，不实施方案，不改 Cache/录音/UI/测试。CI18 仅 SDK41通过，storage/VLC/导航未运行；CI19由总控控制，不能把探针结果当作录音页面验证。

## 范围与证据等级

最初5源为 SendMessageBar.swift/xib、MessageViewController+SendMessageBarDelegate.swift、MediaRecorder.swift、MessageViewController.swift（第5份用于真实inputAccessory/发送路由）；总控追加授权后只读 Cache.swift 与 MessageViewController+Keyboard.swift。无额外主题/Interactor/SDK实现审查，无私有配置读取。仅对全App做录音调用文件名枚举：Cache.mediaRecorder / MediaRecorder创建命中 Cache 与该Delegate两文件；未借此扩展审计其他实现。另只读工程的target/source配置用于测试接线可行性。

以下“源码确证”指存在可按指定顺序执行的代码路径，尚无本轮麦克风、录音、音频播放、账号切换设备动态证据；不声称已经实际泄露录音或错误发送到新账号。

## 真实调用链与问题

| 单元 | 实际路径及触发顺序 | 确证范围 / 未验证部分 |
| --- | --- | --- |
| 首次授权后意图已结束仍开始 | Bar195–220：长按began→显示short→Delegate63–65→Recorder79–91。undetermined先didFail(permissionRequested)，Delegate221–226隐藏栏；系统回调允许后Recorder85直接startRecording。期间松手→Delegate66–67→Recorder135–136因recordFileURL=nil直接return；回调仍可启动 | 缺取消/原请求校验是源码确定。授权弹窗期间真实手势事件与界面表现未设备执行；即使用户不再按住，回调仍具有独立start入口 |
| 初始化失败后nil解引用 | Recorder104先设latestRecordName；107创建AVAudioRecorder抛错后111–114只通知/日志并return，audioRecorder仍nil（首次尝试）。其后stop仅检查recordFileURL非nil，在138读取IUO.currentTime；pause155–156亦仅检查URL；isRecording73直接解引用 | 可构造factory/AV初始化失败→stop/pause/isRecording的源码反例。未在当前Mac制造真实设备错误。第二次初始化失败还可能保留前次recorder，与新文件名不一致 |
| 授权/初始化错误后的UI状态 | Bar.showAudioBar(hidden)不清audioLocked，Delegate失败只调用该方法；locked状态后错误可留下内部锁定标记。didStartRecording207–208为空，展示由按钮动作先切换 | 显示/内部状态不同步可由源码确认；不得只换按钮文案而声称失败恢复完善 |
| 录音跨SDK生命周期保留 | Cache16保有单实例；205–215创建/获取不绑定owner。invalidate61–89两分支只失效SDK/helper等，不退休或清空mediaRecorderInstance。Delegate动作63–92每次重新取全局Cache.mediaRecorder，没有捕获本次recorder/UID/SDK | Cache失效后仍可取同一个录音对象是源码事实；现有计时器/授权回调也未受Cache generation约束。是否通过现有页面/Interactor变成跨账号发送，本轮未验证，不能直接宣称已发送给B |
| 页面/应用生命周期没有录音终止 | MessageVC292–304观察willResignActive，345–348仅interactor.cleanup/leaveTopic；deinit361–366调用同方法。该类无viewWillDisappear/viewDidDisappear录音处理；计时器/permission closure位于全局recorder，delegate为weak | 源码中页面停止逻辑未接录音。后台是否被AVAudioSession自动中断不是应用保证；设备/音频路由结果未运行 |
| 旧播放器回调及暂停语义 | Delegate82–87每次试听新建VLCMediaPlayer，90–92暂停当前对象；231–249不核player是否仍等于currentAudioPlayer，旧stop/ended可把已隐藏栏恢复longPaused；timeChanged254–255为空 | 源码确定不能承诺暂停后续播、标题真实位置或旧回调隔离；实际VLC通知时序未运行。与网络视频探针属于不同消费者 |
| 原音频消息入口 | Delegate66–71读取recordURL和duration!→MessageVC748–771；Data读取，小内容Drafty.insertAudio→sendMessage，大内容uploadAudio | 保留真实消息/上传/C3链，不从录音外观改发送语义。<3000ms（VC152/750）和读取失败758–761静默return，栏已隐藏的恢复仍属现存边界，不假报成功 |

## 建议冻结一个可靠性单元：VOICE-LIFECYCLE-01

优先处理权限意图、初始化失败和原owner/页面生命周期；保持视觉另外提交。最小完整边界预计 **5生产文件**，第5只是原Bar复位原语，不是新版面板。少于此会漏掉全局缓存、页面离开，或保留audioLocked错误状态：

1. **MediaRecorder.swift**：实际状态/attempt、可空底层recorder、权限依赖与recorder工厂的窄注入；初始化成功才公布本次URL/实例，失败清理本次未完成状态；stop/pause/isRecording/重复取消对无recorder安全。首次系统授权只完成授权，允许回调仅通知“已允许麦克风，请再次按住录音”，绝不调用startRecording；下一次真实按住且当前permission granted才申请开始。拒绝提供“未开启麦克风权限，可在系统设置中开启”，不冒充未知错误；请求中不作为录音成功或通用失败。
2. **Cache.swift**：单一原owner/UID/generation与录音lease绑定，原子取得/退休原对象；失效两个分支都要封闭仍存在的录音lease。旧调用者不再通过无条件getter获取后来账号的新对象。锁内只解绑/标记退休与捕获旧对象，绝不在SDK/Cache锁内同步等main或执行AV/UI回调；退出锁后对捕获旧对象安排主线程停止/清理。不新增第二套账号存储。
3. **MessageViewController+SendMessageBarDelegate.swift**：在start时捕获本页面、原owner与本次recorder/attempt，后续stop/send/delete/permission/recording回调只用该捕获；不再动作中重取Cache.mediaRecorder。原owner与attempt失效后不更新新界面、不向新账号提交、不删除后来录音。移除duration强制解包；成功取到本次完整结果后仍调用现有sendAudioAttachment。权限完成只提示再次按住，不发送。播放器回调必须匹配当前实例和仍有效预览；停止/取消时先解绑旧delegate再停旧player，防晚通知重新开栏。
4. **MessageViewController.swift**：保存本页面录音lease，明确处理willResignActive、页面离开与deinit。最小保守规则建议：这些事件取消待授权意图、停止正在采集，并放弃本页面尚未提交录音/试听；不自动发送，不处理已进入原上传/发送链的数据。只触发同一个幂等结束入口，不清全局任意录音。权限弹窗本身导致inactive也不能在返回后自动录音。这一放弃策略需由总控冻结，再提供准确页面提示；不把“保留预览”或跨页面恢复默认为已有功能。
5. **SendMessageBar.swift**：一个无delegate副作用的resetRecordingPresentation入口，清audioLocked、隐藏手势辅助、复位旧移动约束（存在才取）、波形与现有按钮；生命周期/失败调用它，不能调用deleteRecording来间接递归业务动作。仅修原状态复位，不在本提交换Figma布局/按钮层级。

同一结束入口的语义应先冻结为 cancelIntent / stopForPreview / finishForSend / discard，不另建消息状态。stopForPreview保留本次文件及有效时长，重复stop不重算/清空已有结果；finishForSend不再次请求权限、不读取其他attempt。discard和生命周期清理只操作该lease自己的未提交文件。旧回调与新attempt交错必须比较原对象/attempt，不能仅靠一个Boolean。

### 锁与线程约束

复用现有SDK→Cache顺序。任何AV操作/播放器stop/Toast/布局不得持这两把锁同步等main。退休须先同步使本lease不再接收start/result，再在锁外对原对象执行物理停止；允许旧清理排队，但绝不能重新绑定新对象。底层工厂失败或准备途中发生退休后，完成准备的一方须再次核本次lease再record，不得在过期attempt开始采集。MediaRecorder自己的状态同步不可反向调用Cache/SDK；UI展示在main按原lease复验后才落地。这是待实现约束，不声称现有源码满足。

Cache失效通过旧对象退休关闭入口后，异步清理完成也不能改新的Cache slot。为了测试而注入当前slot判断的边界，必须明确不等价于运行真实Cache/页面，不能把假owner Boolean当全账号隔离验收。

## 原生测试必须运行实际类，而不是复制门禁

现有TinodiosUITests是Xcode UI-testing runner（pbxproj746），不能凭名字当成App hosted unit target。当前MediaRecorder.swift仅在主App Sources（1039），未直接进入该测试target。

可行最小接线：
- 同一个生产MediaRecorder.swift增加到既有TinodiosUITests Sources（不是复制文件）；新增一个MediaRecorderLifecycleTests.swift；现有CI脚本只追加该class selector，原200/native和导航3不删。
- MediaRecorder窄依赖协议/工厂定义在同生产文件。默认适配仍是真实AVAudioSession/AVAudioRecorder；测试替换的只有系统permission回调、recorder工厂及底层对象。测试驱动实际MediaRecorder.start/stop/pause/retire和真实delegate回调，绝不重写状态判断。
- 该生产文件目前以Cache.log形成App模块依赖。可将固定事件logger作为初始化依赖由Cache传入，使实际类可直接编译进runner；无需编译/伪造整个Cache/Firebase/App。测试不输出错误文本/录音路径；日志替身不实现业务门禁。
- 原owner lease若放同生产文件，使用实际Tinode/SqlStore合成账号fixture测试生命周期；当前Cache slot闭包可以受控注入，但报告必须区分“真实生产lease/recorder”与“实际Cache/UI消费者未运行”。Cache两分支与页面调用线另做精确源码审查；不能据此称完整UIKit退出场景通过。

建议 **8个有意义的方法**，冻结后按最终实际方法数统计，而不是目前已通过：
1. 首次undetermined→允许回调：工厂/record调用0；下一次真实start（granted）才开始。
2. 待授权期间cancel/retire/离页后晚允许：不开始、不回调新delegate/新attempt；拒绝/再次按住路径可恢复。
3. 第一次工厂抛错→isRecording/stop/pause/discard均不崩，未公布文件；之后合法start成功。
4. setCategory/setActive/prepare/record=false各失败：无假didStart、无遗留timer/半成品可发送；原错误分类安全可观测。
5. 同一生产lease的A退休→B新lease：A晚permission/计时/finish不影响B；旧清理只处理A文件。
6. inactive/页面结束调用共同结束入口两次：只停止/清理本次，zero send；再次按住新attempt正常。
7. 正常stopForPreview、重复stop、发送取结果：真实类保留第一次有效时长/文件，不把预览当已发送。
8. 放弃本次只删所属合成文件，其他文件/后来attempt不受影响；当前player归属的消费者接线单独核实，不能用recorder测试冒充VLC播放验证。

这些是可执行原生测试方案，尚未实现或运行；注入系统边界并不证明真实麦克风弹窗/后台录音。实际设备还需许可未决定/拒绝/撤销、音频中断、锁屏/后台、录音后退出/换号和真实发送验收。暂停后继续试听行为若要求修复，应在本可靠性单元范围冻结时明确，不只换标签。

## 视觉独立单元：仍建议3生产文件

后续另提交SendMessageBar.swift/xib + MessageViewController+SendMessageBarDelegate.swift。实际get_design_context及返回原截图已读 [173:1952锁定](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=173-1952)、[173:2012预览](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=173-2012)、[173:2072试听](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=173-2072)。设计00:12/00:04与会话样例不植入。

真实手势不变：松开发送、左滑取消、上滑锁定（Bar194–259）。锁定显示“停止录音/发送语音/取消录音”；预览显示“发送语音/试听/放弃录音”；播放显示“发送语音/暂停试听/放弃录音”，不得把pauseRecording与playbackPause混淆。当前图标32pt初值、运行44pt；改52pt最小文字按钮，大字可增长；真实record/player时间回调才显示进度，不编计时器进度。

保留原inputAccessory（VC163–168、369–373）；Bar在音频态会resignFirstResponder，XIB有safeArea底部约束。VC599–600按accessory高度避让；Keyboard26–57处理键盘overlap。新长面板必须自适应内容高度，不能沿40/56pt固定栏塞文字；安全区只计一次，短录按压位置/输入草稿/回复预览/键盘恢复保留。ClawTheme动态色和scaled字体沿用，大字换行与VoiceOver逐动作顺序；不在30ms振幅回调连续公告。不把Figma遮罩复制为新的导航或自动退出逻辑。

现有3个登录导航测试不覆盖已登录聊天/麦克风；本次没有新增布局代码，不声称录音三状态已落地或交互通过。

## 固定源SHA-256

| 文件 | 冻结Git blob内容SHA-256 |
| --- | --- |
| Tinodios/widgets/SendMessageBar.swift | 9f8704249a3a6a14dbb6a2d9b4a79979f1f2a6d55479feacf907559fd68fe424 |
| Tinodios/widgets/SendMessageBar.xib | 85480419186e22fe1180f24f959c5a59402ac4788fc11bc4b643022955c10c3f |
| Tinodios/MessageViewController+SendMessageBarDelegate.swift | b539812ff8d89afc42679ad915a123da06303ecdf70473d8503429c41ecc1429 |
| Tinodios/MediaRecorder.swift | 6320e35c30e3f6f498a0a0d77907d5d7ff0672877e7688a65fb74901fe932842 |
| Tinodios/MessageViewController.swift | ce86b8a188ae24acf68b9b16d0d8cbbd923499ced9d920602aa63a963ab865c2 |
| Tinodios/Cache.swift | 2070083d2deeb7bf65e7a4a2d8658ec3f4b694c2806337012cecf8ca86291935 |
| Tinodios/MessageViewController+Keyboard.swift | ebf0368ad24cedfe785bc2a72fce910391a977176f5d34fdc2c7a2ae147f409c |
