# B02 隐藏时历史完成后的首次读取

固定问题源 `2d0feec40530e04688694539ed23823df7bd4419`：完整历史在离页后返回，Session 创建了 knownRun/knownAddress 并消费 snapshot token，但因为 readerVisible=false 未调用 recover，Run 内地址仍 nil；回页 setVisible(true) 因 receipt/address 均 nil 不发 GET。Windows 只证实该源码反例，尚无 Mac 红测。

窄修仅 Run/Session 与新增状态测试文件：known-only Run 在绑定完整权威历史时注册原 cid/rid，不联网、不通知、不为未知提交制造 receipt。统一 setVisible(true) 负责首次及返回读取；删除原 Session 额外 recover，避免双 GET。注册还核同 scope 已提交 B snapshot 和最后非空 rid。

新增第 13 方法以实际 URLSession/History/Run 和 held messages 响应覆盖：离页前请求→释放旧 lease→完整响应→隐藏时零 GET→新 lease 恰一个原 rid GET→再次返回恰一个 GET。其余 12 方法除获批 late-stop 屏障外保持。

late-stop 方法保留原断言并追加 main FIFO 屏障。真实 HTTPTask.cancel 同步 finish/completion，再由 Run.receive 排 main；切 cid 的 acquire 返回后 sentinel 才入队，所以 assertion 不抢在取消 completion 前。该证据是取消完成已排过及迟到 transport 不二次消费，不声称取消后的成功 HTTP 包又被完整解码。原 B1 晚成功身份回归仍未修改。

新增方法累计预期 308 native + 3 navigation，全部新 B02 原生待 Mac。原 2d0、CI43 依赖下载失败证据保留；UIKit WIP 不纳入此状态窄提交。
