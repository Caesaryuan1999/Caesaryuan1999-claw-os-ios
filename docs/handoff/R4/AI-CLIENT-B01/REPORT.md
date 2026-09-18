# R4 AI iOS B1：有界传输与内存恢复

源码初版 `02e4ebcb54e4aa7451224e7935b8bb78b840c8ba`，修正后 B 源码 `e9eba400129c734315e8176d00e5b2a52e2bc74f`。初版源码/八路径 `unit.patch` 原样保留；初版已知问题不能作为可交付终态。最终累计源候选 `b004af0d5c5d8ce2f7560fad04ed8711694c8e23` 另含下述独立 A 夹具和 Core 布局修正。未推送、未运行 CI。

## 范围与接线

四生产：`Tinodios/ClawAssistantModels.swift`、`ClawAssistantService.swift`、`ClawAssistantRun.swift`、`ClawAssistantStream.swift`。新增 `TinodiosUITests/AssistantRunTests.swift` / `AssistantStreamTests.swift`，在原 App-hosted `TinodiosVoiceLayoutTests` target 和既有 `verify_publish_outcomes_macos.sh` 追加两个 class selector。真实 Xcodeproj 1.28.1/Ruby 3.3.12 解析检查见 `project-check.json`，不是 Xcode 编译。

没有修改 Session/Cache/History/UI/DB/Keychain/Pods/workflow。A UI 仍不启用生成；capabilities 新字段不会自动开 B。已捕获的 Session owner/UID/token/origin/generation 门禁复用原实现，HTTP scope 不因单纯 WS 离线而失效，401 只封闭助手 scope，不普通 logout/清库。

支持显式新会话/新问题请求、同 key 原字节显式重试提交、GET 权威 text+last_event 恢复、单独 SSE reader 与 stop 请求、前台 1/2/4 秒最多三次读恢复以及绝对 60 秒 reader 期限。没有自动 POST 重放；无 rid 时同 key POST 仍可能首次执行，动作语义只能是“重试提交”。legacy 只读，retry_of 保留原问题字节和旧尝试，不按正文去重。

## 五项独立审查修正

| 原 02e 源码反例 | e9eba 修正 | 原生证据准备（尚未执行） |
|---|---|---|
| A stop 未返回，流先确认终态；submit B 清 receipt，旧 stop 代次仍有效 | 新意图前退休 stopOperation 并取消原 HTTP task；回包再核 cid/rid/request/question/answer/legacy | 实际 loopback TCP：阻塞旧 stop，真实流终态，B 待提交时观察旧连接取消；错身份六组实际 Service 回包保持原投影 |
| events 只核首项，缺尾末页、after 超 last、next==last 可接受 | DTO 核末页尾部/非末游标；Service 核请求 after 和空页一致性 | 真实 Service+URLProtocol 的九组完整/不完整页 |
| 任意 HTTP 410 被直接翻译成 conversation_deleted | 除 401 外要求限额内 UTF8/JSON/MIME 和 status/code 匹配 | 真实 TCP 302、HTML401、HTML410、正确410、错码410、坏UTF8、超额错误头 |
| 重复 SSE 每条都进入 main 队列；单 append 输出数组无界 | delegate 前 after 去重、连续 ID≤1024、累计 delta 上限；单 append≤1024 | 真实 TCP 字节切片、128 重复帧后的序号哨兵；原 parser 的 1025 帧拒绝 |
| 同步 changed 回调 retire 后，dispatchSubmission/stop 仍可创建 POST | notify 返回后重新核 current 和对应 operation | 实际 Run+URLSession/URLProtocol：新/已有会话 submit 与 stop 的同步退役，有限反向 expectation 验证零请求 |

这里的红证据是固定旧源码调用顺序，不是 Windows 执行 Swift 的红测。受控恶劣重复流是客户端容量边界测试，不声称真实后端发出了恶意流。TCP取消验证本机 transport；不声称撤销服务端已收到的 stop。

## 验证与数量

- `source-checks.json` / `static-policies.json`：初版八路径、原 18 Swift 文件保留、20 个新方法、44/44 源策略。
- `successor-source-checks.json`：后继恰六路径、12 源码事实/门禁检查、所有未选 index blob 不变、原 20 方法名称保留。`successor-static-policies.json` 为 44/44 源策略。
- 最终 Run 17 + Stream 7 = 24 个新方法。原 269 个 native 方法保留，下一准确候选期望 **293 native（SDK44 + storage249）+ navigation3**。计数不是运行结果；全部 B 原生方法及新 Core/A 修正仍 **NOT_RUN**。
- 真实 TCP 使用 127.0.0.1 合成 HTTP；实际 SDK/SQLite 使用隔离合成账号。无真实 provider、无真实用户凭据、无 6099 实机联调。绝对期限测试自身需等待约 60 秒，但不扩大 CI timeout。

CI38 的既有 A/CORE 结果由总控原件保留：268 pass / 1 fail；它没有本 B 单元，不能外推 B 通过。后继 Core 原生视觉也待新结果。

## 保留的前置依赖

1. 跨进程 pending request journal **OPEN**。当前 key/body 只在内存；进程退出会丢未知提交票据，不能据此开放生成 UI或宣称跨重启安全重试。
2. 本单元无显式 B messages 列表入口。B2 必须按 limit10、items≤10、user32KiB/assistant256KiB 与 24MiB 响应预算验证最坏转义页；A limit20 不变。
3. 当前只有本 run 的 ticket/receipt/projection；没有 previousAttempts 跨会话缓存。切 cid 清旧投影，匹配 cid 墓碑清除当前 run，外 cid 墓碑不清新会话。未来 B2 完整历史仍须独立验收。
4. 尚无真实模型、流式页面/停止交互、跨设备运行恢复、设备/网络切换验收。已有 A 页面不会假回答。

## 安全还原

既有保全源 `cf63be2d5661f6561789c411f9a1d74827a068f7` → 原 `unit.patch` 得到 02e → `a-page-order.patch` 得到 3cb → `b-successor.patch` 得到 e9eba → `core-title.patch` 得到 b004。每步精确 baseline/target、mode/blob/SHA/字节数在 `unit-manifest.json` / `successor-manifests.json`。

已用独立临时 GIT_INDEX_FILE 分别实际 `git read-tree BASE`、`git apply --cached --binary PATCH`、`git write-tree`，完整目标树和所有未选条目均一致，原工作树 index 未变。没有将 reverse-check 当成正向验证。补丁保留 Git 原字节上下文，不重写行尾。

应用须在保全的独立 checkout 验证准确基线与本地定制，再逐步 `rtk git apply --check <patch>` / `rtk git apply <patch>`；不要对原 dirty 源 reset/clean。回退用保全 checkout/对应源提交，不承诺旧 binary 可直接读取新库。本批不改数据库或消息/认证协议，不需要数据库迁移；也不包含私有配置、签名、推送文件、Pods、build、runtime 或 CI 巨量产物。
