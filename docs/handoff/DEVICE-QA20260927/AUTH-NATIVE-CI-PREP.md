# 本轮 me 订阅修补：独立 macOS Swift 验证准备

本文件是可供总控审查和触发的候选，**未推送、未触发、未运行 Swift**。本地工作流/执行器提交为 `ed9d974cb85ab04f1c190fa81c69dce6603fd215`，父提交 `f79ea7f0d3412ac3fa809d63117db9a3cff1a318`。本批仅变更 `.github/workflows/ios-smoke.yml` 并新增 `Scripts/ci/verify_me_subscription_macos.py`，不改生产代码或已封 17 例夹具。

## 固定输入与验收

- 修补源：`3d9498144a8ea95a5d581d777e6b78a246128ebc`，包含 `92208c6` + `3d94981` 两生产文件修补。
- 回归基线：`79f015f47b15fd7124f81d52205de5c5508f370e`。
- 使用完整真实 `TinodeSDK/PromisedReply.swift`；从各自固定 Git 提交原样提取 `UiUtils.attachToMeTopic` 与 `ChatListInteractor.attachToMeTopic`。
- 17 例现有模板 `me_subscription_fixture.swift` 与旧适配器 `run_me_subscription_fixture.py` 不修改。执行器锁定两者 LF SHA-256、基线/候选 3 文件 hash，并要求 checkout 中生产文件与已审候选一致。
- 17 例覆盖当前/旧 owner 的 401、403、404，502 原 owner 重连，其他错误不误报成功，成功/失败呈现，以及已附着 me 的同引用、listener、零额外订阅和重复调用。
- 先编译并执行基线：必须是真实运行 exit 1 / native_status=FAIL，17 个确定名称全部有布尔结果，并至少复现执行器列出的 6 个关键回归。编译失败、挂起、少用例或无编译器不算“红测试通过”。
- 再编译并执行候选：必须 compile_exit=0、runtime_exit=0、native_status=PASS，准确 17/17 用例通过。
- 旧适配器在找不到 swiftc 时会输出 NOT_RUN / exit 0；新增执行器先要求 macOS 和 swiftc，再核原生状态、日志计数与退出码，避免将准备成功当验证通过。

候选生成 Swift 的 SHA-256 仍为 `9a00605afe58c67c7f03340db214d1f76d2e66b39a157194f7c5f9a8a2535a4b`，与上批封存的精确函数夹具一致。基线生成值为 `ac3ac9840c2422331da1cfa40aee0f19aca21b209ee35134d048d21073962ab5`。

## 工作流行为

按总控确认复用已注册 `ios-smoke.yml`（workflow ID `310211684`），新增 `workflow_dispatch` 布尔输入 `auth_only`，默认 **false**。原 simulator job 只新增 `inputs.auth_only != true` 条件；原有完整工作流步骤、命令、依赖和超时全部保留。

显式 `auth_only=true` 时仅启动新的 `auth-only` job，macos-15 / 10 分钟总超时，完整历史 checkout、`persist-credentials=false`、`contents:read`，不安装 Pods、不签名、不构建 App、不运行旧 337 项套件。原编译 120 秒、可执行夹具 30 秒超时不变。只上传 summary、生成 Swift、编译/运行/适配器日志；不上传编译二进制或使用任何业务凭据。

[GitHub 官方 workflow_dispatch 说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch)要求可调度工作流存在于默认分支。本次使用既有注册入口和新验证分支的配置，不新增默认分支修改。最终远端可调度状态仍以实际 dispatch 回执为准。

## 总控审查后的一次触发

建议只新增自有验证分支 `codex/verify-ios-auth-20260927`，指向包含 `ed9d974` 及本准备文档的最终封存 HEAD；旧 CI51 验证分支和 main 不动。总控先核分支不存在/目标 SHA 与审查输入一致，再按既有授权推送并核远端 SHA，不 force push。

对自有仓库 `Caesaryuan1999/Caesaryuan1999-claw-os-ios` 的既有 workflow 发一次 dispatch：

```json
{
  "ref": "codex/verify-ios-auth-20260927",
  "inputs": {"auth_only": true}
}
```

请求路径为 `POST /repos/Caesaryuan1999/Caesaryuan1999-claw-os-ios/actions/workflows/310211684/dispatches`。凭据从现有安全配置读取，不写入此 JSON 或日志。提交后核新 run 的 head SHA、event、输入、原 simulator job 为 skipped、新 auth-only job 为实际执行，不自动重试请求。

macOS job 实际命令：

```bash
python3 Scripts/ci/verify_me_subscription_macos.py --output build/me-subscription-auth
```

执行器依次调用已封适配器（输出目录须不存在）：

```bash
python3 docs/handoff/DEVICE-QA20260927/run_me_subscription_fixture.py --source-ref 79f015f47b15fd7124f81d52205de5c5508f370e --output build/me-subscription-auth/red --execute
python3 docs/handoff/DEVICE-QA20260927/run_me_subscription_fixture.py --source-ref 3d9498144a8ea95a5d581d777e6b78a246128ebc --output build/me-subscription-auth/green --execute
```

实际编译为 `swiftc -swift-version 5 <生成的 main.swift> -o <probe>`，随后直接运行各自 probe；基线预期的 runtime failure 由外层严格检查，不依赖 `continue-on-error` 或忽略任意非零状态。

## 已执行的本地检查

1. Python AST 解析通过；YAML 解析通过。剥离新增输入、两 job 条件和 auth job 后，与 `f79ea7f` 的原完整 workflow 结构相同。
2. YAML 核 `auth_only` 类型/default、互斥条件、唯一手动触发、读权限、不保存 checkout 凭据、auth 唯一运行命令。记录 `auth-native-ci-workflow-local.json`。
3. `rtk python -X utf8 -B Scripts/ci/verify_me_subscription_macos.py --prepare-only --output docs/handoff/DEVICE-QA20260927/auth-native-ci-prepared`：固定 hash 通过，双方真实输入已生成，**NOT_RUN**。紧凑结果在该目录 `summary.json`；生成 Swift / adapter 日志仅保留本地。
4. 不带 `--prepare-only`、独占输出 `auth-native-ci-windows-rejection`：实际 exit 1，错误 `Native execution requires macOS; no substitute runner`，证明当前 Windows 不会返回原生 PASS。不是 Swift 编译测试。
5. `git diff --check` 通过，生产目录无本批差异。所有必要文件 hash 由 `AUTH-NATIVE-CI-PREP-SEAL.json` 封存。

本地检查发生于工作树提交前，准备结果中的 checkout_sha 为 `f79ea7f`；当时新增配置与本提交一致，受测生产文件固定为 `3d94981`。本地 NOT_RUN 原件未事后改写为新 SHA 或通过。

## 结果解释及回退

成功时仅证明：上述两原函数与真实 Promise 在受控 Cache、Tinode、Topic 和 UI 边界中能通过固定 17 例 Swift 运行。真实 Cache 锁/Keychain/SQLite、完整 UIKit 编译、真实网络、iPhone、跨端均不在这个夹具内，不得标为已验收。CI51 旧 5 项媒体失败继续开放，不能因 auth job 通过而关闭。

失败时保全首次 compile/runtime/summary 原件，区分夹具边界不匹配、Swift 编译错误、基线未复现或候选真实断言失败；先定位明确原因，再协调必要增量，不循环盲跑。验证分支独立，不合 main；撤销本测试配置可单独审查 revert `ed9d974`，不回退生产修补或删除已有证据。
