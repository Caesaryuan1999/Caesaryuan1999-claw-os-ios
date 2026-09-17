# UI04 有界只读审计

审计固定源码 4821062e9cf503c35137e8150d7c93813077c687，分支 codex/r3-20260918-ios。本报告仅新建文档，没有修改产品源码、公共资料或 Figma。CI6 精确候选仍冻结；任何真实 CI 故障优先于后续 UI 工作。

这是 UIKit/Storyboard/中文资源与调用链静态审查，不是六条路由的模拟器操作或真机验收。参考根 R3.D1，未因 Figma 暂无画面认定代码有错。

## 六条实际路由与主题落点

| 页面 | 真实入口/动作 | 已有中文与主题 |
| --- | --- | --- |
| 群信息 | MessageViewController.swift:807–811 顶部头像 → Messages2TopicInfo；774–778 传 topicName → TopicInfoViewController | TopicInfo:60–74、451 起接 ClawTheme 列表/字体/开关/卡片；63 固定标题“用户设置”；303–316 分组为公开信息/会话设置/管理/群成员。属于已接主题的真实群页面，未声称布局实机验收。 |
| 群编辑 | TopicInfo:244–246 → TopicInfo2TopicGeneral；Main.storyboard:4137；编辑完成按钮3623–3626 → doneEditingClicked | TopicGeneral:52–65 接 ClawTheme 输入/头像按钮；中文资源 Main.strings:623 导航“设置”，备注338 为“可选评论 (私人)”。公开字段仅 owner 可编辑104–111，备注对成员开放103。下面问题1影响完成动作。 |
| 通知 | AccountSettings:258–264 构造 SettingsNotificationsViewController 并 push | 通知页67–70/145–165 接主题背景、列表和开关；中文 Localizable:543–545“通知未启用 / 点击开启系统通知权限”。下面问题2影响恢复入口。 |
| 安全 | AccountSettings:267–268 → AccountSettings2Security；Main.storyboard:447 | SettingsSecurity:44–66、139–187 接主题页/卡片；修改密码250起已提示成功后重新登录；受控退出/删除沿已验 LOGOUT 接线。本次未重复身份/C3审计；无新增独立“隐私”菜单。群聊天权限另由 TopicInfo2TopicSecurity 到 TopicSecurity:158“群管理/聊天权限”，现有解散/退出确认已接实际路由。 |
| 图片预览 | 消息内容点击 MessageCellDelegate:231–232 → showImagePreview716起，或附件选图 SendMessageBarDelegate:164–185 → ShowImagePreview；MessageVC:779–782 传内容 | Main.strings:326“图片预览”；ImagePreview:107–110 保留黑色媒体底，不能仅因媒体黑底认定违反A主题；接收图片右上系统分享按钮 storyboard2111–2114。下面问题3影响失败状态与输出。 |
| 文件预览 | SendMessageBarDelegate:115–157 文件选择器读取本地 Data → ShowFilePreview；MessageVC:783–786 传内容 → FilePreview | Main.strings:617“文件预览”。这是发送前确认页，收到文件走消息附件下载/分享，不冒称收到文件也走此页。FilePreview:78–83 仅黑白背景；实际发送按钮 storyboard1650–1665 仍小图标。下面问题4/5。 |

## 最多五项确定缺口

### 1. P1：群编辑的备注完成动作会崩溃，或提交时丢弃备注

- 证据：TopicGeneralViewController.swift:175–179 使用 self.topic.comment!；TinodeSDK/ComTopic.swift:61–62 的 comment 合法为 nil。即使已有备注不崩溃，196 实际构造 MetaSetDesc(pub: pub, priv: nil)，丢掉刚构造的 priv。197–200 成功回调仍返回上一页。
- 复现：无私人备注的群 → 顶部群信息 → 编辑 → 输入备注 → 完成，nil 强制解包触发崩溃。已有备注改字 → 完成，则请求没有 private.comment，不会保存所填值。
- 最小包建议：TopicGeneral + SDK Types 两生产文件；真实生产共用 commentDelta 不强解包、只发 comment 单键；清空发送既有 kNull sentinel，SDK getter把ACK合并后的sentinel视空；成员只生成私人变化，owner仍可原有public/tags更新。不能整份覆盖 private，需保留 arch 等其他键。
- SDK/服务证据：Types.swift:48–54 与 Description.swift:191–205 按键合并；服务端 topic.go:2331 当前订阅 private 深合并，utils.go:838 起单key null移除。方案已报总控，实施需独立提交；本报告不算已修。

### 2. P2：拒绝系统通知后，“点击开启”只再次请求，不跳设置恢复

- 证据：SettingsNotifications:249–250 以合并后的 notificationsAuthorized 布尔判断；false 一律 requestSystemAuthorization。282–290 返回 denied/false 时只刷新列表，293–295 的 openSystemSettings 不被该分支调用。系统已授权但关闭横幅/通知中心也会被267–279合并成false。
- 复现：在系统权限弹窗选择不允许，再到我→通知→“通知未启用 / 点击开启系统通知权限”，点状态行；仍回原状态，无法通过所承诺入口恢复。其他“通知声音”行确实可打开设置，但不修复状态行含义。
- API依据：[Apple通知授权文档](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:))说明系统记住选择，后续请求不会再次弹询问。
- 最小包建议：该 VC 保存真实 authorizationStatus，只有 notDetermined 请求；denied 或已授权但提醒渠道关闭走现有系统设置URL，并按状态显示“前往系统设置开启”。生产最多 VC+中文资源2文件；原生测试映射动作，实际系统跳转仍需模拟器/设备验收，不改变推送协议。

### 3. P2：图片下载失败后仍可分享“损坏图片”占位图，没有重试反馈

- 证据：ImagePreviewController.swift:58–68 为收到图片建立 errorImage，失败146–148 将该图放到 imageView；右上分享未被禁用。117–128 在 ref 存在时直接把当前 imageView.image 转为字节并分享，未区分原图/占位图/下载中。失败只有日志，没有可见错误或重试动作。
- 复现：点击带远程 ref 的收到图片，在无缓存且网络失败/服务器拒绝下载时，页面显示占位图；此时点分享可把占位图导出成原文件名。即使后续再打开可能重试，本页当前按钮语义仍错误。
- 最小包建议：仅该 VC 增加已有图片加载状态；未取得有效内容时禁分享，提供中文失败说明和显式重试，成功才启用。不把请求失败称图片已损坏，不扩图片编辑功能。实际请求/错误结果验证需后续原生控制响应测试。

### 4. P2：选择文件但读取失败时静默返回，用户没有恢复提示

- 证据：MessageViewController+SendMessageBarDelegate.swift:115–157 负责进入文件预览；Data(contentsOf:)135 或资源读取129抛错后158–160仅写日志。没有 toast/错误页，也没有说明应重新选择；同路径过大文件131/144已经有提示，说明两类失败表现不一致。
- 复现：在文件选择器选择已失效、云盘未取回或不可读的文件，资源/Data读取失败；不会进入预览且聊天页无反馈。该结论是抛错路径源码确定，未实际操纵iOS文件提供器。
- 最小包建议：该扩展文件1生产文件，在主线程显示“无法读取此文件，请重新选择或先下载到本机后重试。”；不展示error/path，不改大小限制、内容或发送协议。可控文件读取失败原生用例与真实云盘行为分开验收。

### 5. P2：文件确认页的发送按钮仍为32pt无文字图标，不符合明确发送操作

- 证据：Main.storyboard:1650–1665 的 LBd-NU-F3v 是普通 UIButton，固定32×32，仅 arrow.up.circle.fill；没有title或accessibilityLabel。FilePreviewController.swift:27–29/52–84 未配置该按钮的文字/辅助功能名称/触控尺寸，也没有主题按钮接入。
- 影响：这是立即把附件交给消息页面发送的主动作（FilePreview:40–44），视觉只见小向上箭头；读屏缺少明确“发送文件”名称。R3.D1要求主要按钮明确文字、iOS普通点击至少44pt（共用48），不是因缺Figma推定。
- 最小包建议：FilePreviewController + Main.storyboard最多2生产文件，将现有动作接到主题明确文字“发送文件”按钮，触控≥48，保留原NotificationCenter发送语义和返回路由，不碰C3/Store。约束尺寸可静态验，真实大字/读屏需后续模拟器验。

## 收敛边界

以上只列会影响完成/恢复/实际主动作的5项；不把所有可见旧用词或主题继承都追加成新修复批次。安全页的静态状态标题不当成真实账号安全证明；媒体页黑底不当成主题缺陷。未读取SharedUtils私有配置，未验证APNs/FCM、正式签名、真机、完整页面旅程。CI6结果和并发I/O根因由后续精确证据决定。
