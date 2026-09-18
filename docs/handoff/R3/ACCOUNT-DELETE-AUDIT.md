# iOS 注销入口只读审计

审计固定 d61855fd1534cb864fb5f6848eec3fa1b7dcce4a；本文件只记录审计，不改代码/SDK/删除范围。

## 实际入口与文案
我 → 安全 → actionDeleteAccount（SettingsSecurityViewController.swift:58/66/94–96）。
运行时入口目前“删除账号”；393–404 的确认只有“确定要删除账号？此操作无法撤销。”，确认“删除”采用 default。
zh-Hans.lproj/Main.strings:236 的 Fjs-5K-JCI.text 仍为“删除帐户”；Base storyboard:3019 对应该旧标签。
最小 COPY-DELETE：上述控制器及 zh-Hans strings 两生产文件，精确对象ID，不全局替换。统一注销账号，确认 destructive、取消默认。总控已给逐字正文：
“注销后将无法再用此账号登录。你当前拥有的群组也将被删除。在其他群组或与他人的聊天中，已发送的消息可能保留。此操作无法撤销。”

## 清理时序与已纠正的审计范围
- 控制器493–507捕获并核 owner/UID/Cache世代；成功调用 UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)，没有重新获取新SDK。
- UiUtils338–342 → Cache.invalidate61–88 使用原slot身份与 withSessionLock，允许正确清理已退休同一SDK，拒绝旧owner清新slot。失败回调检查旧generation/UID/current。
- Tinode.delCurrentUser1594原成功链之后才1596–1602核原UID/StoreUID、deleteAccount、logout；不是点击就先退出。
以上只证明生命周期时序，不能证明只有删除200才触发清理。
总控发现并已确认独立 SDK-DELETE-ACK01 缺口：Tinode.dispatch678–679 将200..<400都resolve，delCurrentUser成功链忽略packet。因此匹配本请求的300或205也能误删本地Store并退休SDK。本端先前“没有先退出问题”不代表ACK校验安全，明确收窄结论。
提案只在Tinode.swift为该请求限定ctrl.id匹配且code200，不改全局dispatch；缺ctrl/非200不清理，并保留原UID/Store/retired保护。独立native回归，不混COPY。尚待实现与真实Mac运行。

## 边界
服务端删除当前账号、其拥有群及群消息；在其他群/P2P的已发消息可能保留。此语义来自本轮总控/后端核实，本端未对真实用户调用删除。permanent_accounts可拒绝。不声称所有数据立即清空或服务器删除真机已验证。
