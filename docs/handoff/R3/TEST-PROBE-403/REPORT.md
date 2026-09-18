# TEST-PROBE-403 — 关联实际HTTP响应的完整观察窗

仅修改 `TinodiosUITests/VLCPlaybackProbeTests.swift` 和本端证据文档。生产仍固定 `e6d0aa978daf6c2aa92f88e88deb2060658226f9`；本单元起点是其文档后继 `7e12f3b4997bf80bb37629bfca809638f98b41c1`。不修改播放器默认参数、依赖版本、host、CI selector或四个方法名，不实施生产播放修复。

## 原失败实证

独立读原CI23 ZIP并校验SHA：`36d3d11a3e994719ffef7bef8fe97d394f897adcc0a003b26674c198046fab1b`，artifact10544693980，73,781,941 bytes。原目录 `ios-01-a-20260918-113833`。

- SDK44 + UIrunner167真实通过；独立VLC4是3通过、1失败。导航/新包/冷启动未执行。前三项是依赖观测，不是播放安全通过。
- 失败附件 `storage-attachments/F9E82E62-E94E-48D9-A6BC-F2B1F3E8DE79.json`：reopen-403-timeout，completedCases为空，第三player state0、readBytes/decoded/displayed/time均0，host前台scene/window/drawable实际有效。
- 源红/蓝MP4的AVAssetReader均90帧、64×64、最后PTS2966ms通过；原第一/第二VLC截图也已导出。失败分支却没有保存这两次颜色、请求计数及server.observations，所以不能从零帧区分“没有请求”和“收到403后停止”。原ZIP/PNG/JSON不改。
- 固定0a7源码313的terminal只包含ended/error，664的旧until(5)只等decoded或terminal；源141–153事件没有HTTP状态/header/body完成字段，669异常丢失当前case。官方[VLCKit3.6.0头](https://raw.githubusercontent.com/videolan/vlckit/3.6.0/Headers/Public/VLCMediaPlayer.h)将Stopped列为枚举0；它说明状态名称，不能证明本次实际响应已送到播放器。
- 原storage.log仍含CALayer/doResetBuffers后台线程异常栈与h264 get_buffer/decode_slice_header警告。现有调用方play/stop已经走vlcMain；没有证据称这已修复VLC内部渲染线程。本单元不改渲染实现，不以新观测通过擦除旧日志。

## 最小观测变更

1. 每个fixture route保存revision，每次replace原子递增；requestSequence单调增长。第三阶段只匹配第二阶段计数之后、当前403 revision的请求，不能拿前两次200/206充数。
2. 记录固定responseStatus，以及headerWrite/bodyWrite的not_started/pending/completed/failed、responseWriteCompleted。网络异常保存固定失败类别，不记录URL、query值、header值或error描述。空403正文也经过真实NWConnection body完成回调。
3. `responseWriteCompleted`只表示本地NWConnection接受header/body写入，不声称对端已经解析。失败、取消、未完成都不会满足403条件。
4. 第一/第二实际截图颜色、播放器指标、请求计数及事件各阶段保存。所有catch附当前case、先前阶段、完整请求和已完成其他cache模式；不会在第三阶段失败时丢失前两段。
5. 第三阶段保持**完整固定5秒**，不因初始stopped或瞬时ended/error提前结束。独立XCTWaiter对永不为true的轮询条件等待原5秒，只将timedOut解释为观察窗到期；该结果自身不构成测试通过。记录elapsed、有限采样和最大decoded/displayed，原120秒方法预算不变。
6. 窗口结束后必须有真实解码/显示正证据，或关联第三阶段且写入完成的HTTP403并且播放器在stopped/ended/error。零请求+零帧永远失败；只有403但仍opening/buffering也失败。正帧但未观察到403是“路由改变后仍复用内容”的单独观测，不伪称服务器拒绝已被忽略。
7. cacheable=false/true分别保留结果。成功测量的无旧内容结论只写NOT_OBSERVED_WITHIN_FIXED_WINDOW；不是持久缓存、安全隔离或生产页面验收。旧内容正证据仍报告原安全缺口。结束后原5秒stop检查保留，只尝试一次；失败仍使方法失败。

全局terminal、decoded的帧/time/64×64门槛、8秒正常播放窗、snapshot、clip/AV读回、cleanup及前三个原测试方法逐字保留。sampledFrame只追加可选证据回调，在真实snapshot后返回已有颜色/指标；默认调用行为和断言不变。

## 检查与待执行

Windows只执行本端源码固定差异检查及git diff --check；见source-checks.json。没有在Windows运行Swift/VLC，不以Python复制状态机。原生方法数量仍44 SDK + 167 UIrunner + 4 VLC =215；离线导航3另列，无skip、无断言删除。

下一Mac需逐项检查：两cache模式均有前两色/指标、第三revision/请求序号、原5秒elapsed、header/body完成或错误、停止结果；异常时也有完整当前case。主生产owner退役继续读取、VLC默认跟随redirect等问题仍独立待修；本probe没有实例化实际VideoPreviewController。

新提交由总控/独立审查后运行精确CI。不得为得到绿色而加超时、跳过零请求或放宽正常解码/帧/时间断言。测试回退仅撤本单文件差异，旧CI23失败证据保留，不回退VOICE视觉或可靠性。
