# CI39：真实 TCP fixture 启动顺序修正

本单元仅修改 `TinodiosUITests/AssistantStreamTests.swift`：将既有 `newConnectionHandler` 五行完整移到 `listener.start(queue:)` 前。生产仍与 `b004af0d5c5d8ce2f7560fad04ed8711694c8e23` 相同；不改 B02、七个方法、断言、3 秒 ready 等待、60 秒绝对 deadline、65 秒 XCTest 上限、selector 或 workflow。本窗口未推送、未触发 CI。

## 原始失败与确定根因

- CI39 固定 b004，run35402042528 / job105783842048。
- 原 ZIP：根目录 `artifacts/integration/20260919/R4-ios-ci39-evidence.zip`；SHA256 `71cbce339b394cf06b8d7085a95faeb5cba7e2f6552fcbc7b84585ee43d6569e`，本次重新核对一致，未修改。
- ZIP 内 `ios-01-a-20260918-223342/storage.log` 第21843、21849、21853、21857行，四次均由 Network 报告 `Started without setting either new connection handler or new connection group handler`。
- 原源码第52行先 start；第53行等待 ready；第57行才安装连接 handler。监听器立即进入 failed，端口为空，第54行抛 fixture；因此后面的 handler 安装永远未到达。四个方法分别0.566、0.011、0.005、0.010秒失败，没有进入 HTTP、流读取或60秒观测。
- 原 summary：SDK44通过；storage245通过/4失败/0跳过，共249；合计289通过/4失败。Stream为3通过/4失败；导航、打包、冷启动未运行。其他方法通过不补足这四项缺失证据。

## 前后条件与实际验证

修前已由原日志和固定 Git 源码共同证明缺 handler；修后 state 与 connection 两个 handler 都先安装，再 start，仍须真正 ready 并取得端口才允许方法继续。连接上限32、loopback绑定及所有 read/send/stop 实现不变。

Windows检查见 `source-checks.json`：原五行块逐字保留；移除该块后全文件前后完全一致；整个 `AssistantStreamTests` 类逐字相同；七方法名称/正文/全部断言保持；唯一代码差异为这个块的位置。`git diff --check` 通过。没有在 Windows 执行 Swift、Network 或模拟器；后继原生仍待总控以精确提交运行，期望仍293原生+3导航。

工作目录 `work/r3-20260918-ios`，branch `codex/r3-20260918-ios`；修改前 HEAD `db903725054d8fc7c7247d671d6452e57a0f645d`，tracked0/untracked19789，自有 origin。未跟踪资料、旧恢复包与 CI39 原失败全部保留。需要源回退时仅在副本反向应用本单元一个测试文件差异，不操作生产数据或旧库。
