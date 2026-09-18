# AUTH-CAPABILITIES-COPY

起点：036375fb19770fbabe9122490900665a37a63996；分支 codex/r3-20260918-ios。开始 dirty 0，自有 origin；不推送、不改共享资料。

## 证据与范围

CI14 56c4a7f 的 SDK 41 + storage 140 和真实 App 离线导航 3 方法通过。原截图 C2257385-B3C9-4DD5-BB7B-96A73A540A95.png 在找回密码尚未提交时显示“网络请求结果未确认”。实际入口为 capabilities GET → transport → Flow.prepare → 页面 error.message，无验证码或密码提交。原成功与截图缺口同时保留。

仅 1 生产文件 Tinodios/ClawIdentityService.swift：capabilities 方法只将 transport 映射为 capabilitiesConnection，显示“暂时无法连接身份服务，请检查网络和连接设置后重试。”。其它错误原样返回；所有 POST、共用 request、invalidResponse、服务端错误、重试请求冻结、旧账号兼容保持。无 wire/配置/持久结构变化。

测试 TinodiosUITests/IdentityFlowTests.swift 新增 1 方法，实际 URLProtocol + 生产 Service/Flow 验证 GET、无 body、失败专用错误、无待提交请求、旧账号入口可用及再次 prepare 成功。增强既有 uncertain challenge 方法，明确 POST 仍 transport/原未知文案，原相同 body 重试断言保留。仅网络响应受控，不是真实服务/OTP。

## 检查与下一候选

Windows 44/44 现有源码策略通过；source-checks.json 逐段比对 POST/共用请求及 Flow 未改变。diff --check 通过。原生未在 Windows 编译或执行。

现有 CI 按整类选择 IdentityFlowTests，无需变更 selector。期望 SDK 41 + storage 141 = 182 原生，另导航 3；这些是待 Mac 执行数量，不是本提交通过数。CI14 实际仍为 181 + 3。

回退仅本提交的 Service 和测试差异，无数据库迁移。尚不封最终累计补丁，待密码截图补证及总控精确 CI。
