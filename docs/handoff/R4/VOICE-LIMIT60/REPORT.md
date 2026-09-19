# R4-VOICE-LIMIT60：独立四源候选

源码父基线：`0ea19847e3b043bc14bfb046d2e1809cf92134e6`。直接父提交为只读准备 `f537df8808656e6de2fec6811b1400e7e574c714`，两者生产相同。本提交只含任务包指定四个生产文件、两个已接线测试文件与本目录文档；无 push、dispatch、原生构建或设备操作。

归因更正：用户原话确认语音限制 60 秒；“到限进入试听、不自动发送”由总控在本轮说明并冻结，不称用户逐项确认。f537 只读时点报告保留。其后视觉已由总控另发 SIMPLE60/连续秒数宽度方案，本补丁不改 Bar/XIB/普通 AU 视觉或历史。

## 改动与原问题

- Cache 工厂使用 `MediaRecorder.recordingLimitMilliseconds = 60_000`；真实 AV 引擎调用 `record(forDuration: 60)`。MediaRecorder 默认同值，每次开始捕获本次 activeDurationLimit，不因后改配置误判在途录制。VC 移除未被使用的旧 600_000 常量。
- 原 0ea 中 Bar 仍 recordingStarted、引擎已停但 finish 尚未派到主线程时，旧 ended → stopAndSend → sendAudioAttachment 可直接提交；旧 recordUpdate 也会把已停引擎先转 preview，丢弃未送达的失败 flag。
- 新 `deferSubmissionForRecordingCompletion()` 只对仍 recording 的本次状态作拦截。若引擎已经停止，即使 currentTime=0、最后样本59.x，也阻断旧释放提交，停止采样 timer，**保留原 engine/delegate 等真实成功或失败回调**，不提前伪造成功预览。
- 引擎仍 recording 且原实际录制时间达到本次限额时，先幂等 stopForPreview 并拒绝该次提交。已建立 preview 后新的明确发送返回原路径。成功 flag 本身不证明到限；只有实际 elapsed 达本次 limit 才显示“已达60秒，试听后发送”。
- 完成先到时原 Bar.recordingDidStop 设置 recordingStarted=false/audioLocked=true，原 longPressed 开头 guard 挡同次旧 ended；未修改 Bar/XIB。未知停止继续等回调，失败走原 failRecording，不因拦误发变成成功。
- 最终 Recording.duration 仍由实际 elapsed ×1000 产生，不强行填 60000、不截断文件或 metadata。旧 >60 秒 AU 格式化/读取、C3、DB、SDK、上传寿命、原 owner/权限均未改。

已停的 currentTime=0 是本反例的重要前提。相关官方入口：[AVAudioRecorder.currentTime](https://developer.apple.com/documentation/avfaudio/avaudiorecorder/currenttime)；独立后台报告 `02e26b2514134ac6f06579ae6690b9ecdcb7ea7a` 的 IOS-VOICE-LIMIT60-BOUNDARY-REVIEW.md 保留其官方取证。此处不把 Apple 属性说明提升为本候选已在真实设备复现。

## 验证与原生接线

Windows 实际完成：

1. `check-source.py` 对固定 0ea 四个源码缺口判据为 false、候选为 true；这是**源码反例/接线检查，不是 Swift 红绿执行**。检查六路径唯一范围、保留原 8 个 MediaRecorder +6 个 VoiceLayout 方法正文、Bar/XIB/Interactor/普通 AU/PBX/selector/Pods 原样。
2. `Scripts/ci/run_static_policies.py` 44/44 通过，报告 source-policies.json。
3. `git diff --check` 通过。source-checks.json 分别记录 raw/LF SHA 与 Git clean blob，不把 Windows 原字节当 Git 原字节。

原有两个 test class 已在 PBX/selector 中，无新增接线和时限变化。新增 5 方法：

| 所属既有 class | 方法 |
|---|---|
| MediaRecorderLifecycleTests | testEngineLimitUsesSixtySecondsAndFreshTakeResetsBudget |
| 同上 | testStoppedEngineWaitsForAuthoritativeSuccessOrFailure |
| 同上 | testActiveEngineAtLimitStopsOnceAndAllowsExplicitPreviewSubmission |
| VoiceLayoutTests | testLimitFinishAndReleaseOrderingUseOriginalNibAndSubmissionDispatch |
| 同上 | testNormalReleaseAndLockedLimitKeepExplicitSendDistinct |

前 3 个调用生产 MediaRecorder，注入 AV session/engine 边界，使用真实临时文件；测试 engine 自动停止后 currentTime=0/最后样本59.875、成功/失败 flag 延迟、重复终结、预算重置及数据仍真实。原 record(forDuration:) fixture 现在记录传入参数，原 8 方法断言不删。

后 2 个在现 App-hosted target 使用实际原 XIB、实际 Bar.longPressed、实际 MessageVC.sendMessageBar(recordAudio:) 的 stopAndSend 分支和同一生产 MediaRecorder。录音 start 由注入 engine 驱动，原 Bar 的 .start 在匿名 VC 被原 owner 门禁拒绝；测试不造登录。完成 UI 桥接调用原 recordingDidStart/Stop/preview，现有提交边界 override 只记录实际 prepareSubmission 的 Data/duration，并调用原 didSubmit；**不代表完整 voiceUI owner gate、真实麦克风、真实发送/上传/服务器 ACK**。两种回调先后均经过原 Bar/audioLocked，不用连续直接调用两次 stopAndSend 伪装旧松手。

预期由 313 native +3 导航变为 **318 native +3 导航**，目前全部新增方法 **NOT_RUN**。旧 313 是当前累计候选数量，不声称 B02 已获 Mac 结果。CI43 外部依赖失败仍由总控保留；没有自行重跑或改依赖。

## 准确限制

- 引擎属性读取与停止并非物理原子；实际 AVAudioRecorder 60 秒文件长度、编码收尾和真手势时序仍需 Mac/设备验收。受控 engine 不能证明物理文件绝不超过任意亚毫秒。
- 如引擎已停且完成回调尚未来，保留等待状态与失败责任；没有凭 elapsed/已停就推断成功。平台永不回调的故障不在本次新增 watchdog 范围，用户离页/退出仍按原 lease 退休清理。
- 明确手动停止/发送原有 stopForPreview 的编码收尾行为不扩改。本次解决到限旧释放误发与 timer 抢先成功；不宣称普通 AU 播放可靠性、全部声音设备或格式安全已完成。

## 审查、安装和回退

此候选只供总控/后台按固定 SHA 源审；总控决定沿授权验证分支的累计 CI，当前不产安装包。直接父 f537 是文档，生产父0ea；后继如需恢复使用本候选原 Git diff，不覆盖 SharedUtils/私有资源/已有包。回退只对本固定提交 `git revert <candidate SHA>`（先确认工作树与新后继），禁止 reset/clean；录音会恢复旧限额和原问题，不能当作已修版本交付。
