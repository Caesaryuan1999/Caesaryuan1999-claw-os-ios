# CI40 拒绝响应的阶段诊断

这是仅测试的诊断候选，不是已确认的生产修复。生产仍为 b004，当前源码基线 `34b675e7f1db76c90ca112e0f2588f1ddfb97696`。唯一代码路径 `TinodiosUITests/AssistantStreamTests.swift`；B02、生产 Stream、selector、workflow、既有恢复包与原失败均不改。本窗口未推送/执行 CI。

## 原件结论与开放根因

CI40 run35403779991 / job105789172452，原 ZIP SHA256 `dc40962c88da1604ae6d7361e2e80980226e13a91e5cb91bd687b72c9dac1b07` 已核。SDK44通过；storage248通过/1失败/0跳过，合计292通过/1失败。原真实分块、60秒绝对期限、旧stop与新会话三项 TCP 方法通过；第四拒绝响应方法在第238行等待5秒失败。导航、包和冷启动未执行。

原方法七步骤共用同一 expectation 名，失败记录没有 status；原 xcresult 内 TestCaseRun227 也没有 Activities 行。因此不能确定具体哪一步，也不能用系统连接编号代替 fixture 请求序号。4410 的 header-only 条件是候选，尚非已证根因。

生产 `ClawAssistantStream` 的 response delegate 已检查错误响应 MIME 与 `expectedContentLength <= 65536`。若65537头真正进入该分支，会立即以 invalidResponse 拒绝；不能报告缺少长度门禁。[Apple 对该 delegate 的说明](https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/urlsession%28_%3Adatatask%3Adidreceive%3Acompletionhandler%3A%29)是收到初始响应头，本次原件未记录其实际到达时刻。根因保持 **OPEN**，没有将不确定性归为 CFNetwork 或业务解析问题。

## 本次诊断范围

- 七个固定 case 各自 `XCTContext.runActivity`，expectation 也包含固定序号/fixture编号，仍等待5秒。
- fixture 在真实请求到达后记录 `request_seen` 与仅数字的请求序号；原响应发送内容及 close 顺序原样。
- `Reply.send` 仅增加可选 observer，在真实 `.contentProcessed` 回调记录字节数量、成功布尔，或 NWError 的固定 posix/dns/tls/unknown 类别和数值。仍无论错误与否调用原 completion，未改变旧行为。contentProcessed 成功只证明发送回调，不等于客户端 delegate 收到响应。
- 实际 Stream completion 记录固定结束类别，绝不转储 server code 字符串或 Error 文本。全部事件记录同一 monotonic 起点的微秒数；锁内最多128条，超额仅计 dropped。
- 方法顶层 defer 用原 XCTest keepAlways 附件保留 `assistant-stream-refusal-stages` JSON；先注册，因而在原 service/server 清理后生成快照，包括正常返回与测试失败路径。进程强制终止等无法保证 defer 的场景不作承诺。

固定编号仍为302跳转、401 HTML、410 HTML、1410合法墓碑、2410错误业务码、3410非法UTF8、4410超额 Content-Length。4410依然只发送原头，不新增 body/EOF/close；没有引入直接调用 delegate 的替代测试。诊断不记录 URL、header、token、正文、原错误描述或用户信息。

## 本地检查与下一验收

`source-checks.json` 记录固定原/新字节 SHA。原七个方法名称不变，另外六个方法全文逐字相同（含真实60秒方法）；七组响应构造块逐字相同；本方法原拒绝/frame/redirect全部断言保留；3秒初始化、5秒等待、60秒及65秒 XCTest上限不变。`git diff --check` 通过。

这些是 Windows 源码/字节检查，不是 Swift 编译、Network 回调或新的运行结果。后继仍期望293原生+3导航。下一准确 Mac 候选须根据原样附件判断请求、发送回调与 Stream completion 到达的具体阶段；即便运行变绿，也不能仅凭诊断增量宣称原 header-only 运输根因已被修复。旧CI39/CI40失败和原恢复包保持独立。
