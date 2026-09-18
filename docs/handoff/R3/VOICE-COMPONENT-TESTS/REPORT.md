# VOICE-COMPONENT-TESTS — real App class/XIB, component-only candidate

基线：`4b5ab7398cf70e153eaaf08dd09cb79cefb20ece`。此批独立于总控正在执行的 CI26；未 push、未运行 Xcode，不改任何生产源码、XIB、协议或已封探针。

## 准确范围

6 个代码/接线文件：

1. `TinodiosUITests/VoiceLayoutTests.swift`：新测试，唯一编译归属为新目标。
2. `Tinodios.xcodeproj/project.pbxproj`：新增 `TinodiosVoiceLayoutTests`，类型 `com.apple.product-type.bundle.unit-test`；host 为原 `Tinodios.app/Tinodios`，loader 为 `$(TEST_HOST)`，依赖原 App；仅 1 个测试 source，无复制生产 source、无复制 XIB/resource。
3. `Tinodios.xcodeproj/xcshareddata/xcschemes/Tinodios.xcscheme`：只追加新 Testable，原两个 Testable 保留。
4. `Podfile`：仅在原 Tinodios target 下追加 `inherit! :search_paths` 子 target。VLC 隔离 hook 逐字不变，新目标不进入它的 allowlist；不重复声明 App pods。
5. `Podfile.lock`：仅更新 Podfile SHA1；PODS、DEPENDENCIES、SPEC CHECKSUMS、版本与 CocoaPods 元数据未变。
6. `Scripts/ci/verify_publish_outcomes_macos.sh`：仅追加 `-only-testing:TinodiosVoiceLayoutTests/VoiceLayoutTests`；同 sim_id、Debug、loopback、免签和原时限/结果路径。原 selectors、全部旧测试源码和断言不改。

本端报告、source checker、Ruby 检查及输出另存本目录。无新 workflow；沿用 `storage.xcresult`、summary 及已有原附件导出。

## 6 方法与证据层级

| 实际 XCTest 方法 | 调用对象及断言 | 不能据此宣称 |
|---|---|---|
| testOriginalNibLoadsAndResetsWithoutRecording | 原 App SendMessageBar、Bundle 原 nib、自定义 UIKit 类、真实 recognizer 接线；未开始录音的重复 reset | 完整聊天首次离页已操作 |
| testRecordingStatesAndOriginalButtonsForwardActions | 原状态展示方法；原 XIB touchUpInside target/action → delegate spy；停止/试听/暂停/发送/放弃的准确动作 | 麦克风、真实播放器或网络发送成功 |
| testDynamicTypeDarkLightAndScrollableMinimumTargets | 真实 UIKit traits，实际字号必须增长；深浅色；260pt 组件 viewport 滚动；按钮全框可见、≥52pt、实际 hitTest、文字容纳 | 所有设备/字号和系统 VoiceOver 朗读完成 |
| testInputAccessoryKeyboardAppearsAndDismisses | UIViewController 的真实 inputAccessoryView，真实 UITextView first responder；系统 keyboardDidShow/Hide、有效屏幕几何；合成文字从不提交 | PNG 包含软件键盘像素或真实输入触摸旅程 |
| testResetAfterGestureDoesNotReusePreviousLayout | 受控 recognizer 输入 → 原 longPressed/reset；文本布局变化、重复 reset、下次 gesture 读取当前约束 | UIKit 真实触摸识别/手指滑动通过 |
| testControlledGestureHandlerUsesSameWindowAndThresholds | 原 handler 的同窗口坐标、上滑锁定后松开不发、左滑取消、正常松开发送 delegate；真实代码未提取或复制 | 真实录音或上传/服务端 ACK |

新累计**期望**为 **232 native = SDK44 + 原 UIrunner175 + VLC host7 + App component6**，独立 navigation3。新增 6 方法尚未在 Mac 执行；不是把原 226 重算为新证据。

## 真实 UI 与受控边界

- `@testable import Tinodios` 加载原 App 模块；`SendMessageBar()` 自己的 `loadNib` 装载原编译 XIB。组件放在测试专用中性 accessory 容器，不建立假聊天数据、假联系人或登录后门，也不调用 MessageViewController 的 SDK attach/read 路径。
- 原 `recordingDidStart/Stop`、`audioPlaybackPreview` 等由测试受控调用，输入波形是合成 bytes，仅验证展示。Delegate 只记录固定动作，没有录音器/播放器/网络实现。
- 按钮先核原 XIB selector，再使用真实 `sendActions(.touchUpInside)`；同时核真实 window hitTest。不是 XCUITest tap，也不是触摸识别器端到端覆盖。
- controlled recognizer 只覆写 state/location 输入，再调用完整原生产 handler；不修改生产识别器或添加后门。原 XIB 的 long-press recognizer 数量及 0.5 秒配置另外断言。
- accessory 被 UIKit 放到 input window，所以 iOS17+ 的实际 `traitOverrides` 用于该真实 view（当前 CI 模拟器是 iOS18.5），不能仅给父容器改 trait 就宣称字号改变。验证实际 trait 和 font pointSize；低系统若无法兑现不会 skip 或伪装通过。
- 每个阶段 PNG 来自已装载组件的真实 `drawHierarchy`，不是重画设计图，也不是 XCUIScreen/完整聊天截图。JSON 明确该来源。键盘真实出现/收起由系统通知和 first-responder/屏幕几何单独证实，PNG 不伪称展示输入法像素。失败 teardown 尝试保存当前组件后再清理，导出仍沿用原严格逻辑。
- JSON 只含固定 case、类/host 布尔、几何、字号、按钮固定 ID、delegate 动作；不保存输入文本、token、UID 或服务路径。退出只还原本测试 window/responder/observer 和组件状态，不清 Keychain、账号或 DB。

## 初态与宿主限制

测试运行于真实 App，因此正常 AppDelegate 启动仍会执行。要求 Info 的 `HOST_NAME=127.0.0.1:9` / `USE_TLS=NO`、Keychain 无 token、SDK/Store 无 UID、未鉴权；未知初态直接失败，不清数据求通过。沿用已授权 CI fixture 与免签环境，不连真实服务/发送 OTP。此门禁是测试开始检查，不是替代 AppDelegate 的网络沙箱；CI 编译 endpoint 仍为关闭的 loopback。

## Windows 实际检查

- `check_source.py`：21/21；核唯一 6 方法归属、原 226/导航 selectors 字节保留、CI 仅加 1 行、Pod hook 不变、依赖 lock 只改 checksum、生产目录 0 delta、关键已有 native 源字节不变。
- `run_static_policies.py`：44/44 既有 source policies；没有为了本批放宽 policy。
- 便携 **Ruby 3.3.12 / Xcodeproj 1.28.1**：实际打开完整 pbxproj 对象，核目标类型、唯一 source、原 App host/dependency、无复制 resource、原类/XIB membership、scheme 与 checksum；PASS。
- 原 15 个实际 `Xcodeproj::Config` + 原 Podfile hook 回归再次 PASS，输出重定向到本目录，未覆盖 CI21 旧结果。另用真实 Config 给新增 App-hosted target 加含 Firebase 的 App 配置，证实 VLC hook 忽略它并保留 App/新目标原 flags；不是空字符串 fallback。
- 本地首次需要补充纯 Ruby 工程解析依赖；全量 gem 安装因未装 MSYS2 被拒，未安装 MSYS2。固定 CFPropertyList3.0.9 不兼容本地 Ruby，改用符合 Xcodeproj 约束的官方3.0.7（API SHA `c45721614aca8d5eb6fa216f2ec28ec38de1a94505e9766a20e98745492c3c4c`），其余 atomos0.1.3/claide1.1.0/colored2 3.1.2/nanaimo0.4.0；全部只装在 ignored artifacts/tools，不改系统 PATH/服务。此是本地检查工具，不是 App 依赖升级。
- 实际 CocoaPods 集成、App 测试 bundle 加载、Swift 编译、6 方法与截图仍 **NOT_RUN**，交总控精确 SHA 审查后运行。

API 依据：[Apple UIGestureRecognizer/state](https://developer.apple.com/documentation/uikit/uigesturerecognizer/state-swift.property)；这里不把覆写输入当真实触摸识别。Swift 的只读属性 override 规则：[Swift inheritance](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/inheritance/)。
