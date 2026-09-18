# CI33 · 本端原件验收交接

CI 来源 **`b0984075ca79ffef93658f702005dd19a773616b`**，run **35375538413** / job **105699232079**。本端检查起始 branch `codex/r3-20260918-ios`、HEAD `6c0a00bd48877a89899ec1f1cf52d0c195aa2b62`；tracked dirty 0，保留 untracked 19,781 文件。HEAD 比 CI 来源只多 5 个交付文档文件，没有生产/测试/CI 差异。本次亦只新增本文与 JSON，不重跑 CI、不重封旧包。

原 ZIP 位于项目根 `artifacts/integration/20260918/R3-ios-ci33-evidence.zip`：**50,270,844 bytes**，SHA256 **`0e7227eeec0d351efe518632f23e1f90af1c4f9f6bb3acb6be6ab72af3158f1d`**，实际读取并核对。内部前缀 `ios-01-a-20260918-173905/`。独立读取三个 summary：**SDK 44 + storage 198 = 242 原生，另 3 导航，全通过，0 失败 / 0 跳过**；10 个 ChatScroll 方法都有真实 passed 末行。root 的 69 实体 / 61 附件复核与本端有界原件检查分开，明细与选定附件 hash 见 JSON。

## CI32 同名失败关闭到当前证据层

| 方法 | CI33 实际结果 | 关键原件 |
|---|---|---|
| testNewSubmissionConsumedOnceThenAckAndUnknownScrollPreserve | PASS，0.159 秒 | `56D80220…json`：offset 310，锚点 6/7，first offset -10；方法内独立几何与未消费断言通过 |
| testPreviewButtonCapturesBeforeHandoffAndLateWorkCannotMintTicket | PASS，0.817 秒 | `AADAFA22…json`：didShow 3，原聊天有 parent/window，offset 430；真实 storyboard / 原 handler 的 pop 后捕获拒绝通过，无原 fixture 崩溃 |
| testQuoteNoOpAndOriginalPageSourceRejectLatePresentation | PASS，0.362 秒 | `F23ADCCD…json`：受控取消后 parent/window 为 true、removals 0；`1C59E09B…json`：真实 pop 后 removals 1、parent/window 为 false，旧来源拒绝断言通过 |

CI32 的原 3 失败、ZIP、诊断与 fd/e30 包永久保留。该关闭表示这三个相同测试在固定后继实际通过，不把受控 appearance 当触摸返回手势，不将中性 cells / FlowLayout 的 MessageVC 消费者测试称完整生产聊天 UI、真实附件上传或通讯验收。

## 模拟器包与冷启动

应用包路径：项目根 `artifacts/integration/20260918/R3-ios-ci33-evidence/ios-01-a-20260918-173905/CLAW-OS-unsigned-simulator.zip`，**37,665,378 bytes**，SHA256 **`22c2ad33ec01022c6eef3d9291f733779d6573e3cda4eee26cdcbc167c763e96`**。已核包内 `Tinodios.app/Tinodios` 二进制 SHA `9a426e841b940cfe1eaf261f0cafacda059fec4a4a83fea6731f8bda5b061135`，与冷启 manifest 一致。

同一 iOS 18.5 / iPhone 16 Pro 模拟器 `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9`；原 Shutdown→boot→bootstatus **34.583029 秒 < 45 秒**→Booted→install→实际 launch。启动前确认无该路径进程，实际 **PID 40215**，proc_pidpath 对应安装的 Tinodios 二进制，截图前后进程在，crash_reports 为空。原 `launch-smoke/cold-launch.png` 为 **1206×2622**，SHA **`9590caf145a4fca6d948e272b9ca624319943f829b1235be850624e8073be997`**；本端已看原图：登录表单、注册/找回和原账号登录入口显示，底部连接设置仅部分可见，未据静态图推断滚动或点击可达。

此包为未签名 **Mac iOS Simulator** 应用，bundle `app.veilping.clawoschat`、version 1.22.12 / build 1736；不是 iPhone IPA。运行配置为 `127.0.0.1:9`、推送占位禁用。后续在具备 Xcode 的 Mac 安装：核上述 ZIP hash，用 `ditto -x -k <ZIP绝对路径> <新的解压目录>`，确认兼容模拟器已 Booted，执行 `xcrun simctl install <该模拟器UUID> <解压目录>/Tinodios.app`，再 `xcrun simctl launch <该模拟器UUID> app.veilping.clawoschat`。本次交接没有执行新的安装或启动。

## 三段源码恢复顺序

必须以保全的 R3 源码 **34a8b3e5ad4df210117e2e03b308576796ba55b2** 为起点，保留其继承定制和私有配置；不是空上游。每段先按原清单检查起点，再 `git apply --check` / 实际 `git apply`，核 mode/blob/SHA 后才下一段：

1. **09631fe**：`FINAL-1B20EC2/CLAW-IOS-R3-source-test-ci.patch`，102 路径，1,165,207 bytes / SHA `448633865dec72f1c178dce9ff0f4690b14bdc7eed039c38b1fe91259d85580f` → 1b20 源码。1b20→0a54 仅文档，代码前置相同，已只读核对。
2. **e30e7bc**：`CHAT-SCROLL-01/FINAL-FDEDF825/unit.patch`，13 路径，97,716 bytes / SHA `29cc92f25a9b21100c9fb38b29796460810d946f146a7d365a3b60cb2e48e9f3` → fdedf825。
3. **6c0a00b**：`CHAT-SCROLL-01/FOLLOWUP-B098407/unit.patch`，2 路径，16,477 bytes / SHA `718837601a66f7e344b0f37c7c6e4f8ae0f9f63dfac3a25e314f1e37874c8da8` → b0984075。

三包原正向恢复证据保留，本次仅重新核包实体 hash，没有重新生成或应用。当前滚动单元和两文件后继无 DB/schema、协议、SDK 或发送存储变更；前期累计包中的 C3/迁移边界仍遵守原说明，不据本报告承诺任意旧版本安全降级。回退使用保全的相应源码与配置，不 reset/clean 现工作树、不删除本地数据库。

最终关闭由总控决定。真实 iPhone/Android 设备、账号服务、跨端或双端通讯、真实 OTP/推送、完整聊天和辅助功能操作仍未因本轮 CI 成为已验；媒体外链/安全观察保留各原报告边界。
