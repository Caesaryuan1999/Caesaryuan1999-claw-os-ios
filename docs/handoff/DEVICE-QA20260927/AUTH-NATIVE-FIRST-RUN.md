# Auth 原函数 macOS 首次实测：失败原件

2026-09-27 本轮总控审查后，核对本地 `fe66b7f3e80fc3a521c40e046f362829f884a27a` / tracked clean / 自有 origin / 新 ref 不存在，以普通非 force push 创建 `codex/verify-ios-auth-20260927`，远端 SHA 再核一致。main 和旧 CI51 分支未改，未创建 PR 或发送评论。

北京时间 08:15:40 对既有 workflow `310211684` 发一次 `auth_only=true` dispatch，HTTP 204。排他 marker 为 `auth-native-execution/DISPATCH-ONCE.json`。[原 run 36281964469](https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios/actions/runs/36281964469)，attempt 1，auth-only job `108515388746`，08:15:54–08:16:15 完成，结论 **failure**。原 simulator job `108515389571` 为 skipped，未运行 337 项套件。

## 真实结果

- macOS 15.7.9 arm64；Xcode 16.4 / 16F6；Apple Swift 6.1.2，以 Swift 5 语言模式编译。
- 基线 `79f015f4`：compile_exit 0，runtime_exit 1，17 项中 2 通过 / 15 失败。6 个必需红回归均实际失败，属于成功复现原问题。
- 候选 `3d949814`：compile_exit 0，runtime_exit 1，17 项中 7 通过 / 10 失败。因此候选原生验收 **未通过**，没有将编译成功或部分断言通过标成绿。
- 双方生成 Swift SHA 与本地准备一致。源码/旧 17 例输入未改变；双方 compile.log 为空（没有编译诊断）。

候选通过的 7 项：当前成功呈现、当前失败不呈现、旧成功不更新新账号、旧 caller 失败不影响新账号、同 me 引用与呈现、安装 listener 且不重复订阅、重复 attach 幂等。

失败的 10 项：当前/旧 owner 的 401、403、404 保持原错误码（6 项），当前/旧 owner 的 cluster 502（2 项），其他 502（1 项），普通 500（1 项）。这些断言同时要求 `getResult` 抛出原 TinodeError/code；初版观察函数遇到其他 Error 只返回 false，**原日志未记录实际错误类型**，不能把静态推导写成已测错误文本。

## 已定位的源码路径与下一最小动作

真实 `PromisedReply.swift` 的链路：failure handler 返回 rejected Promise → `handleSuccess:239` 调用下一 Promise 的 `reject` → 下一终端 `handleFailure:249` 抛出原 Error → 上层 `callOnFailure:208–209` catch 再对同一 nextPromise `handleFailure/reject` → `reject:133–135` 发现已完成，抛 `illegalStateError` → `then:160–161` 用此新 Error 替换返回 Promise。

该源码因果可解释全部“保持原错误码”断言失败，但还须在独立诊断副本记录实际 Error 类型和描述。不会改写这次 7/17 原件或改低期望。

最小生产候选是仅把 UiUtils failure handler 的 `return PromisedReply(error: err)` 改为 `throw err`。真实 `FailureHandler` 签名明确允许 throws；这将从 callback 的 throw 路径传播原 Error，避免先完成 nextPromise 再第二次拒绝。保持 401/403/404 路由、旧 owner 门禁、502 原 owner 重连和已附着幂等分支不变，不修改整个 SDK。

后续由独立诊断副本记录原 `3d949814` 的 10 个 Error 类型，再让未改动的原 17 例验证新固定候选。总控审查增量后另触发一次新源验证；本次未盲重跑同源。

## 原件保存

全部保存在 `auth-native-execution/`：

- `collection.json`：GitHub run/job/步骤/下载元信息和 11 个原件 hash。
- `auth-native-original.zip`：artifact `10918339134`，14,235 字节，SHA-256 `f3f39edff02d1b2ed45811286c7478396c37a802082ad04bff77e50dd44305a6`，与 GitHub digest 一致。
- `auth-native-job.log`：24,112 字节，SHA-256 `8a8b68cd5b7ed203802186124be1f87b089ea9526378a954487d1d58467dcc9d`。
- `original/summary.json`、`original/red/`、`original/green/`：原始生成 main.swift、编译和运行日志、result.json；原生结果没有二次加工覆盖。

这是 macOS Foundation 下真实 Promise 和提取原函数的运行证据，Cache、网络和 UI 为受控边界；不是完整 App 编译、UIKit、iPhone、真实后端或跨端验收。原 CI51 5 项媒体失败仍开放。
