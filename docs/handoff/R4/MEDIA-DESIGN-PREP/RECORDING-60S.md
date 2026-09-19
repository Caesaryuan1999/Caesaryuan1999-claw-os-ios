# 新录音 60 秒：独立实现准备

这是 0ea19847e3b043bc14bfb046d2e1809cf92134e6 的只读盘点。用户已确认：新录制最长 60 秒，到时自动停止并保留试听/发送，不自动发送；历史 >60 秒不裁剪、不改 duration 或内容。准确实现名单待总控冻结；本报告不修改代码。

## 原来源与到限路径

1. Cache.swift:279–295 为真实创建入口；285 把 MediaRecorder.maxDuration 设为 **600_000 ms**。MessageViewController.Constants.kMaxDuration:215 也是 600_000，但全项目源搜索只见声明，没有消费者，不能只改它。
2. MediaRecorder.swift:201–202 在真实 AVAudioRecorder 上调用 record(forDuration: TimeInterval(maxDuration)/1000)。应该把实际采集预算改为 60 秒，不能只把 Drafty duration 截成 60_000。
3. AV 完成回调 356–370 要求同 engine、原 owner current，经主线程 stopForPreview:238–258；后者停止计时、移除 delegate、停止引擎、结束音频 session，保全本次 URL/真实 elapsed ×1000/preview，并仅一次通知 didFinishRecording。
4. MessageViewController+SendMessageBarDelegate.swift:230–235 → SendMessageBar.recordingDidStop:483–489，把 recordingStarted=false、audioLocked=true，进入 longPaused，再填实际时长和样本。此完成链没有 publish 或 submit。
5. 未锁定松手 longPressed.ended:216–221 在 recordingStarted=true 时发 stopAndSend；上滑锁定后开头 guard !audioLocked:206 已阻止后续同手势 ended。完成回调先执行时也会设置 audioLocked，因而不能自动发。
6. **临界仍需处理**：真实引擎到限与其主队列完成回调存在先后；若旧 recordingStarted 仍为 true 的 ended 先执行，就会直接进入 sendAudioAttachment。不能只依赖 UI 标志或任意 sleep。必须在发送前由本次 recorder 的实际录制状态/已到限判定降为 preview，保留随后显式发送动作。

## 准确四生产文件建议

| 文件 | 最小职责 |
|---|---|
| Tinodios/MediaRecorder.swift | 单一本次新录制限额与实际引擎停止/到限 admission；到限幂等 stopForPreview，不在 callback 自动调用提交。不得靠改 duration 值掩盖实际文件超长。 |
| Tinodios/Cache.swift | makeMediaRecorder 实际配置 60_000 ms，引用统一值，仍原账号 lease/锁序。 |
| Tinodios/MessageViewController+SendMessageBarDelegate.swift | stopAndSend 进发送前：本次仍 recording 但引擎已自动结束或实际录制已达限，转 preview 并 return；已完成 preview 的明确发送仍走原入口。 |
| Tinodios/MessageViewController.swift | 移除/统一旧无消费者 600_000 常量，录音提交仍原 scope 与真实 Data/duration/preview；不改变普通历史 AU。 |

SendMessageBar.swift/XIB 本轮不必改：真实 recordingDidStop 已封锁同一次长按 ended 并显示预览；应测试真实原方法确认，不复制一套 Boolean。若实现分析证明需要区分新的 action 才能守住边界，应先上报额外文件，不能静默扩名单。到限准确提示的落点可在现 Delegate 的实际完成处理，文案由总控统一；不显示“已发送”。

## 重录、上传及旧历史

- 放弃走 MessageVC.discardVoiceRecording:964–971 → Cache.releaseMediaRecorder → recorder retirement，清本次未交接文件；新 start 建新 UUID 文件、清 elapsed 与采样（MediaRecorder:180–208）。不删除已交 Data 的消息或上传副本。
- MessageVC.sendAudioAttachment:974–1004 从 prepareSubmission 取得真实 Recording/Data，只校原 3 秒最小值；提交被原 owner/UID/generation/topic 接受后 didSubmit，旧文件清理责任保持。
- MessageInteractor:735–755 内联直接使用 recording.duration；大附件初始:856 与成功:977 同一 duration，后者 ref=srvUrl；不改变 mid/上传/C3/重试规则。
- 旧网络 AU 的 duration 解析与播放器读取完全独立；不把 60 秒新录制规则加进历史 formatter/SDK/DB schema，不批改已有文件/消息。

## 原生回归建议（不是已运行）

先扩展现 MediaRecorderLifecycleTests 的**真实 MediaRecorder 类** + 注入 AV 边界，记录 record(forDuration:) 参数而不是目前 fixture 丢弃参数；真实临时文件仍保留。再在现 App-hosted VoiceLayoutTests/受控 delegate 中调用原 XIB 长按 handler，必要共享真实业务消费者路径，不能只复制 if 条件。

| 情形 | 应保留的断言 |
|---|---|
| 已授权开始 | 只启动一次，record(forDuration:) 精确 60；真实录制 engine 参数而非 metadata。 |
| 59 秒松手 | 保留原当次有效 owner 的提交一次，真实 duration 不改。 |
| 60 秒 finish 先于同手势 ended | preview 保留；stop/finish 幂等；ended 不提交；随后显式“发送语音”才提交一次。 |
| ended 先于已排队 finish | 引擎已不 recording 或真实本次时间已达限时，只转 preview，零提交；晚 finish 不重复结束/提交。 |
| 锁定到限/同手势取消 | 到限仍 preview，ended 不提交；明确放弃仅清该 take。 |
| preview / 重录 | 显式发送使用原 Data/duration/preview；放弃后新 UUID、新计时；不足 3 秒/读失败恢复及 cleanup 原断言保留。 |
| 账号/页面退休 | 到限/晚 callback 不恢复退休 lease，不提交给新 owner；原录音与试听停止规则不变。 |

系统 AVAudioRecorder 到限回调时序与实际文件可播放时长仍需 Mac/设备验证；受控 engine 只能证明真实应用类的状态/竞态处理。原生 XIB 受控 handler 不等于真手势/麦克风权限弹窗/真机录音。需要真实文件时长测量，不准把数值夹具或被裁的 metadata 当实际 60 秒文件证据。
