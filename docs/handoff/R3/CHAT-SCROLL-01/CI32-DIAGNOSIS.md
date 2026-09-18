# CI32 · 三失败与限定后继

固定失败源码 `fdedf825490ea9fa420b54033e8c48d65f8fc8aa`，原交付 `e30e7bcd13458cb6a6cb569686eefcf35ee571e6` 均保留。本报告仅解释原件与后继两文件，不覆盖旧结果或重封 13 路径包。

原 ZIP：根 `artifacts/integration/20260918/R3-ios-ci32-evidence.zip`，SHA256 `7e8c23f27e8f5edbe63176fc4ed772183db36cc42c167365ee929cec8d6e275c`。ZIP 内前缀 `ios-01-a-20260918-171147/`。实际 SDK 44 通过，storage 195 通过 / 3 失败 / 0 跳过，其中原 188 全通过、新 ChatScroll 10 方法为 7 通过 / 3 失败；合计 239 通过 / 3 失败。导航、打包、冷启动未执行。

## 1. line199：几何快照不完整，不是已发生滚底

原 `95F2A055-062A-47B3-9B32-D69292141990.json` 终态为 offset 310、first anchor 6 / -10、interaction 5、43 行；原 PNG `4645065A-F999-45FB-8BDB-A31340C8103D.png` 为历史位置与“回到最新消息”按钮。没有拉到底的证据。失败期待的 anchor 8 来自测试在 `setContentOffset(310)` 后立刻调用生产 capture；该函数以 `indexPathsForVisibleItems` 的可见 cell 候选作为几何全集，未先完成此次布局，可能漏掉新进入顶端的 6/7。原新位置在刷新完成后仍为 310，不能把失败描述为定位票据被消费。

生产展示入口同样直接调用此 capture，因此仅在测试前强制布局会留下生产快照不完整。限定修正：在 `MessageViewController.captureChatViewport` 先 `layoutIfNeeded`，然后读取当下 offset/insets，以有效 viewport 询问 layout elements，过滤 `.cell` / section 0 / 合法索引 / 相交元素。没有包裹新的 programmatic suppression，未知滚动仍可使意图代次失效。

只读核 `MessageViewLayout.swift:74–89`：原实现遍历 cell 属性缓存并按相交返回，同时无条件附带 header，故必须过滤 `.cell`；不修改此布局文件。原测试保留 anchor/pixel 断言，再以 FlowLayout 的**逐项**第 6/7 项属性独立核首项跨过 viewport top、相邻项仍在 viewport、快照前两身份 6/7、前后 offset 310 及迟到票据未消费，不用同一枚举生成自证期望。

## 2. line301 与 FilePreview121：预览尚未完成 push / 测试实例缺原 outlets

原测试 push 后立即执行发送；等待仅用 coordinator=nil 或原聊天 view.window 是否存在，不能证明新的 push 已显示、随后的 pop 已完成。capture 的生产门禁检查实际导航 stack.last；本轮该检查仍返回票据，说明失败点并未取得“预览已离栈”的证据，不能通过放松 capture 解决。

原 `E7A2C094-92F0-4053-B2AF-F1CBDB445822.ips` 精确堆栈：teardown `drawHierarchy(afterScreenUpdates:true)` → UIKit `startDeferredTransitionIfNeeded` → UIView 移入 window / trait 更新 → `FilePreviewController.traitCollectionDidChange` → `setInterfaceColors`。原 `NeutralFilePreview` 抑制 viewDidLoad、仅手工补 sendButton，fileNameLabel 等 IUO 没有连接，所以 line121 崩溃。此证据确认 fixture 不满足真实控制器要求，未证明原 storyboard 页面有同一崩溃。

限定测试修正：实例化原 Main.storyboard 的 FilePreviewController，在 load 前设置合成内容，使用其真实按钮与原发送 handler。先观察本次真实 nav didShow、top/visible/parent/window 与无 transition，才执行按钮；发送后等待原聊天 didShow、预览离栈，再保留“不能再次捕获”断言。原 notification 消费者 interactor 仍为 nil，没有发布、上传或服务端接收。删除缺 outlet 的测试子类，不修改 FilePreview 生产代码。

## 3. line260：容器完成条件不成立，不能直接调用 appearance 回调

原 pop 返回和 parent=nil 断言已通过，但退休标志仍 false；原件没有 didMove(nil) 事件记录，不能据此声称该回调已经完成。storage.log 21832–21833 明确警告直接调用 viewWillDisappear/viewWillAppear 不受支持。原终态 PNG `E7E61474-ABBB-4D75-BCCB-FBA19D602591.png` 全黑，日志又提示对离开可见 window 的 view 截图，不作为有效页面证据。

限定测试修正：初始 fixture 就有真实前一页；受控取消用配对 begin/endAppearanceTransition，仍准确称非触摸手势。真实 pop 等 navigation didShow 与测试子类观察到的实际 didMove(nil) 回调，才核原 parent/retired/source 与旧来源拒绝。观察器只在 `super.didMove` 后累计次数，不手写退休标志，不手调 didMove，不改生产退休方法。若 3 秒内真实事件不达，仍失败。取消后保留页面时保存 PNG；离栈后只保留明确 window=false 的 JSON，不生成黑图冒充页面。

## 检查与边界

仅 `Tinodios/MessageViewController.swift` 和 `TinodiosUITests/ChatScrollTests.swift` 改代码，生产只有 capture 方法；其余八源、原 232 用例、CI selector/workflow/时限、SDK/DB/publish 不变。原 10 方法不增减，七个非失败方法正文不改；共享 fixture 改为真实导航完成事件门禁。等待仍每次 3 秒、只让出 RunLoop 到条件达成，不固定延时、不禁动画、不放宽容差或原断言。

Windows 已执行 44/44 源策略；源/原件限定核查见 `ci32-successor-checks.json`。新原生运行 **NOT_RUN**，下一期望仍 242 原生 + 导航 3。第二/三项需新 Mac 运行才可关闭；第一项补齐真实几何枚举，但当前原件只证明终态未滚底。原 MessageViewLayout 全页面布局、触摸交互返回、真实附件异步上传仍未因此成为已验旅程。

官方依据：[visible items](https://developer.apple.com/documentation/uikit/uicollectionview/indexpathsforvisibleitems) 列出可见 cells；[layout attributes](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/layoutattributesforelements(in:)) 提供指定坐标矩形的各类元素几何，须过滤元素类型；[appearance transition](https://developer.apple.com/documentation/uikit/uiviewcontroller/beginappearancetransition(_:animated:)) 要求容器用配对 API 而非直接调用 appearance 方法；[didMove](https://developer.apple.com/documentation/uikit/uiviewcontroller/didmove(toparent:)) 说明子控制器移除及转场完成通知。此处只引用公开契约，不把本轮没有记录的 UIKit 内部时序当已证事实。
