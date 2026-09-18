# VOICE-DATA-CLEANUP-01

相对 57524056d641d1bcea3144b9b3dea7330332d666 的独立审查修正，仅 MediaRecorder.swift 与原 MediaRecorderLifecycleTests.swift 两个代码文件。Podfile 修复另提交。

确认旧 didSubmit 仅丢弃 ownedURL，却无真实 URL 消费者：UploadDef 传 Data，LargeFileHelper 写自己的独立临时副本。旧测试“已交出原文件保留”因此固化了源文件泄漏；575 原红版本保留，不改历史证据。

现按实际 Data 接收边界清本 lease 原文件。移除失败保留 ownedURL、记录固定事件；后续 retire 对同一 URL 重试。已接受 Data、上传副本、其它录音文件均不删除。未接受/过短/不可读时仍 preview。退休重试也失败仍保留对象中的责任并记录固定事件，不宣称跨进程持久清理或磁盘全擦除。

原方法改为真实临时文件与注入一次文件移除失败：didSubmit 后责任仍在，retire 再次移除，原 Data 和独立上传副本不变；另测立即移除成功。仍 8 方法，无数量增加；Mac 尚未执行。恢复原完整版权/来源头，在其后保留本次说明。原方案中的“文件所有权转移”以本报告实际 Data 边界勘误，历史575报告保持。
