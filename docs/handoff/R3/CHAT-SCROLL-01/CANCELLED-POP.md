# CHAT-SCROLL-01 · 取消交互返回窄修

父候选：`0a3c145d2f5c8d8d27b578617d206c17ddb1ef87`。该候选未推送、未执行 Mac CI；原候选及其临时 unit 包保留，不用本报告回写为已通过。

## 原反例与修正

原 `viewWillDisappear` 在 `isMovingFromParent || isBeingDismissed` 时永久设置 `chatPageRetired`。交互返回开始后取消，原页面仍在导航栈，但此标志不恢复，后续 `chatDisplaySource` 变成 nil，真实呈现入口会拒绝更新。这是已确认源码路径反例，尚非本机手势运行红测。

本次仅改 `MessageViewController.swift` 与原 `ChatScrollTests.swift`：离页仍立即失效 UI 定位意图；退休移到 `didMove(toParent: nil)`，在实际子控制器移除后拒绝原页面来源。原录音离页清理、发送、权限、数据库、九文件其余实现、CI 选择与预算均不变。

Apple 的 [notifyWhenInteractionChanges 文档](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/notifywheninteractionchanges(_:)) 描述取消交互转场时原控制器重新收到 `viewWillAppear`；[didMove(toParent:) 文档](https://developer.apple.com/documentation/uikit/uiviewcontroller/didmove(toparent:)) 说明容器完成转场后通知子控制器，`removeFromParent()` 在移除后自动调用此方法。测试覆盖属性的 [isMovingFromParent 声明](https://developer.apple.com/documentation/uikit/uiviewcontroller/ismovingfromparent) 是只读 `get`。

## 测试与覆盖边界

在原第 7 个方法内增加：受控 `isMovingFromParent=true` → 原生产 `viewWillDisappear` → 恢复并调用 `viewWillAppear`，确认旧意图代次失效而来源仍可呈现；随后为实际 `UINavigationController` 添加前一页，执行非动画 `popViewController`，确认真实移除、退休，以及原来源迟到呈现被拒绝。取消过程是受控 UIKit 回调，不是交互手势；pop 是真实容器操作。

保留原 10 个方法、其它 9 个方法正文和所有既有断言。中性 cells / FlowLayout 与完整 MessageViewLayout、真实聊天旅程的区别仍按原 REPORT。原 232 回归与导航 3 不变；新总数 **242 原生 + 导航 3 仅为下一 Mac 期望**。

Windows 已执行原 44 个源策略，44/44，通过记录 `cancelled-pop-static.json`；两代码文件 `git diff --check` 通过。没有 Swift 编译、UIKit 运行或设备结果。具体源码绑定与保持项见 `cancelled-pop-checks.json`。

## 路由范围与交付

只读核当前构造：`UiUtils.routeToMessageVC`（约 424–464 行）与 `presentChatReplacingCurrentVC`（约 918–936 行）均 push；Main.storyboard 的 `Chats2Messages` / `ArchivedChats2Messages` 为导航中的 show。未发现直接 modal 创建 MessageViewController 的入口。本次退休覆盖实际导航子控制器移除，**不宣称覆盖未来直接 modal 或整体容器 dismiss 而未移除子控制器的生命周期**。

只由总控审查后推送与执行 CI。本次不重封旧源包或 `0a3` 临时包；如撤回整套滚动单元，应使用已封 CI31 / `1b20ec2` 安全源包，不把带本反例的 `0a3` 当运行验收版本。
