# IOS-CHAT-SCROLL-01 原实现反例

固定原文件 blob/原字节 SHA 见 before.json。此为源码反例，不是 Windows UIKit 执行。

1. 被动 onData true → load cache → Presenter async → DisplayLogic 大批 reload 后无条件 scrollToBottom。历史回看可跳最新。
2. 小批 delete/insert 与 refresh 同时启动，消息/索引在批次前替换；重叠呈现可让 refresh 使用旧索引。
3. MessageView.scrollToBottom 另开异步 completion；外层 guard 不能覆盖迟到滚动。
4. 编辑本地 defer 和 ACK 都用默认 true；清 pending 后不能再推断旧提交类型。
5. 视频实际确认后异步 thumbnail，再背景读 Data；迟回调不能重新生成主动定位资格。
6. 旋转按总高度差，置顶和局部 reload 绕过历史锚点；quote/pin 同位置点击不保证 DidScroll。

独立方案复核 c9a7ece3 的 11 组反例纳入新实际 UIKit 消费者测试；旧 232 原生与导航 3 保留。
