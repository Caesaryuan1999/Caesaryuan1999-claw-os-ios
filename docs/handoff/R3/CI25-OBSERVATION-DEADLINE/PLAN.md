# CI25 固定观测窗诊断与最小提案

只读诊断。CI25/abc2307/run35345790739：SDK44、UIrunner167通过；原4 VLC观测3通过，第四403观测失败。新VIDEO-OWNED491/226方法未在该轮执行。

已独立核原zip SHA `1161c85058f9fb81dedae8d64c476852e7d0bb1264c13d38a292c7750b867630` 与原附件 D6DED7EA-C015-4291-9155-B0A1CDDE30E3.json；成员SHA和必要安全字段保存在evidence.json。第一原片实际A_red，第二B_blue；第三revision2的独立seq5–10实际403/header/body write completed；maxDecoded/displayed=0，thirdStoppedOrTerminal=true。

`elapsedMs = Int(elapsed * 1000) = 4999` 已证明 monotonic elapsed <5 秒，故原745的 `elapsed >= 5` 必失败，足以解释该处 response 抛错。原JSON未记录waited枚举，不假定它一定为timedOut，更不能从4999推断具体少了多少微秒或私有XCTest计时实现。当前逻辑错误在于把一次wait(timeout:5)返回直接当作实际至少经过5秒；严格5秒要求本身不应降低。

最小提案仅 TinodiosUITests/VLCPlaybackProbeTests.swift 和本报告：

1. 增加同文件test-only共用绝对单调截止方法，目标 `startedUptime + 5`。每段等待前算真实剩余时间；如果XCTWaiter提前返回，继续只补剩余时间，最多8段且仍受原120秒方法预算约束。
2. 非timedOut结果/中断、无时间前进耗尽、无剩余方法预算均失败，不把这些当窗口完成。最终仍要求monotonic elapsed >=5，不增加宽容误差、不改成4.999，不延长VLC8秒解码或stop5秒。
3. 原403两种cache配置及新M3U观测复用该方法，保留403 request/revision/完成状态和帧/状态要求。记录安全wait类别、补足段数、最终elapsed微秒及deadlineReached，便于下轮判定。
4. 同helper提供clock/wait边界注入，在原403方法开始执行4个受控回归：提前到4.999后补足、一次到期、时间不前进耗尽、interrupted拒绝。它验证测试自身的deadline算法，不模拟VLC。随后真正VLC/HTTP5秒仍完整执行。若按此实施，不新增XCTest方法，仍226+nav3期望。

生产两文件及已封491累计包保持，后继测试修正独立提交。只有精确后继Mac结果能证明真实观测窗与实际VLC行为；此诊断不把前两正常颜色、零帧或状态0提升成缓存/网络安全保证。
