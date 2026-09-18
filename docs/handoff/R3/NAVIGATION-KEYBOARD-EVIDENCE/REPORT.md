# NAVIGATION-KEYBOARD-EVIDENCE

起点 65e689554702cc81d4baae33ba8b007d7c8273dd，分支 codex/r3-20260918-ios；开始 dirty 0。仅修改 TinodiosUITests/IdentityNavigationUITests.swift 与本端报告；生产、工程、selector、workflow 均不变。没有推送。

## 原证据与缺口

CI14 56c4a7f/run35316061181/job105507851181 实际 SDK 41 + storage 140 = 181，以及真实 App 离线导航 3 方法均通过。官方导出的 EB47D5C4-9807-4AFA-82D4-1CF7CFCFF806.png 密码框为空、键盘区无软件键盘；原图保留，不以方法通过代替画面验收。

原 navigation.log：t34.54 secure type；36.70 读取 Keyboard frame；36.89 添加 login-password-keyboard 并再次检查 Keyboard；37.04 才点击背景收起。此顺序不支持“先收起再截图”，但不能排除截图呈现差异；也未证明系统安全遮挡是原因。原密码非空断言可能让 placeholder 通过，原图不足以证明密码输入和键盘视觉状态。

## 本次限定补证

原 3 方法、所有既有断言、实际输入与收键盘动作保持。四处键盘截图现在都在截图前后直接读取实际 App/field/keyboard，断言前台、键盘存在且可点击、非空 frame、屏幕交集、输入完整可见且未被键盘遮挡。

密码仅合成 NavigationOnly42，不提交：保持旧非空断言，增加值非 placeholder/label 与 16 字符合成长度检查。不输出输入字符串；值检查失败也只报告布尔和长度。没有切换生产 secure 属性、显示真实密码或添加绕过路径。

每处原 App 截图名称保持，另保留同阶段 XCUIScreen.main 原始截图；均 keepAlways。前/后各附 public.json：阶段、uptime、前台/存在/可点击布尔、App/field/keyboard 几何与相交状态；密码仅字符数/预期数/非占位布尔，无原值、placeholder文本、accessibility树或凭据。状态附件在断言前写入，便于失败时读取。原 CI 当前帮助验证的 export attachments 会同时导出，不加工 PNG。

## 检查与限制

Windows source-checks.json 全通过；原 2 个非键盘方法、enter/dismiss 函数逐段不变，原所有断言行完整保留；git diff --check 通过。Swift/App/键盘未在 Windows 执行。

加上前一 AUTH 专用提示提交，下一 Mac 期望 182 原生（SDK 41 + storage 141），导航仍 3；不是新增 4 个导航测试。原 CI14 181+3 成功记录不改。

若原始截图仍空白，继续按安全状态附件、App/全屏原图与动作时间判断；不自动以 green 方法或推测系统限制关闭。未知状态/长度不符/键盘消失仍失败，不放宽断言。当前不封 FINAL 累计包。
