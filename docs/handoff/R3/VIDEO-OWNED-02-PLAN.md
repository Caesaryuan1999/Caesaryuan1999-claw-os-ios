# VIDEO-OWNED-02 — 待探针审查后的两生产文件分解

只读计划，当前源码冻结：生产e6d0aa978daf6c2aa92f88e88deb2060658226f9；TEST-PROBE-403为758b062e2f291219882b3a45773509ed90077a92。尚未实施本单元，等待总控对探针固定提交的审查。已读backend ed622e56的IOS-CI23-VIDEO-OWNER-DEPENDENCY.md及实际VideoPreview/ClawSecondary全链关键段。

## 实施界限

**1. Tinodios/ClawSecondaryUIState.swift**

- 在现ClawOwnedFileDownload复用同源冻结header/匿名外HTTPS/全redirect拒绝/ephemeral无cookie-cache/一次完成，不改LargeFileHelper后台上传。增加可选下载预算，默认nil使既有非Video调用者保持原行为；Video直接构造现helper并传预算，不为参数转发增加第三生产文件。
- 原owner在当前context门禁内捕获已协商maxFileUploadSize，缺省既有8MiB。非正/不能安全计算的值fail closed；不改wire、服务上传限额或新取当前Cache账号。
- 单次启动前实际卷空间须满足2×最大文件字节+16MiB余量（乘加检查溢出）；空间查询失败单列恢复。进度中检查totalExpected>上限或totalWritten>上限立即取消；未知长度也按实际累计字节检查。完成回调先检查实际磁盘文件大小/完整长度，再保全UUID文件并核最终大小；只有符合预算的完整200可交播放器。
- 单次空间预检不是全进程磁盘预留；URLSession进度回调可能在已经写入一个chunk后才报告。明确不保证零瞬间超量、并发全局预留或后台进程终止续传。网络/403/文件过大/空间不足/空间状态不可用/本地写入分开中文，不把播放准备错误说成“分享失败”。
- 同文件增加最小播放责任对象（如需）：捕获context/attempt、独立播放文件和锁外stop/detach/cleanup闭包。真实VC调用其消费/失效方法；原生回归也调用同一生产方法，不复制Boolean镜像。不得在SDK/Cache锁内调用VLC/URLSession/UI/文件IO。

**2. Tinodios/VideoPreviewController.swift**

- remote ref先解析原context URL，再进行独立playback owned下载；显示“正在下载视频…”及实际可恢复失败。完整结果在main重验原owner、当前可见、attempt后才创建`VLCMedia(fileURL)`，不再把addAuthQueryParams远端URL交VLC。
- 每attempt独立player身份；旧下载、旧player delegate、旧失效监视不得停止新attempt。保留原.local选择/字幕/回复发送/缩略图和inline分支，绝不删除用户原文件。
- 播放文件与分享文件/attempt分离。播放关闭只删本次播放UUID文件；系统分享使用另一个独立owned结果，不能关播放就删除仍在分享的文件，也不能分享结束删除正在播放的源。
- 可见期间main nominal250ms owner检查，暂停/无delegate事件/网络停滞也可发现退休；读取current门禁返回后才stop、清delegate/drawable/media、cancel并回收owned文件。它不是即时撤回，主线程阻塞会增加调度延迟；不得宣传每250ms一定完成VLC停止。
- 退场/source替换/deinit幂等取消监视并清本attempt；初次setup发生在viewWillAppear之前，不能把“尚未可见”当owner失效误杀正常加载。新播放需要原context且页面可见；后台播放不是本单元承诺。
- 冻结来源有效但VLC解码失败仍按设计保留“分享视频”；失效/无权限来源不可借新owner恢复。没有新视频UI/Storyboard或自动换账号重试。

## 原生回归分解（待精确方法清单确认）

拟复用现有测试目标，不新增host/依赖版本或生产测试开关：

- `TinodiosUITests/OwnedImageTests.swift` 追加实际ClawOwnedFileDownload及播放责任对象方法：冻结同源header/外源匿名不退化；已知/未知长度超过上限；终文件超限；空间2份+16MiB/不足/查询失败/整数溢出；owner在网络与main交付之间退役；A→B旧结果不启动/清理B；自有播放/分享文件互不删除且原local文件保留。复用实际URLSession/合成provider边界，不能说已设备网络验证。
- `TinodiosUITests/VLCPlaybackProbeTests.swift` 原4方法保留；可追加真实owned-download→本地同源片VLC帧/time/seek，以及实际owner退休后的生产共用lease→stop/detach/自有文件清理。使用现已运行前台host、原socket/AVAssetWriter源，不模拟VLC。不代表实际VideoPreview页面导航已经执行。
- 实际新增方法数在源封存时由selector/class/extension清单核算，再给总控最终预期；当前215+导航3仅基线，不预报新增方法通过。

## 必须保留的兼容与安全边界

整文件准备意味着失去远端边下边播及Range首帧优势；本地seek需实际验证。每次打开独立文件，无跨账号URL缓存复用；不据此宣称VLC内部已无缓存。

**fileURL只约束交给VLC的入口。** 当前还没有恶意播放清单、引用MOV/其他容器内部外部URL的实际VLC证据，不能由“入口是本地文件”推出任何内容都永不发次级网络。建议在新增真实依赖回归中放一个完全本机的外部引用合成fixture；若真实VLC会访问，先向总控报告确定结果及格式白名单/结构验证取舍，不能静默缩减原支持格式或加未经验证的VLC参数冒充沙箱。此边界不由现14个owned URLSession方法覆盖。

现CI23 renderer内部CALayer异常、旧403不完整观测保持原证据；TEST-PROBE-403只改善观测，不修生产。实现前后都不改C3/AUTH/DB/上传，并与VOICE纯视觉分提交。最终两生产完整差异、真实方法调用链、Mac与页面/设备层级分开交总控独立审查。
