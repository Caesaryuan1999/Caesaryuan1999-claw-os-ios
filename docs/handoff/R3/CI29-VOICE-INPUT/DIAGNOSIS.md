# CI29：输入生命周期与按钮图像可见性（只读诊断）

候选 e1ed950147233f8e9df05ad025e5e356d0097dae；run 35357924685 / job 105641753202。实际 SDK44、UIrunner175、VLC7 全通过；Voice6 为 5 通过、1 失败，共 231 通过 / 1 失败，导航、打包、冷启动未运行。唯一失败是 VoiceLayoutTests:178 的 currentImage 仍为 mic。原 ZIP SHA 和两张原 PNG/两份 JSON 已独立逐字节对照，见 diagnosis.json；不覆盖旧失败。

## 已确认的前置差异

`VoiceLayoutTests.swift:176` 从刚加载、未编辑的输入框直接赋非空 text，然后调用真实 textViewDidChange。`PlaceholderTextView.swift:118–122/132–136` 在空初态显示 placeholder；`:55–58/149–154` 对非空的程序赋值不清 isShowingPlaceholder，`:67–68` 因而仍返回空 actualText。真实 begin-editing 通知在 `:140–145` 清这个标记。`SendMessageBar.swift:717` 按 actualText 是否为空选择发送/录音，这是当前生产判定；不是 Spy 缺少回调造成的错误。

真实消息编辑赋值入口 `MessageViewController+MessageCellDelegate.swift:386–388` 和 `:523–525` 均先使输入框成为 first responder，再赋原消息文字。本轮成功键盘测试在 `VoiceLayoutTests.swift:265` 同样先进入编辑、等待完整键盘几何，之后赋合成文字。

原 `8D8A6964-D2F8-4F86-975B-82D4EEC33A1F.png` 已目视为单行纯“发送”，无麦克风；配套 EC839 JSON：firstResponder=true、currentImage=false、title=发送、64×48。失败 teardown 原 8E035 PNG 为麦克风；6080 JSON：firstResponder=false、currentImage=true、title为空、48×48。这与源级前置差异一致。原 JSON 没有 actualText，不能把推导写成已记录的运行字段。

## imageView 非空不等于图像可见，但原证据尚缺几何

同一成功 EC839 JSON 的 `imageViewHasImage=true`，原 PNG 没有图标。因此只要求 `imageView.image == nil` 比用户可见要求更强，不能据此再次更改生产按钮。Apple 把 [currentImage](https://developer.apple.com/documentation/uikit/uibutton/currentimage) 定义为当前显示图像；[imageView](https://developer.apple.com/documentation/uikit/uibutton/imageview) 是按钮托管的图像子视图，文档未保证清 normal-state image 后该子视图的 image 对象也清空。这里不推断 UIKit 具体缓存实现。

[isHidden](https://developer.apple.com/documentation/uikit/uiview/ishidden) 文档说明隐藏视图仍在层级中，祖先隐藏也会隐藏后代；[alpha](https://developer.apple.com/documentation/uikit/uiview/alpha) 的零值完全透明，祖先透明度影响后代。若涉及几何裁剪，应按 [clipsToBounds](https://developer.apple.com/documentation/uikit/uiview/clipstobounds) 的真实值，不能把任意零 bounds 或离开父 bounds 自动解释为不可见。

CI29 未记录 imageView 的 hidden/alpha/bounds/frame/window 或祖先状态，因此尚不能断言究竟哪条机制使原图标不可见。不能用 currentImage=false 单独替代无可见残留图像的要求。

## 待冻结的单测试文件修正

仅 VoiceLayoutTests.swift：在原空→字→空方法中先执行真实 becomeFirstResponder 并检查当前 first responder；再赋合成文本、确认 actualText 与合成值一致后调用原文本变更方法。保留配置 nil、currentImage nil、标题、单行文字宽高、按钮尺寸、回空原录音图片及零发送等原业务断言；不触碰 PlaceholderTextView/SendMessageBar 或原生六方法数量。

将内部 image 对象 nil 的过强要求改为有证据的不可见判定前，需总控/后端批准。建议在稳定布局后、主线程只读记录 imageView 及祖先的 hidden、alpha、bounds、window、转换后位置，并先断言原按钮本身在真实 window 内且可见。仅接受无图像对象、图像子视图已不在 window、或存在 hidden/alpha 严格为零的节点；没有已证不可见原因时仍失败，不只凭缓存存在与否判断。几何为零/裁剪但以上条件不成立时，先保留失败和证据，不猜测放行。

原 PNG 原样保留；追加 JSON 仅记布尔/几何/固定类别及合成输入长度或相等布尔，不写实际输入内容。当前只是只读诊断与提案，未修改测试、生产或 CI。官方 Markdown 在浏览工具不支持其 MIME 后从同一 Apple URL 直接读取，下载 SHA 留在 diagnosis.json。
