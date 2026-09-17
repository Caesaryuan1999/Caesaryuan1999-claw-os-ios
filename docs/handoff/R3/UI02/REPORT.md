# R3 UI02 — 聊天气泡、输入和附件呈现

状态：候选源码已完成，Windows 有界检查通过。UIKit 编译、真实录音手势、模拟器和设备操作 **NOT_RUN**，由总控精确提交 Mac 验证。

基线 UI01：7a0966ae6401d529f63a21708059f12bb838c8d0。仅 3 生产文件及 3 个旧设计策略变化；SDK / DB / C3 / MessageInteractor / 认证实现不变。

| 生产文件 | 本批变化 |
|---|---|
| Tinodios/MessageViewController.swift | R3.D1 气泡上限 360 / 可用宽度 0.76（包含内边距）；14 内容边距；浅深语义色、onBrand 发送文字；16 正文和 12 日期/状态基础字号；字号改变复用既有保留位置重绘。 |
| Tinodios/widgets/SendMessageBar.swift | 有文本显示“发送”，编辑显示“保存”，空输入保留录音图标及说明；标题宽高随字体计算。输入上限四行，超出滚动；录音和波形预留按钮空间。附件标题与标签动态字体、VoiceOver 名称，原相册/拍摄/文件事件不变。 |
| Tinodios/widgets/SendMessageBar.xib | 发送宽高解耦，48 最小尺寸；附件入口 48；placeholder 统一输入消息。所有既有 outlet、action、ID 保留。 |

MessageBubbleDecorator 已有 18 圆角，无需改动。无新网络请求、消息状态、重试、编辑负载生命周期、持久列或协议。键盘观察、历史加载、选择/撤回及媒体业务不改。

验证：
- policies-before-update.json：33 项中 30 通过 / 3 旧设计断言失败。
- 3 既有策略只更新 320→360、0.78→0.76、颜色和 placeholder；功能与消息可靠性断言保留。
- policies-final.json：**33 / 33 通过**，属于源策略和 Windows SQLite 镜像，不是 Swift/UI 运行。
- scope-and-hashes.json：7 项范围检查通过。生产文件恰 3；无 SDK/DB/Interactor/认证 diff；发送与附件 action 方法和录音发送 delegate 调用原顺序保留；XIB 连接/ID 保留；18 圆角类无改动；保留位置重绘方法本体无变化。附 6 源码/策略文件字节 SHA。
- git diff --check 通过。

后续验收：精确 Mac App 编译；最小屏/横屏/大字的文本、长编辑、时间标记与输入四行滚动；浅深色；发送/保存/空输入切换；按住录音→取消/锁定/播放/发送；附件取消/相册/拍摄/文件及键盘恢复。没有把原始静态检查当作这些行为通过，不声称全 App 大字或录音设备验收完成。
