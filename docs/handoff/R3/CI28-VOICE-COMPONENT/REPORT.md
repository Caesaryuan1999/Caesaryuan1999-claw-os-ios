# CI28 VOICE-COMPONENT 有界修正

基线 `13318b374709aa5f160374111a6954477a627a3c`；只改两份代码：
`Tinodios/widgets/SendMessageBar.swift`（初始化 4 行）及
`TinodiosUITests/VoiceLayoutTests.swift`（原 6 方法内增强）。

## 原始失败与证据

CI28 run `35353667838` / job `105627636349` / artifact `10551556467`：
SDK44、UIrunner175、VLC7 全 PASS；新 VoiceLayout 六方法 3 PASS / 3 FAIL。
总计 229 PASS / 3 FAIL / 0 skip；导航、打包、冷启动 NOT_RUN。
Swift importer 修正已经通过，不再是 CI27 的编译失败。

原 ZIP `C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci28-evidence.zip`，
74,830,064 字节，SHA-256 `3844417c2abd8daf6e379cc6bd0dbb435635ac56a3026c4a9d07e644ae42c094`。
原证据目录 `C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci28-evidence/ios-01-a-20260918-140246`。
本单元不重写原附件，同行 `checks.json` 记录 24 个组件原附件与 ZIP 逐字节/hash 对照。

| 位置 | 实际证据与根因范围 | 本次修正 |
| --- | --- | --- |
| 测试 103 | 整个 bar 后代的 UILongPress 数为 13，错误预期全部只能为 1；UITextView 有系统选择手势。原 XIB 的录音手势实际连在 sendButton，最低按住 0.5s。 | 只数原 sendButton 的 UILongPress；仍要求恰 1、0.5s，并验证 recognizer.view 是原 button。没有删除系统手势。 |
| 测试 186 | 首次采样 keyboard height=98，不满足原 >100；tearDown 原 `3D162F77-8955-4F37-AC8D-68037CB27623.json` 已为400、shows3、inputFirstResponder=true。原等待条件只要历史 didShow>0 和任何正高度，会把 accessory-only 通知提前接受。 | 使用输入切换后的新通知序号，didShow/didHide/didChangeFrame 都更新真实 endFrame；主线程持续采样，保留 >100，且扣除 accessory/safearea 后仍要求完整软件键盘。几何稳定至少100ms，总等待3s。 |
| 测试 275 | 原真实 hit 校验失败；生产 lock 动画150ms，而 fixture settle 约30ms；`13EB074A...png` 可见过渡期重叠/淡按钮。原失败没有 hit class，不能把动画直接定为已完成动态因果证明。 | 等相关面板、按钮及祖先过渡层无动画且几何稳定，再等实际同window目标中心命中并保留原 hit 断言。两个等待共用每目标3s绝对预算；超时仍FAIL。记录层keys/命中class/window，不禁用动画、不强行改interactive。 |
| 真实产品 P2 | 原 `BA297243-6CFE-4BF0-9614-388921CF04F5.png` 确认麦克风残留，发送两字折行。XIB286–290 仍有 buttonConfiguration.image；旧 Swift 只 legacy setImage(nil)/setTitle，且宽度按纯文字。 | 已load Nib、IBOutlet有效后，在第一处legacy外观设置之前，以 iOS15 availability 门禁设 sendButton.configuration=nil；titleLabel 单行。原文字宽高计算、录音图片恢复、手势和发送 delegate 原样。XIB保持原字节。 |

[实际残留图](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci28-evidence/ios-01-a-20260918-140246/storage-attachments/BA297243-6CFE-4BF0-9614-388921CF04F5.png)；
[动画过渡图](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci28-evidence/ios-01-a-20260918-140246/storage-attachments/13EB074A-60DF-4863-97D7-2CC86E056B5D.png)；
[失败后稍晚的锁定图](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci28-evidence/ios-01-a-20260918-140246/storage-attachments/06FBE749-6BDC-4B30-871A-9E41C117C79C.png)。
这些是原 UIKit 组件 drawHierarchy，不是完整聊天页面或真实录音。

## 原生验收保持六方法

- 原 nib/reset 方法增加真实原 XIB 空→文字→空：configuration nil；文字态 image nil、title=发送、单行、真实 UILabel 宽高足够、原按钮最小尺寸；回空态无 title、原 UIImage 恢复、48pt 和录音 accessibilityLabel 恢复。未调用发送、录音或登录。
- keyboard 方法保留原 >100/输入区完整可见及无发送断言。隐藏时检查本次新通知、input不再firstResponder、controller当前firstResponder、真实键盘只剩 accessory+safearea；controller故意保留 inputAccessoryView，所以不再错误要求 frame 必须零。不是降低软件键盘显示标准。
- 相关层列表不遍历 UITextView 光标或 Wave 子层；只检查面板、按钮和祖先布局过渡。teardown 不等待稳定，仍保存失败原状，避免失去诊断。正常 PNG 在稳定后读取同一个真实 view，没有重绘替代组件。
- safe JSON 仅记录固定类别、计数、通知可见高度、responder、按钮图像/产品标题/尺寸、层keys和命中class，不记录合成输入值、账号或凭据。
- 六方法名称/已有所有 XCTest 断言保留；原 226 方法及导航3 selector、宿主/PBX/Podfile/lock/依赖均不变。没有改 CI 环境，没有增加 native 方法凑数。

## 本地检查与边界

44/44 既有源码策略 PASS（`static-policies.json`）；精确边界与原证据 hash 检查见 `checks.json`。
这些是 Windows 源码检查，新增实际 UIKit 断言尚未执行，不写 Mac 绿或假造“修前原生红/修后原生绿”。
新的 title/config 断言此前不存在；红证据是 CI28 的实际组件 PNG 与固定源码链。

Swift 最低部署 iOS14，因此配置API使用 `#available(iOS 15.0, *)`。
下轮仍预期 232 native（44+175+7+6）+ 独立导航3。
动画与键盘的新等待条件必须由实际 Mac 原图/JSON/断言继续验证；如仍失败，保留原因，不能放宽原阈值、强制静态动画或清数据求绿。
已冻结录音权限/lease、Cache、Interactor、owner、C3/AUTH、文件责任和上传/发送均无变化。
