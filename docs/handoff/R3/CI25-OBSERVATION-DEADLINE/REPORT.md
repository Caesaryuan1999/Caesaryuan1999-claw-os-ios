# CI25-OBSERVATION-DEADLINE — 补足真实固定观测窗

独立 test-only 单元；生产两文件与49194cc逐字不变，已封491累计补丁不覆盖。本提交仅修改现 `TinodiosUITests/VLCPlaybackProbeTests.swift` 和本目录证据，未更改VLC参数、HTTP、解码8秒、停止5秒或120秒单方法预算。

原CI25证据见 `ci25-original.json`（原字节43330，SHA ff b83120...完整值见evidence.json，实际摘要为 `ffb83120b49a9f5f10b0d266d5db33d1893821029861bb364a7d72356ffde0bd`）。这是原导出附件直接复制，不重新计算现场值。seq5–10/revision2完整403响应、stopped/terminal、零新帧均已记录；elapsedMs4999确定不足5秒。原waiter枚举未记，不能假称已证明其具体返回值/底层计时误差。

共用 `observeFullWindow` 以 `startedUptime + 5` 为绝对目标：合法timedOut提前返回才按当前剩余时间继续；最多8段，每段受原方法剩余预算约束。中断或其他结果直接拒绝；时间无进展耗尽不通过。最终仍要求monotonic elapsed >=5并有方法预算，不新增4.999容差、不改播放/HTTP要求。403的cache false/true及新M3U观测都调用同helper，并记录各段固定类别、最终微秒、deadlineReached/accepted。

在原403方法开始调用同helper的4个受控边界：4.999提前返后补0.001；正常一次到期；无进展8段后拒绝；中断即便时间已经到5秒仍拒绝。它们只证明测试本身的clock/wait算法，不是实际VLC；随后原HTTP和VLC仍走真实5秒观测。没有新增XCTest方法，仍226(44+175+7)+单列navigation3期望。

Windows执行27/27定向源码检查与diff --check：另外5个原生方法、实际server/player、decoded/clip/AV读回/snapshot/cleanup/owned helper绑定均逐字不变；新7方法全部属于实际XCTestCase。Swift受控4例和真实VLC仍待下一精确Mac，不把Python源码检查当执行。

原491包仍只对应491；此后继测试delta由总控独立复核后决定CI26。原CI25 FAIL、CI24编译失败及全部renderer警告保留，HTTP403和完整计时通过也不能提升为任意容器网络隔离或真实VideoPreview页面验收。
