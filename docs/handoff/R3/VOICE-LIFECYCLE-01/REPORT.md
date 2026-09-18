# VOICE-LIFECYCLE-01

基线 63b8fe4ae4092311745a5159ea523e90ed82857d；本单元 6 生产 + 3 测试/接线。CI20/CI21 是独立探针宿主问题，不是本单元执行证据。VOICE 实际 Swift/Mac/麦克风/页面运行均待验证。

## 真实问题及本次边界

旧 MediaRecorder 在首次 permission 回调中直接 startRecording，未绑定原按住意图；latestRecordName 在 AVAudioRecorder 构造前赋值，构造失败后 IUO 可被后续停止/暂停读取。页面动态取 Cache.mediaRecorder 共 10 处，发送时强解包 duration；不足原 3 秒和文件读取失败静默返回。red-source.json 只记录源码确证，不伪称 Windows Swift 红测。

1. MediaRecorder.swift：一个录音 lease，原 owner 门禁 + 同步 retirement admission；AV、文件操作、delegate 在主线程且不在 Cache/SDK/admission 锁内。首次授权只提示再次按住，回调不启动。初始化全失败路径清理部分文件与 session；首次 stop 记录时长/URL/波形，重复 stop 幂等。prepareSubmission 是生产实际读取入口，短录音/读取失败保留 preview。didSubmit 仅在原消息/上传入口接收后转移文件所有权，退出不删已转移文件。
2. Cache.swift：仅为捕获原 SDK 创建 recorder/helper；退休标记在原同步锁内、实际 AV stop/删除/页面回调在释放锁后。旧 page 释放旧 lease 不会替换或销毁新 lease。没有重写 Cache 其他职责。
3. MessageViewController+SendMessageBarDelegate.swift：同一 lease、topic 和播放器对象才消费回调；授权结果/错误恢复可见。暂停后沿原 player 继续；结束/失败可重建同一本地媒体。仅 observed playing 状态触发播放 UI，旧 callback 不修改新录音。
4. MessageViewController.swift：原 SDK/UID/Cache 世代/page/topic 门禁。inactive/interruption 停止采集及试听但保留 preview，回前台提示“录音已暂停，请试听后再发送”；离页/deinit/退出只放弃未交出的本次录音。提交小于 3 秒/读取失败/原入口拒绝均可恢复。录音授权、播放、UI 和网络入口不在 Cache/SDK gate 中执行。
5. widgets/SendMessageBar.swift：仅状态接线，无 xib/视觉修改。实际录音开始才出现录音状态；发送、试听不提前隐藏或显示成功；保留原手势（松开发送/左滑取消/上滑锁定）及 inputAccessory 约束。
6. MessageInteractor.swift：新增捕获原 owner/UID/generation/topic 的音频接收入口；内联真实 Drafty→原 topic.publish，OOB 仍既有 msgDraft/upload/msgReady/syncOne 链，传捕获 helper/baseURL。返回 true 仅表示已交原消息/上传入口，不表示持久成功/服务端 ACK/送达。音频进度/完成不找后来账号的页面；其他媒体的原消费者/私有 Drafty helper 与原 sendMessage 保留。C3/DB/AUTH/wire 均不改。

AV 已进入的同步调用和另一线程 retirement 存在物理执行重叠；retirement 立即关闭后续 admission/回调，排到主线程完成停止，不宣称能撤销已进入的系统调用。实际系统麦克风授权、后台行为、音频中断和完整 UIKit 手势需设备/模拟器专项验收。

## 8 组原生测试准备

MediaRecorderLifecycleTests 直接编译生产 MediaRecorder.swift。仅 AV/session 边界注入，文件读写是实际 UUID 临时目录；不是复制 Boolean 状态机。八方法覆盖：

- 授权迟到不开始、取消意图/retired 回调及拒绝权限。
- factory/prepare/session/record 四种失败，nil 安全和部分文件清理。
- 重复停止保留首次 URL、时长、波形、一次停止。
- preparation 中退休阻断 record/delegate。
- 停止采集后保留 preview、不会自动 restart。
- 旧 engine/失效 owner 的晚回调不改新 take。
- 未提交本地文件删除、已交出文件保留。
- 过短与实际读取失败保留 preview，恢复读取后同 take 可提交。

owner slot 是生产注入闭包的受控替代；未执行真实 Cache/SDK→UIKit 的端到端切号。inactive 调用接线、上传/页面/播放器身份消费用源码复核，不能把这 8 组称系统权限或完整录音发送成功。

pbxproj 仅将真实 Recorder 和新测试加入现有 UI runner；原 4 VLC 方法仍只在独立 host。CI 多一个 MediaRecorderLifecycleTests selector，原所有 selector/测试断言保留。期望 210 原生 = SDK 43 + UI runner 163 + host VLC 4；导航 3 单列。

## AUDIO 适配器继承

成功分支仍使用 srvUrl，初始仍 mid。仅增加显式原 owner baseURL，禁止成功回调重新借后来 Cache。既有 CI 提取器绑定当前 HEAD 整文件 blob、唯一 case.audio、完整真实 helper 和固定 helper SHA；允许的新增实参精确为 baseURL: audioBase。旧 red blob 957739e19a32e8de9f5e5f63b424f78e090cf29e、旧 callback 原字节及 SDK 两个真实 Drafty 方法保留。本层仍“生产分支源码适配 + 真实 Drafty”，不是完整 UIKit completion 或服务端上传接收。

## 本地检查 / 未运行

- 44 既有 source-policy 脚本通过，未改其测试规则。
- 26 新源码/工程/方法计数检查通过。
- 实际 CI 提取器在隔离真实 Git fixture 运行 4 例：当前错 ref 注入红、当前绿、重复分支拒绝、dirty source 拒绝；未改原 AUDIO 红报告。
- bash -n、git diff --check 通过。
- Swift/8 方法/实际 permission、麦克风、VLC 音频试听、上传与 UIKit 切号：NOT_RUN。等待固定累计候选 Mac 原生执行后更新结果，不能把当前期望 210 当通过。

WIP-CI19/WIP-CI20 只是本地保全，不纳入正式源提交。无生产私有配置、签名、真实服务资源变更；未推送。
