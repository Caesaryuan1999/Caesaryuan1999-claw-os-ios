# CI22-AUDIO-QUOTE-01

独立最小编译修复；父49029978c855290e525eb034072e379ba7c80856（RESET完整消费者遗漏另单元补正，不混）。

CI22固定785/run35338111488/job105577570377已实际失败。总控保全artifact10544002656、SHA f793ed96b4b62d7c6453d7139392e024977869785ae29bf17fbc9c6dde2bab04。Hook实际Ruby3.3.12/CP1.17.0/Xcodeproj1.28.1成功，SDK43/43通过。App MessageInteractor.swift712对Drafty?直接append编译失败；UIrunner163/VLC4/导航3/打包冷启尚未运行，不报通过。

SDK Drafty.copy在1523声明返回Drafty?（当前实现dummy.append(self)）。575新增原owner音频回复路径漏解包。仅1生产MessageInteractor.swift：guard let replyCopy = reply.copy() else { return false }; content = replyCopy.append(content)。原reply头/seq/edit/forward路径未改；不能copy时拒绝本地接收，原预览保留；不强解包、不退回修改原quote对象、不丢弃quote后发送。

现SDK测试文件新增1方法testCopiedAudioReplyPreservesOriginalQuoteAndAudioMetadata：真实Drafty.quote/copy/append/insertAudio，断言原quote序列化不变、合成正文/QQ格式保留、AU实体bytes/preview/duration/size完整且无ref。它验证真实SDK构造语义，不冒充完整UIKit提交回调或服务端接收。无需新的selector，SDK目标原有全类运行会包含它。

Windows精确反替换与原生产文件逐字一致、SDK方法计数44、git diff --check通过；新增原生未执行。累计在RESET跟进闭合后预期44 SDK +167 UIrunner +4 VLC =215，导航3单列。当前CI22只有原43SDK实际通过。后续总控固定候选审后执行，未推送。
