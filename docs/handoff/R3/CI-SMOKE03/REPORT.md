# CI-SMOKE03：CI13 分层证据与 CI14 待验候选

记录日期：2026-09-18。本报告只补充本端交接；不修改生产代码，不重封累计补丁。

## CI13 实际通过的层级

- 精确源码：`a06f49a353b7a115edca64dc11526a1243859597`。
- Run：`35313543115`。
- SDK **41 / 41 PASS**，storage/business **140 / 140 PASS**，合计 **181 个原生方法**。
- 独立真实 App 导航 **3 / 3 PASS**，不计入上述 181。
- Artifact：`10534073578`；下载 ZIP SHA-256：`a809c3d073359b26946f82b2ef2c7fbe37969471cde9861fc0e75a0143eb7255`。
- 根证据目录：`artifacts/integration/20260918/R3-ios-ci13-evidence/ios-01-a-20260918-060752`。原始 ZIP 内另有完整 `navigation.log` 与 `navigation.xcresult`；根目录最初仅提取部分 summary 与 smoke manifest。

| 真实 App 方法 | 结果 | 耗时 |
| --- | --- | --- |
| `testKeyboardInputAndDismissalAcrossIdentityForms` | PASS | 91.809 秒 |
| `testLegacyEntryCanBeFullyRevealedAndSwitchedBack` | PASS | 25.111 秒 |
| `testRegistrationAndResetReturnToLogin` | PASS | 21.492 秒 |

这些测试真实启动模拟器 App，验证注册/找回与返回、合成手机号/邮箱/密码输入、软件键盘出现与收起、输入框未被键盘遮挡，以及完整显示并点击原账号入口。没有提交登录或验证码，没有清数据强行进入已知状态，没有完成真实注册/找回，也没有连接真实身份服务。

`keepAlways` 附件是真实 XCTest 截图。CI13 将其保留在 result bundle；本报告不宣称已单独导出或由总控完成目视验收。方法通过不等于截图设计验收。

## 独立 cold-launch smoke：在 launch 前 FAIL

`launch-smoke/manifest.json` 记录同一选定设备 `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9`、iOS 18.5 的顺序：

1. 设备可用，但状态为 `Shutdown`。
2. boot、受限 `bootstatus -b` 和复查均成功，状态变为 `Booted`。
3. install 与 installed-container 查询成功，安装后的可执行文件哈希匹配已测试文件。
4. 无条件 `terminate_previous` 超过原定 **45 秒**。
5. 尚无 `launch` 调用、启动 PID 或该轮 cold-launch PNG。

已打包的模拟器 App ZIP SHA-256 为 `a8bc6a53e95b54e8e6718a48fc73488aec777f707dbc9f1189c3c551d148813a`。打包成功不能替代冷启动成功。

`navigation.log` 第 2913、3055、3181 行分别记录 Terminate PID 22142、25080、26334，随后各方法 PASS。最后一次 teardown 约 1.08 秒返回。navigation summary 完成于 `06:21:07.237 UTC`，smoke 开始于 `06:21:23.094 UTC`，间隔约 15.857 秒。

原测试 teardown 已调用 `XCUIApplication.terminate()`；Apple 的 [应用状态契约](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/state-swift.property) 明确成功返回时为 `notRunning`。没有证据表明再加一次相同 teardown 调用可以修复本次问题。

确定失败点是随后无条件执行的 `simctl terminate`。CI13 未记录紧邻该调用之前的 PID 状态、各命令耗时或 CoreSimulator 内部诊断。因此：

- 尚不能证明 App 崩溃、旧进程残留，或某个 CoreSimulator 内部根因。
- CI12 的 cold-launch PASS 不能借作 CI13 的证明。
- CI13 在独立 smoke 层仍为 FAIL；其 181 + 3 项真实测试通过事实保留。

## CI14 候选与精确范围

候选：`56c4a7f609cd0103a9b26604fb404d319f97ed48`；父提交：`a06f49a353b7a115edca64dc11526a1243859597`。恰好修改四个测试/CI 文件：

| 文件 | 变化 |
| --- | --- |
| `Scripts/ci/smoke_simulator_launch.py` | 启动前确认进程状态；条件终止并复查；记录命令耗时。 |
| `docs/handoff/R3/CI-SMOKE/check_smoke_runner.py` | 实际 runner 与附件导出代码的受控回归。 |
| `Scripts/ci/verify_publish_outcomes_macos.sh` | 按当前工具帮助导出原始导航附件，保留原测试失败码优先级。 |
| `.github/workflows/ios-smoke.yml` | 即使失败也上传导出状态、help/log 和原始附件。 |

进程检查只从 `/bin/ps` 读取 PID 与 `ucomm`，精确匹配可执行文件名称后，才调用已有 Darwin `proc_pidpath`，与当前设备 UUID 下安装后的精确路径比较。不写出其他进程参数或全量进程列表。已知其他设备路径被排除；查询失败、PID 路径不可解析、记录格式错误/重复、同设备下路径不符均保持 FAIL。

只有确认无目标进程才跳过 terminate。若目标正在运行，必须终止成功，并再次枚举确认消失才可 launch。超时、残留和未知状态均阻止启动。原 **45 秒**命令限制不变，没有 force-kill、模拟器重置、重启或自动重试。安装哈希、启动 PID/路径、PNG 与针对本 PID 的 crash 门禁保留。

该变化为冷启动补上可观察的前置条件，并避开没有必要的无条件终止操作；不能称为已证明修复 Apple 内部卡住原因。

附件导出先执行并保存当前 runner 的 `xcrun xcresulttool help export attachments`，确认 `--path` / `--output-path` 后才运行 export；不加 `--only-failures`。依据 Apple 的 [Xcode 16.3 工具说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes)，以运行时 help 为当前接口依据；测试使用的 [截图附件初始化器](https://developer.apple.com/documentation/XCTest/XCTAttachment/init%28screenshot%3A%29) 生成 PNG。

原始导出 PNG 不重编码，记录 SHA、尺寸、字节数和相对路径，原工具 metadata 同时保留。无 navigation bundle 为 NOT_RUN；导出失败为 FAIL，不能当成可查看图片证据。已有测试失败码优先，导出结果不能替换或掩盖它。

## 已完成的本地检查

- **35 / 35 受控 Python 方法 PASS**：27 个 smoke runner 案例，加 8 个执行实际 export heredoc / Bash cleanup 退出代码的案例。
- **44 / 44 源码政策脚本 PASS**。
- Python 语法、Git Bash 语法与候选 diffcheck PASS。
- 三段原有 `xcodebuild test` 命令在行尾归一后逐字相同。
- 原 **181 个原生方法 + 3 个真实 App 导航方法**的测试源、断言和 selector 均未修改。
- 生产代码变化 **0**。

以上属于 Windows 上受控命令边界与源码检查，不是 macOS 实际进程枚举或 `xcresulttool` 执行证明。总控已独立重跑 35 个受控方法并全部通过。

本端复验命令：

```text
rtk python -B docs/handoff/R3/CI-SMOKE/check_smoke_runner.py
rtk python -B Scripts/ci/run_static_policies.py
rtk git diff a06f49a353b7a115edca64dc11526a1243859597 56c4a7f609cd0103a9b26604fb404d319f97ed48 --check
```

## 等待 CI14

总控已审查固定四文件 diff，将精确 `56c4a7f` 推送至已授权验证分支，并报告 14:42:36 手动 dispatch 返回 HTTP 204。本报告写入时尚未收到 run ID 和最终结果。

后续应分列验收：

- SDK 41 + storage/business 140 原生方法。
- 真实 App 导航 3 方法及其原始截图。
- 当前工具 help、export 状态、原始 PNG 哈希与总控目视结论。
- 同一设备的进程前置证明、cold launch、安装/运行二进制身份、PID 存活、PNG 与 crash 结果。

证据到达前不宣称新成功。真机、签名、APNs、真实身份投递、真实服务联机与全量 UI 旅程不在本单元验收内。累计交付补丁暂不重封。
