# Auth 原生红后最小修补与增量 CI 审查包

生产修补：`a29f141b00c6adec2c316a27c39f365ff3e285e0`。独立诊断配置：`2a712a8f24e754bb7a2cb9187ed9b5aee62620ae`。本地分支 `codex/r3-20260918-ios`。两提交均未推送，未触发增量 CI；下面是准确可执行输入，不是原生通过报告。

## 从原始失败定位

已实际运行的 `fe66b7f` / GitHub run `36281964469`：原 17 例基线 2 过 / 15 失败，原候选 `3d94981` 7 过 / 10 失败，双方 Swift 编译成功。原件、hash、所有布尔失败在 `AUTH-NATIVE-FIRST-RUN.md` / `auth-native-execution/original/summary.json`；首次观察器没有打印实际 Error 类型，不事后捏造这些数据。

真实 Promise 的 failure-handler 返回类型为 `((Error) throws -> PromisedReply<Value>?)?`。返回 rejected Promise 会进入 `handleSuccess:239`，触发下一终端 Promise 的 reject；终端再抛原 Error，上层 `callOnFailure:208–209` 捕获后对同一 nextPromise 再 reject，变成 `illegalStateError`。同期独立源码复核也确认此路径；`Topic.subscribe:651–660` 已采用直接 `throw err` 的相同调用范式。

这里有两个时间路径，不能混为一谈：已完成 Promise 上稍后注册 handler 时，`then` 的 catch 会将新错误替换到返回 Promise；先注册再异步 reject 时，返回 Promise 已交给消费者，终端抛错及已接 caller 的恢复行为可能不同。追加测试专门区分这两类。

## 生产差异及兼容

只变更 `Tinodios/UiUtils.swift`：把 `.thenCatch` 末尾 `return PromisedReply<ServerMessage>(error: err)` 改为 `throw err`，并修正两行说明。真实签名允许 throws；新路径直接进入一次 `handleFailure`，避免先通过 `handleSuccess` 完成同一 nextPromise。

401/403/404 使用捕获 owner 退登、502 原 owner 重连、当前 owner 检查、已 attached me 幂等采用、ChatList 传递 owner 和 UI 门禁均不变。没有改 SDK、SQLite、Keychain、主动退出/注销、协议字段、超时或旧数据。

新 UiUtils LF SHA-256：`49a1ca6d0f0ffaa3360cc4b8eb579682e16faf50dce6412bec9f1d0ed6ebb321`；ChatList 和完整 PromisedReply 的 hash 不变。源策略仅更新为核实际 throws 路径和 SDK 声明，属于源接线证据。

## 同一次增量 CI 中的两组独立测试

原 `me_subscription_fixture.swift` 与 `run_me_subscription_fixture.py` 逐字/hash 不变；原 17 例的预期和计数不变。

| 阶段 | 固定源 | 验收 |
| --- | --- | --- |
| 原 17 例 red | `79f015f47b15fd7124f81d52205de5c5508f370e` | 编译成功；6 个已规定核心断言实际失败；runtime FAIL |
| 原 17 例 green | `a29f141b00c6adec2c316a27c39f365ff3e285e0` | 编译成功；精确 17/17；runtime PASS |
| 追加诊断 pending_red | `3d9498144a8ea95a5d581d777e6b78a246128ebc` | 编译成功；精确 50 例；10 个 completed 原错误保留诊断重现失败；runtime FAIL |
| 追加诊断 pending_green | `a29f141b00c6adec2c316a27c39f365ff3e285e0` | 编译成功；精确 50/50；runtime PASS |

追加 `me_subscription_pending_fixture.swift` 只复用原受控边界定义，仍注入完整真实 Promise 和原样 helper/caller。原 17 例源码不重写。

追加 10 个 completed 样本对应上次全部失败码路径，输出 Error 具体类型、描述、code/text/what。追加 40 个 pending 组合为 401/403/404/502/非 TinodeError 对象 × 当前/替换 owner × 调用线程/后台线程 × helper 终端/已接 ChatList caller。均先挂实际函数链后 reject；后台用真实 DispatchQueue 和 semaphore await，记录实际线程。

helper 未接下游时分别观察 reject 调用线程抛出的 Error 与 helper.getResult 的 Error，保留 code/text/what 或自定义 Error 引用身份。ChatList 已接下游时让其实际 failure handler 消费终端，不额外对同一 Promise 调两次 then；检查无错误成功呈现、原 owner 的退出/重连次数及替换 owner 无副作用。后台等待超时立即输出失败并退出，避免继续读取仍被工作线程使用的数据。

**边界仍为受控 Cache / Topic / UI**，不测试真实 Cache 锁、SDK WebSocket、Store、Keychain 或 UIKit。即使追加 50 项通过，也不能称真实设备或网络并发通过。

## 配置、命令与原件

工作流仍为上轮已审 `ios-smoke.yml`，本批无 YAML 变化。只有显式 `auth_only=true` 运行此入口，原完整测试默认行为保持不变。runner 固定 3 组源 hash、原 17 例模板和适配器 hash、新独立模板 hash；不允许悄悄换输入后沿用通过结论。

实际 macOS 命令仍为：

```bash
python3 Scripts/ci/verify_me_subscription_macos.py --output build/me-subscription-auth
```

前三组生产文件从固定 Git SHA 提取。4 个阶段各自 `swiftc -swift-version 5`，每次编译 120 秒、可执行程序 30 秒；追加 pending 的每个 await 为 3 秒。没有提高原用例阈值、安装 Pods 或运行整套 337 项。

每阶段独立保存 `main.swift`、`compile.log`、`runtime.log`、`result.json`，总 summary 保持 17 与 50 两组计数分开。workflow 现有 artifact 通配符已包含 `pending_red/` 和 `pending_green/`，无需新权限。

建议总控审查后使用新验证分支 `codex/verify-ios-auth-throw-20260927`，指向包含本说明的固定 HEAD，先核不存在和远端 SHA；对既有 workflow 310211684 发一次 `auth_only=true`。这只是建议的执行对象，尚未推送或触发；原 `codex/verify-ios-auth-20260927@fe66b7f` 首次失败记录可保持原样。

## 已执行检查

- 新源策略对原 `3d94981` 为 8/9 红，对新工作树为 9/9 绿；记录 `auth-throw-{red,green}-source.json`。
- 45/45 本地静态/宿主 SQLite 脚本通过，见 `static-after-auth-throw.json`。不等于 Swift 或 iOS 构建。
- Python AST 解析与 `git diff --check` 通过；原 17 例模板 hash 与 `fe66b7f` 一致。
- 固定输入生成成功，四阶段均 **NOT_RUN**，见 `auth-throw-ci-prepared/summary.json`；输入生成时 HEAD 为 `a29f141`，当时诊断文件已在工作树，本准备原件不事后重写。
- 原 17 green 生成 SHA `7418d2021310b5ddaeedc3366f377415838955487c0f1b57356fca23105eb180`；pending_red `e3cce38fe51f61cc28a5d90f8d164dd3d36aef44bc4d84aff0168a8db9647083`；pending_green `9e2eee03e8e8408d61e2705ab6c80e0ef69411bd6467f409f97cec13012051b1`。

增量 CI 完成前，生产修补为待原生验证候选。此前 CI51 图片/音频 5 项失败、完整 App 构建、iPhone、Android/iOS 跨端仍未关闭。若增量失败先保留原件与具体错误类型，再定位，不重跑同源或修改通过标准。
