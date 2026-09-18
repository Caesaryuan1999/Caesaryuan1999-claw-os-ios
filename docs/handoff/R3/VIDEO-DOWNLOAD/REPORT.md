# VIDEO-DOWNLOAD

状态：四生产文件实现封存待独立复核 / Mac 原生执行。没有推送。此报告不将 Windows 源检查称为 Swift、VLC、系统分享或真机通过。

## 起点与范围

工作目录 C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios；分支 codex/r3-20260918-ios。开工 HEAD5392b082d17d1ac050849b083f1b9d1e8373cba4、dirty0；生产等价 e90332a417b722baabd8c71b60901f530e06b0aa，自有 origin，只有总控推送/CI。

CI15 的 e903 SDK41 + storage141 = 182 原生、导航3、构建/冷启动实际通过，由总控封证。GET 初始错误文案真实图已修；密码16字符/非placeholder/实际keyboard geometry通过但App与全屏PNG仍空白的视觉证据缺口保留。VIDEO 不在该成功候选内。

仅4生产：VideoPreviewController.swift、LargeFileHelper.swift、ClawSecondaryUIState.swift、UiUtils.swift。测试只追加既有 OwnedImageTests 与 SecondaryUIStateTests，原内容逐字保留；Scripts/ci/test_owned_image_policy.py 更新精确方法计数，保留原10检查并核新总21。没有新增生产文件、target membership、selector、CI runner、Tinode/DB/wire/上传协议变化。当前 uploadURL、multipart、重试/进度实现保持。

## 固定红证据

red-source.json 针对 e903 的4项源码反例成立：任意外源 ref 直入无条件认证header下载；inline文件名直接拼Documents写入；download网络失败落upload-only分支不完成；HTTP错误未检查status即导出。它是源码红证据，不是Windows运行Swift或真实服务器泄露演练。原审查5392b08和后端独立fdb7418保留。

## 实现

- 独立 ClawOwnedFileDownload 使用 ephemeral URLSessionDownloadTask，背景上传 session/config不变。新下载需前台进程存续，不承诺系统终止后的后台续传。
- 冻结原 context 的 SDK/UID/世代/origin 和请求headers。同源才附原headers；合法外源只匿名HTTPS，拒绝userinfo和其它scheme。无URLCache/cookie/credential storage；全部重定向拒绝，不让目标请求发出。旧query中的源文件名或 Content-Disposition 不决定输出路径。
- 请求前、数据/响应、文件保全前后及main交付核原owner；锁只保护状态，不持SDK/Cache锁进行文件IO或UIKit。网络已发出与退出之间无法原子撤回，未扩大承诺。
- 只接受同请求URL的200、非空完整长度匹配文件；403、部分响应、网络/取消、无效数据和写入错误不进分享。delegate返回前将临时下载文件移到安全独立UUID目录。终态completion至多一次，当前的失败/成功均经过生产共用main consumer恢复操作按钮；旧owner/旧attempt不重启新页面按钮，过期成功清理自己的导出文件。
- 通用 exportData/preserveDownload 与 exportPNG 共用目录保全；消息名先降为安全叶名、限字节、清除控制字符，canonical/symlink containment核对，不覆盖已有目标；同名并发获得不同UUID目录。只清本进程登记的自己导出目录，不删除Documents、源用户文件、marker或数据库。
- Video冻结真实源和context，分享/inline写入、VLC回调和异步缩略图消费都核source/attempt；离开取消当前下载/旧callback，原view仍当前才恢复按钮和分享。动作改“分享视频”，不是保存到相册。VLC仍是原播放器，没有宣称内核redirect/cache已修。
- 保留 public startDownload(from:completion:Error?) 原签名作为旧消息薄适配；从该入口起绑定原helper owner并走新下载与原context分享。无法由此证明旧消息页面在入口之前的所有意图归属。
- 旧background下载残留的成功/错误回调只取消，不再move/remove到Documents、不输出原下载error或分享。背景upload请求/响应/重试方法逐段核对不变。
- UiUtils新overload在实际main呈现处经context+attempt gate复验，Video还要求原控制器为当前top；失败或过期清理自己导出，系统分享完成清理。旧overload保持。

## 验证与精确数量

Windows执行：
- 原不安全路径source红检查4项成立；无真实HTTP/用户文件副作用。
- 44现有源码策略通过。新增方法后曾43/44，唯一失败为旧固定计数10，保存在count-policy-failure.json；修正为原image区段10、全类21后44/44，未放宽任何业务断言。
- source-checks.json 14项边界核对通过：upload payload/policy、background config、全部upload request/retry/cancel、receive/completion/progress逐段保留；旧download签名、残留隔离、当前main消费者接线、无动态Cache凭据、原测试前缀不变等。
- diff --check通过。初始静态结果 initial-static.json 保留。
- Windows未编译或执行新增Swift，production.patch.gz无损封装仅4生产文件审阅diff（解压为production.patch），不是最终累计交付包。

新增14个原生方法（名称逐一在source-checks.json）：
- OwnedImageTests追加11：真实URLSessionDownloadTask+URLProtocol请求同源/外源与字节保全、同源/外源redirect目标0、403/206/204/空体、网络失败重试、A→B及同UID新世代、开始前和在途取消一次完成、写入失败、真实main呈现gate、生产共用终态consumer恢复实际UIBarButtonItem；另冻结headers/config/URL规则。
- SecondaryUIStateTests追加3：真实临时文件含../、反斜线、绝对/空名与sentinel不变、8并发同名+真实临时下载move、symlink namespace拒绝。
- 现有整类CI selector自动包含，无新增选择。下一候选期望 SDK41 + storage155 = 196 原生，导航原3；均是待Mac结果。OwnedImage 21、Secondary16，其余类不变。

URLProtocol只控制网络端点；使用真实生产context、SDK/DB账号fixture、请求、URLSession下载delegate和临时文件保全方法。main consumer测试执行与Video/旧adapter同一helper，未把它称为完整VideoPreview UIKit路线或真实系统分享面板测试。旧background回调与上传未退化当前为源码逐段证据，仍要完整App Mac编译。

## 剩余边界与运行/回退

独立backend/root审查及下一精确Mac CI完成前，三原缺口的运行验收不关闭。VLC真实播放、VLC内部redirect/缓存、后台恢复/系统分享UI/真机/跨端仍NOT_RUN。源层不等于无所有媒体风险。没有改变生产TLS、认证、C3、数据库/旧库，SharedUtils未读未改。

回退本独立提交恢复4生产+测试/计数差异；无schema迁移。新导出目录属于临时文件，不宣称磁盘全擦除/跨重启清理。保留CI15已验快照和旧FINAL，最终累计安全包在全部已知单元验收后再封，不覆盖旧失败记录。

production.patch SHA-256: bfeb1207c33873da511141e2947c4987efc71e485ed0817a0d013c6f71daac69

production.patch.gz SHA-256: 62079d167c2b816c408e042a4d1c5f6f34dbb1ae14f229230ef6596a11d79647。gzip 内容与原完整上下文 diff 逐字节相等；原未压缩审阅附件的上下文空白触发 Git 文档 whitespace 检查，改无损封装，不改变源码或 diff 内容。
