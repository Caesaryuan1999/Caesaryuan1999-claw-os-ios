# VIDEO-OWNER-AUDIT — 只读有界审查

固定源码 e90332a417b722baabd8c71b60901f530e06b0aa；codex/r3-20260918-ios，开始 dirty 0。只读 3 个生产文件：Tinodios/VideoPreviewController.swift、TinodeSDK/Tinode.swift、Tinodios/LargeFileHelper.swift。无源码修改、构建、网络媒体请求、私有配置读取或推送。CI15 由总控运行；本文不改变其候选。Figma 视频状态是设计参考，不能据此宣称已实现。

## 确定缺口（源码路径反例，尚未实际 Swift/HTTP 演练）

### P1 VIDEO-DOWNLOAD-CREDENTIALS — 保存任意外源 ref 会带当前账号凭据

VideoPreviewController.swift:238–240 以当前 Cache.tinode 基址解析远端 ref，直接交给 Cache.getLargeFileHelper().startDownload。LargeFileHelper.swift:339–351 无同源判定，将 URLRequest 一律送 addCommonHeaders(:187–191)。Tinode.swift:676–683 明确返回 X-Tinode-APIKey，并在有 token 时返回 X-Tinode-Auth。

最小反例：已登录账号，远端视频 ref 为 https://other.invalid/clip.mp4，点击保存；实际生产请求组装路径会加入当前账号 auth header 并 resume。此不需要 scheme-relative 解析，也不依赖重定向。若获修复授权，真实 URLProtocol/窄实际 request consumer 回归应断言外源无认证字段、同源允许、旧 owner 拒绝；不发真实凭据。

**区分播放路径**：VideoPreviewController.swift:117–118 的 addAuthQueryParams 会经 Tinode.swift:652–654 精确比较 scheme/host/port，外源不新增 query 凭据。本发现不能直接推广为“播放任意外源也加 token”，也未将 Android 的 scheme-relative trusted 分支套用到 iOS。

### P1 VIDEO-EXPORT-PATH — 消息文件名直接写共享 Documents，存在覆盖/越界路径

VideoPreviewController.swift:235–249 用 content.fileName 直接 appendingPathComponent，再 bits.write；没有安全叶文件名、独立 UUID 导出目录、禁止覆盖或原 owner 门禁。同名已存在文件直接成为写入目标；含 ../ 的消息文件名也没有 containment 校验。错误路径还在 :251 输出实际本地 URL 和 error 描述。

下载分支 LargeFileHelper.swift:463–476 同样以 origfn 或 lastPathComponent 拼 Documents，并先 removeItem 再 moveItem；它也没有账号目录或安全叶名约束。不能把此路径称为按账号隔离的播放缓存。

最小合成验收：仅临时测试根下预建哨兵，inline 文件名使用既有同名文件、../sentinel 和安全叶名，验证修复后源文件/哨兵不变且导出留在独立目录；远端 origfn 同测。不在用户 Documents 做破坏试验。本次没有执行这些副作用。

### P2 VIDEO-DOWNLOAD-RECOVERY — 网络失败不恢复保存按钮，HTTP 错误体可进入分享

VideoPreviewController.swift:239 禁用保存按钮，仅在 startDownload 的 completion 内恢复。LargeFileHelper.swift:384–389 的 didCompleteWithError 只识别 upload taskDescription，download task 未设置 taskDescription(:345)，网络/DNS/连接错误会直接 return，未移除/调用 downloadCallbacks。恢复按钮的回调只在 didFinishDownloadingTo(:453–456) 触发。

另 didFinishDownloadingTo(:458–477) 只检查 downloadTask.error，未验证 HTTP status 或媒体内容，HTTP 403/404 错误体仍可移到 Documents 并分享；文件写入失败只记录日志，defer 仍回传 downloadTask.error（可能 nil）。视频调用者也丢弃 Error 参数。

Apple 官方说明客户端网络错误进入 didCompleteWithError；HTTP 服务端错误需检查 task.response，不能用 error == nil 推定成功：[URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask)、[下载文件](https://developer.apple.com/documentation/foundation/downloading-files-from-websites)。

最小验收应分别覆盖真实消费者的连接失败、403、有内容正常成功、写入失败、owner 失效；失败不分享且按钮/恢复动作可用。此处为确定调用链缺口，未声称已真机复现。

## 账号、VLC 及缓存边界

- **原 owner 未被视频页面捕获**：:117/:118 与 :238/:240 都在操作时读取当前 Cache。页面没有绑定原 UID/SDK/世代；保留 A preview 实例、切换 B 后调用保存，会按 B helper 发起 A ref。本次未扩读导航/接收者，不能声称实际普通注销 UI 一定留下 A 页面或 B 一定发送 A 附件；需要受控保留页面/回调 barrier 证明实际消费者隔离。VLC 状态/时间回调(:268、:333) 与异步 thumbnail 的附件通知(:355–375) 同样没有页面 owner 校验；通知下游未纳入本次 3 文件，不推定最终跨账号发送已发生。
- **已有 helper 保护保留评价**：LargeFileHelper 在 init 捕获 SDK(:176–179)，startDownload 使用 withActiveSession，invalidateSession 取消任务/清回调(:149–162)，deliverOnMain 再检 active/current(:168–173)。它可约束已经属于旧 SDK 的任务，但无法补回视频调用者丢失的“原 preview owner”，也不能替代外源 URL 授权。
- **VLC 选项与凭据**：默认 VLCMediaPlayer()(:44)，远端 VLCMedia(url:)(:135) 直接收到 URL；未配置 HTTP header、redirect delegate、缓存目录/key 或账号隔离选项。同源 URL 被 Tinode.addAuthQueryParams 添加 apikey/auth/secret。SDK logout 清内存 token(:1228)，不会改写已构造的 URL。页面离开会 player.stop(:160–162)，此已有停止动作不能描述成完全无保护。
- **重定向未验证**：此页面没有 VLC 重定向审核；LargeFileHelper 完整 delegate 中也无 redirect 限制。VLC/URLSession 外源重定向是否携带或重写这些 query/header 未做运行探针，不能当成已证实二跳泄露；前述 P1 已由直接外源请求成立。
- **缓存未验证**：3 文件内没有按 origin/UID 隔离的播放缓存，也没有读取已有图片隔离缓存的接线。未读/运行 MobileVLCKit 底层实现，无法断言它有 Android 同型持久 URL-key 缓存，亦不能宣称没有内存/磁盘复用。Documents 导出持久文件风险与 VLC 播放缓存分开记录。
- **URL 类型边界**：只要求 Foundation URL 能解析，未在页面限制 HTTPS/http/file 等 scheme、userinfo 或其它媒体协议。确切 Foundation scheme-relative 与 VLC 支持协议应由原生安全 fixture 验证；本次不做另一平台等价假设。
- **现有恢复 UI**：VLC .error 分支只停 spinner、显示图标和 toast(:305–311)，没有 owner-bound 明确失败态；playPause 的 .ended/.stopped 分支重启播放，.error 没有专用分支。Figma 暂停/播放/失败帧不是运行验证。

## 最小后续建议（尚未实施）

优先封直接外源凭据与安全导出、下载失败/状态码恢复这三个确定单元；owner 捕获/世代必须放在真实 VideoPreview 消费者而非只加 helper。复用已有媒体同源/账号 scope 与安全临时导出机制，不另造缓存/认证规则。是否改共用 LargeFileHelper 需另审其其它下载调用者，当前审查没有扩展为全 App 下载重构。

VLC 原生播放/redirect/缓存、后台/账号切换与原视频界面均 NOT_RUN；本次只有固定源码与官方 URLSession 回调语义核对。原 CI15 仍验证 e903，不包含任何视频修复。

## 固定 Git blob SHA-256

- Tinodios/VideoPreviewController.swift: 68eb5db962cd6839c67ea090139f6acd48919ddd00f7ad502d0f9199371708bd
- TinodeSDK/Tinode.swift: 3df82aae42260e219d3bbb57380dab34a4440f094cbd5090f1750956977127ef
- Tinodios/LargeFileHelper.swift: 6fe526d67ce61c2cf0406d323b500c1b3643d9d394b8923ea205e3ac562342d7
