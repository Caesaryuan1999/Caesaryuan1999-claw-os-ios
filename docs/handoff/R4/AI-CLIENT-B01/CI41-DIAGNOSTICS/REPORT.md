# CI41 header-only 诊断后继

唯一代码改动是 `TinodiosUITests/AssistantStreamTests.swift`。基线测试为 `6d36bd8450ad61dabf5872c7e7709238c3cb85f6`，生产保持 b004；B02、生产网络、七个原样本、selector、workflow、既有恢复链不改。本窗口未推送或运行 CI。本候选期望 **294 原生 + 3 导航**，尚未执行。

## 原失败与未确定部分

CI41 run35413624631 / job105817886283 原 ZIP 为 99,462,343 字节，SHA256 `b9585a55dfd9c656f9123ae624bd47ea7276765033ce59437a42612b725d3046`。原件位于根 `artifacts/integration/20260919/R4-ios-ci41-evidence.zip`。SDK44、storage248通过/1失败，合计292通过/1失败；导航、打包、冷启动未执行。

本窗口只读核了原日志和 xcresult 内数据库：前六个活动无失败，第7个 fixture4410 在5秒等待失败。它只发送原410/JSON/Content-Length65537响应头，不发送正文或 EOF。数据库及导出 manifest 都没有 `assistant-stream-refusal-stages`，因此原件不能证明请求是否到达、NW send 是否成功，或 URLSession response delegate 是否执行。原 `defer` 失败保留声明已被这次事实否定；保留旧报告与红样本，不回写为已记录。

生产 response delegate 已有65536长度门禁；收到该长度时会 invalidResponse。根因仍 **OPEN**，没有将超时归因于缺少门禁，也没有据历史论坛断言本平台缓冲规则。

## 最小诊断变化

1. 原拒绝方法在第一个可能失败点前注册 `addTeardownBlock`。LIFO执行服务取消、server关闭、最后保留 JSON；取消产生的 completion 仍记录，但不冒充服务器拒绝。原7组 wire、5秒和语义断言保留。
2. 恰好新增1方法，内含3个独立 loopback server/session 实验。裸 `URLSessionDataDelegate` 使用无 completion-handler 的 `dataTask(with:)`、专用非主串行 delegate 队列，与生产相同的请求头和 ephemeral/cookie/cache 配置。第一组保留 header-only，观察5秒截点；无 response 只记为观察，不作为安全通过或提前终止后续控制。必须确有唯一请求及成功的本机 send 回调，观察才有效。
3. 第二组同头仅追加1字节，必须5秒内收到真实 response，且 status410/expectedLength65537。第三组通过实际 `ClawAssistantService.stream` 发送同头+1字节，必须5秒内 invalidResponse，向消费者交付的 frame 为0。生产 API 不提供原始 body 回调，故没有额外伪造 body 暴露测量。阳性控制以客户端实际回调为门禁；服务端 send 结果照录，不把及时取消的竞态错误另作失败。

三个控制完成后才检查结果，不用控制成功覆盖原case7失败。每组记录固定试验号、事件序号、单调时间、header/发送/数据字节数、状态/长度、固定结束类别；不记录URL、header值、token、body或异常文本。最多128条。原 JSON 与新控制 JSON 均用 keepAlways 原生附件；不保证进程崩溃时可保留。

## 官方依据与证据强度

- [Apple XCTest teardown说明](https://developer.apple.com/documentation/xctest/set-up-and-tear-down-state-in-your-tests)：注册的块在测试后逆序运行，失败且 continueAfterFailure=false 也执行；进程崩溃不保证。选择该机制替代原 defer，仍待本次 Mac 证实附件实际导出。
- [Swift XCTest迁移说明](https://docs.swift.org/latest/documentation/testing/migratingfromxctest/)说明失败中止涉及 Objective-C exception；这支持不能依赖 Swift defer 的判断，但原件未证明精确异常展开路径。
- [Apple URLSession response delegate](https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/urlsession%28_%3Adatatask%3Adidreceive%3Acompletionhandler%3A%29)说明初始响应处理；[NW send completion](https://developer.apple.com/documentation/network/nwconnection/sendcompletion)不提供客户端 delegate 已收到的证明。
- [2016年 Apple论坛实验](https://developer.apple.com/forums/thread/64875)仅提供“可能等到正文才回调”的待证假设，不是当前 iOS/SDK 保证。本控制直接记录实际结果，不预置该结论。

## 本地检查

`source-checks.json` 固定原/新SHA与17项源码检查：原7方法名保留、其余6方法逐字相同、原7组响应构造与断言行相同、60秒方法逐字相同、监听初始化未变；新增恰好1方法。代码及辅助文本UTF-8/LF；`git diff --check`通过。没有运行 Windows 替代网络模型、Swift编译或原生测试。下一轮即使两个阳性控制通过，原header-only失败仍须如实失败，不能宣布B1闭合。
