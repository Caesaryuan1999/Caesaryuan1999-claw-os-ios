# VOICE-RESET-01 — 首次离页安全重置

## 问题与独立修复

生产问题基线 `785461b2006dbc0260472ebfe3cd36907fcbca27`；本提交父代码/文档为 `32f0ca4ef5a7aaaacce840e022a24b9b22b1fb6c`。工作树 `work/r3-20260918-ios`，分支 `codex/r3-20260918-ios`。原未跟踪工具与两个VOICE WIP目录保留，不push。

首次打开聊天后未录音直接返回：MessageViewController.viewWillDisappear → discardVoiceRecording → SendMessageBar.resetRecordingState → resetRecordingGesture。原 `sendButtonConstrains:CGPoint!` 只有longPressed.began赋值；reset无条件访问.x/.y，故nil路径成立。原785 blob与完整调用链保存在red-source-evidence.json。这是源码确证，不是Windows运行UIKit崩溃。

仅1生产文件 `Tinodios/widgets/SendMessageBar.swift`：

- 快照改为可选；手势开始调用实际capture方法保存当时约束。
- reset仅在存在原快照时恢复坐标，随即消费清空；没有快照时保留当前布局，不使用CGPoint.zero占位。
- slider隐藏与按钮尺寸复位仍执行；外层reset仍清recordingStarted/audioLocked并请求隐藏面板。
- 既有lock/cancel动画共用同一个reset方法，移除第二处无条件解包。重复reset和下次gesture不会拿旧坐标覆盖新的动态布局。
- 不改XIB、手势阈值、录音/权限/Cache/提交/文件责任，也不混新视觉面板。

## 真实测试接线及边界

恰3测试/CI文件：新 `TinodiosUITests/SendMessageBarResetTests.swift`，现 `Scripts/ci/verify_publish_outcomes_macos.sh`、`Tinodios.xcodeproj/project.pbxproj`。

CI先严格绑定当前HEAD生产blob（CRLF归一），唯一提取完整captureRecordingGestureOrigin/resetRecordingGesture/resetRecordingState方法，逐方法固定SHA256；缺失、歧义、方法漂移或dirty源码立即失败，无自造实现fallback。还校验实际began调用capture、实际audioBarState调用reset。按钮常量从生产唯一声明提取。

生成的 `build/ci-generated/SendMessageBarResetSource.swift` 只入测试target，不提交生成文件、不进App。生产方法原字节执行在UIView子类，使用真实UIKit UIView、NSLayoutConstraint centerX/centerY/width约束；测试主线程执行。**showAudioBar是明确的隐藏请求spy，没有装载XIB，也不执行完整SendMessageBar/聊天页**。这不是完整页面、音频系统或服务端回归；适配范围没有被表述成XIB测试。

4个新增方法：

1. `testResetBeforeAnyGesturePreservesLayoutAndClearsPresentation`：无快照保持原坐标，同时清flags/slider/size并请求隐藏。
2. `testResetRestoresCapturedGestureAndConsumesSnapshot`：开始前真实约束被捕获，模拟位移后恢复一次，快照清空。
3. `testRepeatedResetDoesNotOverwriteLaterLayout`：之后布局变化，重复reset不回写旧坐标。
4. `testNextGestureCapturesCurrentLayoutInsteadOfPriorSnapshot`：下一手势使用新的当前布局。

原选择与顺序除新增一个class之外逐项相等，原210方法不删减。下一候选准确 **SDK43 + UIrunner167 + VLChost4 =214**；真实App身份导航3另列。完整明细见source-checks.json。CI22仍固定785/210+3，不含本单元，也不因身份导航通过证明聊天返回安全。

## 本地实际检查

- 原有静态策略44/44 PASS，原规则未改：`rtk python -X utf8 -B Scripts/ci/run_static_policies.py --report docs/handoff/R3/VOICE-RESET-01/static-policies.json`。
- 实际执行当前CI的VOICE_RESET_SOURCE Python块于独立仅含安全源的临时Git夹具：5/5符合预期。合法HEAD生成且三个完整方法逐字相等；dirty拒绝；重复方法拒绝；已提交方法漂移拒绝；原785旧源因缺少已审核capture拒绝。最后一项仅为提取器负测，**不是旧UI崩溃的动态红测**。证据adapter-checks.json和adapter-source-hashes.json。
- PBX新增测试/生成源各一次Sources membership，selector唯一，精确方法计数与生产只1文件范围检查PASS。
- `rtk bash -n Scripts/ci/verify_publish_outcomes_macos.sh`、`rtk git diff --check` PASS。
- 未在Windows执行Swift/UIKit，不称Mac编译通过；新4方法与实际Chat首次返回等待后续Mac/设备证据。

## 兼容与后续

无协议、存储或配置版本变化。总控/后端固定SHA源审后，由总控唯一推送/CI；不为此修改Recorder/Cache/上传代码或开启新视觉。真实聊天无录音返回、实际长按取消/锁定及XIB布局仍应验收，不能由源适配器取代。后续视觉实施保持该快照安全语义，并保留严格提取器绑定；若修改这些方法须明确更新对应证据，不能弱化门禁。
