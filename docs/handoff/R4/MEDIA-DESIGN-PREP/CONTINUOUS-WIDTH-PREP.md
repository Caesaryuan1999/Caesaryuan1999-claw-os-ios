# 连续语音宽度：三源最小接线提案

只读提案，尚未实现。普通 AU 源以固定 0ea19847e3b043bc14bfb046d2e1809cf92134e6 核对；后继录制候选 cb296b0f6c0f0571fc0d70f590ef916365c0dd0d 不改普通 AU 格式化、播放器或宽度代码。

总控最新连续规则覆盖本目录 f537 报告的三档：t = clamp(durationMs / 1000, 1, 60)，**完整气泡主体宽 = 128 + 96 × (t − 1) / 59 pt**，不含尾角/头像/外距；保留原显示时长舍入。1秒128、4秒132.881、10秒142.644、20秒158.915、30秒175.186、45秒199.593、60秒224。旧>60秒宽封顶、实际时长保留；未知时长用最短布局，但不显示虚构1秒。小屏实际可用宽先于名义宽，大字实际内容可增宽/高。此前 SIMPLE60 三档与 f537 的 54pt 外观均属旧时点记录，不据其实施。

## 可以先做宽度，而不扩点击/网络

当前 FormatNode.createAudioAttachmentString:375–378 的 voiceWidth 仅作图标能否摆下的 guard；并且把已扣过外侧布局的 size.width 再乘76%。返回富文本的实际宽只由24pt图标+空格+时长决定。真正气泡宽由 MessageVC.calcContentSize:1554–1578 与 calcContainerSize:1533–1550 得出。

最小三生产白名单：

1. **Tinodios/format/MultiImageTextAttachment.swift**：给该实际附件新增可选的 AU 布局时长字段（只读消费/默认nil）；其他非 AU 消费者默认行为不变。不改 image/bounds/setFrame，也不加播放或 URL 行为。
2. **Tinodios/format/FormatNode.swift**：真实 AU 构造时写入 attachment.duration（毫秒，未知保持nil）；保留 type/audio实体key/24pt bounds/实际时长文本/PlayTextAttachmentDelegate。现仅guard的 voiceWidth 改为直接使用已经传入的可用 content 宽判断图标，不再二次76%。不添加透明 NSTextAttachment 来撑宽：RichTextView:78 会把非 Entity 附件映射为 generic 链接，容易无意扩点击入口。
3. **Tinodios/MessageViewController.swift**：统一公式只返回 body目标；calcContentSize 从**实际生成的 AU MultiImageTextAttachment**读取提示，结合自然富文本尺寸决定实际content宽；calcContainerSize 加回原padding并适用真实总预算。不是另写未被 renderer 使用的 helper，也不从原文本猜音频秒数。

计算顺序：

- 原 calcMaxContentWidth 已算出 C（内容上限）和实际左右内距 P（普通当前28pt）。先保留此真实 viewport/头像/远侧预算，不再对 C 乘76%。
- 名义body D 使用连续公式；受限body B=min(D,C+P)；所需content R=max(0,B−P)。
- 实际contentWidth=min(C,max(原富文本自然width,R))，body只加 P 一次；文字/AX/编辑标识需要更宽时沿真实内容布局，不能缩字体强凑名义宽。AU 特例的最小容器宽也须服从可用上限；其他消息的旧最小宽逻辑保持。
- 混合/引用/多 AU 不丢内容或猜纯语音：只有实际 FullFormatter AU 附件携带布局提示；多 AU 取所需body最大值为容器最低需求，正文自然测量仍优先。QuoteFormatter 产生的引用摘要不变成新播放块。完整混合形态需原生用例明确检查，不只测纯音频。

点击范围保持原24pt音频glyph，扩出的普通容器空白仍走原消息/选择行为；不改 RichTextView、MessageCell 点击分发、VLC 初始化、owner、ref URL、回执、存储。**这一步只落连续宽度，不宣称新声波/48pt高度/尾角/整条点击/真实播放进度已落地**。普通 AU 可靠性缺口仍必须按独立包修复，不能以宽度变化绕过。

## 宽度何时变化

布局提示来自消息 duration，不取 player.position、已播时间、URL请求进度、图片加载回调。相同 duration 的 inline/ref、mid:uploading→srvUrl、准备/播放/暂停/结束应严格同宽；不能在媒体解码后把服务器 metadata 改成0或覆盖为测出的新长度而跳动。

已有 StoredMessage.cachedContent 保留富文本；旋转/字体变化在 MessageVC:438–444、716–724 清缓存再布局。此提案继续用该机制，不改 DB 缓存接口。trait导致真实文字增大或可用宽改变可重新排版；服务端真的更新消息 duration 或正文才跟实际消息重载，沿已封 ChatScroll 锚点保护。未知时长后来取得可信 metadata 会从最短布局变长，这应通过消息更新路径明确重排，不由播放瞬态暗改 attachment bounds。

## 真实验收方案与边界

- 在已有 App-hosted target 新增/扩展相关 renderer 测试，真实 Drafty.insertAudio → StoredMessage.attributedContent → FullFormatter → FormatNode → MultiImageTextAttachment → 原 MessageVC.calcContentSize/calcContainerSize。必须断言**实际最终容器frame/布局宽**，不是仅检查公式。
- 精确毫秒：1000/4000/10000/20000/30000/45000/60000及1500，未知/0/负值布局最短但显示规则不改，120000旧历史仍真实时长且宽封顶。CGFloat结果容许像素对齐误差，不改公式。
- 用同一真实元数据构造 inline、初始mid、最终srvUrl，逐次重新创建/更新真实富文本后比宽；PlayTextAttachmentDelegate实际 play/pause/reset 只切图，不改变bounds/最终宽。
- 320pt与正常宽、群头像/单聊、收发、AX/light/dark、编辑标记、引用+AU/多AU/正文、原MessageViewLayout的cell/container/content属性；原metadata/上传状态在容器外且无裁剪重叠。不使用 ChatScroll 的中性 cell/FlowLayout 代替生产气泡。
- 实际 RichTextView.getURLForTap：原音频glyph仍toggle-play/同key；扩宽空白没有新增audio URL；原选择/长按行为保持。不触发网络或播放来证明几何。
- 若实际测试 target 需要新增文件/PBX/class selector，先报精确路径后授权；不先改工作流或增加模拟登录。方法数以冻结后实际实现为准。

本提案不改变原声波素材和播放器；后继完整外观还需最新Figma context与资源白名单。没有在 Windows 运行 Swift/UIKit/真实消息页面，也没有将普通 AU 的原 owner/VLC 依赖视为已修。
