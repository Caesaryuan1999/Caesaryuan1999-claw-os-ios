# DEVICE-QA20260927 — iOS Q01–Q40 输入报告

本表是总控既有 `docs/design/r2/PAGE_STATE_MATRIX.md` 的 iOS 更新输入，不另定协议或产品规则。工作目录：`C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios`。原基线 `codex/r3-20260918-ios@79f015f47b15fd7124f81d52205de5c5508f370e`；本批身份恢复修订 `92208c6a5078ab4d8c92e9e84d069a17ee20e19d` + `3d9498144a8ea95a5d581d777e6b78a246128ebc`。远端为用户自有 `Caesaryuan1999/Caesaryuan1999-claw-os-ios`，未推送。接手时 tracked dirty=0，23538 个未跟踪文件未清理。适用根 AGENTS、ACTIVE_CONTEXT、WORKSTREAMS 和 DEVICE_QA20260927_TASK_PACK；没有本树子 AGENTS。

当前资源：Windows，无 Mac/iPhone，无第二台 Android。以下“源在”是本轮文件/路由核实，不代表功能运行通过。所有本轮 iPhone、Android/iOS 跨端格均 **NOT_RUN**。CI50/51 的旧结果是历史；CI51 attempt 2 另报，不能验证本批 92208c6 修补。协议 C3-20260918/AUTH-A1/AI-A1/AI-B1、设计 R4.D1/Voice v4/Image v1 未变。

`Main.storyboard` 已解析到 StartNavigator、ChatsNavigator、ChatListViewController、MessageViewController、Find、NewGroup、Account Settings 及媒体/群设置等实际 scene 和 segue。四项导航是 `Tinodios/NewChatTabController.swift:14–49` 的程序化 `ClawMainTabBarController.make`，不是 storyboard 中旧 NewChat 页的三个分栏。

| 编号 | 已核实际入口 / 主要源码（相对工作目录） | 本轮能力与缺口 | 下一次有设备时的验收 |
|---|---|---|---|
| Q01 | AppDelegate→StartNavigator；TinodiosDB/BaseDb.swift | 源在；损坏库阻止使用并保留原数据；冷启动无 token 仅停用账号 | 有/无 token、损坏库保全、真实旧版本升级 |
| Q02 | Login2Signup→SignupViewController；ClawIdentityFlow / ClawIdentityService | 验证码→密码注册源在；真实 SMS/SMTP 不可用，不能把合成身份结果当正式注册 | 邮箱/手机号、过期/重发、提交结果未知 |
| Q03 | StartNavigator→LoginViewController；Utils 的身份 UI 桥 | 新密码流程及旧号桥在源；本批修复 me 订阅认证失败被吞 | 同账号历史恢复、错误凭据、失效后重登 |
| Q04 | Login2ResetPassword→ResetPasswordViewController；Credentials / CredentialsChange | 同 AUTH-A1 源在；恢复服务资源未验 | 过期/错误验证码、密码更新/会话撤销 |
| Q05 | Login2Branding→BrandingViewController；SharedUtils.setUpBranding | 配置码/扫码源在；本机 token/库未持久绑定 origin，弱于 Android2094，另列待处理 | 错码返回、配置切换不发送旧 token/不读旧服务缓存 |
| Q06 | ClawMainTabBarController→ChatsNavigator / Find / ClawAssistantViewController / Account Settings | 四导航、连续会话、未读角标/空态/归档在源；没有本轮账号运行证据 | 真数据/字号/断线/未读一致 |
| Q07 | ChatListViewController.applySearchFilter；FindViewController | 已确认会话名称/别名过滤；本次范围内未建立全文消息搜索→命中定位的完整证据，按部分完成 | 空结果、消息命中/目标删除/返回原位置 |
| Q08 | Chats2Messages→MessageViewController / MessageInteractor；TinodeSDK、MessageDb | C3 状态、服务端序号、未知结果路径在源；本轮 iOS 真实收发未验 | 两设备双向文字、超时 ACK、不重复 |
| Q09 | 同聊天页 grp 模式 | 群订阅/写权限源在；没有当前真实多成员验证 | 群聊收发、被移除/只读后的行为 |
| Q10 | MessageViewController / ForwardToViewController；ForwardToNavController | 引用、选择、转发等既有路径；逐操作未运行 | 源删除、目标无权、取消预览 |
| Q11 | MessageInteractor；TopicSecurityViewController；ConversationRemoval 规则 | 删除范围/确认源在；本轮没有调用真实删除 | 本机/会话/对所有人含义、取消/权限变化 |
| Q12 | MessagePresenter、MessageViewController 的 ChatViewportSnapshot / restoreViewport | 历史和锚点实现存在；不是本轮滚动通过 | 分页重漏、回看收消息、长文/媒体加载 |
| Q13 | Cache、TinodeSDK/Tinode.swift、TinodiosDB/SqlStore / MessageDb | C3 保留/重试源在；iOS logout 不删历史；本批失效路径源码修复，原生未验 | 断网/重连、同账号重登、双重启、多设备 |
| Q14 | widgets/SendMessageBar；MessageViewController+Keyboard | 输入/键盘/安全区在源 | 输入法、长文、附件后键盘恢复、VoiceOver |
| Q15 | widgets/ImagePicker；MessageViewController 的 ShowImagePreview/ShowVideoPreview/ShowFilePreview | 系统选择和三类预览路由明确 | 拒权/取消、失效资源、切换账号 |
| Q16 | MediaRecorder、widgets/SendMessageBar | 60_000ms 上限、录制/取消/锁定/预览源在 | 59→60秒、音频打断/耳机/权限 |
| Q17 | MessageViewController.MessageBubbleLayoutPolicy、MessageCell、AudioPlayer | 连续宽度公式 `min(128+96*(clamp(ms,1000,60000)/1000-1)/59,可用宽度)`；CI50 AAC结束回调仍失败，不宣布修好 | 实录短/长音、暂停/继续、自然结束、离页 |
| Q18 | format/FullFormatter / AsyncImageTextAttachment；ImagePreviewController | Image v1 长图3:4、未知尺寸固定3:2源在；CI50只1/6 Image原生方法过，其余在测试后继等待复验 | 横竖长图、完整查看、失败/重试、复用 |
| Q19 | ShowVideoPreview→VideoPreviewController；MobileVLCKit 3.6.0 | 现有 VLC 和显式播放源在；官方归档本轮单次 HEAD 200 不等于播放器通过 | 封面/时长、上传、缓冲、seek、退出 |
| Q20 | ShowFilePreview→FilePreviewController；LargeFileHelper | 受控上传/访问/保存路径在源 | 文件失败与消息失败区分、分享/保存权限 |
| Q21 | MessageInteractor、LargeFileHelper、Cache | 账号/临时任务范围守卫部分在；完整跨进程媒体恢复与最终文件清理仍缺 | 上传中重启/退出、草稿保留、重复创建 |
| Q22 | 通讯录 Find / AddByID；Chats2NewChat→NewChatTabController | 公开账号名查找/添加源在；本轮搜索服务未联调 | 空/离线/无权/扫码/添加后聊天 |
| Q23 | account/ContactsSynchronizer / ContactsManager | 同步前捕获 owner/token，枚举后复核，结果写入复核；本轮无系统联系人运行 | 拒权、切号、慢枚举、系统联系人变动 |
| Q24 | NewGroup→NewGroupToEditMembers→EditMembersViewController | 建群与成员选择、部分失败处置源在 | 群已建但部分邀请失败时不重复建群 |
| Q25 | Messages2TopicInfo→TopicInfo；TopicInfo2EditMembers | 群资料/成员/角色源在 | 群主/管理/普通成员、权限即时改变 |
| Q26 | TopicInfo2TopicSecurity→TopicSecurityViewController | 退出/移除/解散分开确认；源码权限规则在 | 多人真实权限与历史范围 |
| Q27 | Find 的 slf 自聊→普通 MessageViewController | 文件助手是自聊，不是 AI；源在 | 自聊文字/媒体和返回 |
| Q28 | Chats2Archive→ArchivedChatsTableViewController；安全页→BlockedContactsTableViewController | 归档/解除与屏蔽入口在；会话置顶完整行为未本轮复验 | 空态、解除/回滚、列表位置 |
| Q29 | MessageViewController.displayPinnedMessages / applyTopicPermissions；TopicInfo | 消息置顶/权限表现源在 | 源删除、陌生会话、接受失败、无权返回 |
| Q30 | Account Settings→General Settings；AccountGeneralSettingsViewController | 我页/头像/昵称/公开名资料源在 | 未加载、保存失败、真实更新、切号 |
| Q31 | AccountSettings2Notifications→SettingsNotifications；AppDelegate | 偏好和通知路由源在；APNs/大陆方案资源仍无；不得把推送当同步 | 前/后台、允许终止态、关闭权限、旧账号通知 |
| Q32 | AccountSettings2Security→SettingsSecurityViewController | 退出只停用并保留历史；注销须服务端200确认才删本机；本批未改 | 主动退出不变、改密/失效、注销确认/失败 |
| Q33 | AccountSettings 外观只读行；Utils.ClawTheme | 跟随系统双主题；没有假装可编辑的箭头；iOS独立壁纸操作未验 | 系统浅深/字号/对比度 |
| Q34 | AccountSettings2Help→SettingsHelpViewController；本机 Acknowledgements | 帮助/许可在源；客服/条款/隐私均明确不可用，不跳旧品牌外链 | 许可读取、失败、返回；正式文档待审核 |
| Q35 | 我→帮助与客服 | 当前关闭且不收留言；人工专号+本次文字/手选图已确认，但提交链未实现 | 先冻实际接待账号/分配与权限，再做仅本次材料发送 |
| Q36 | 帮助内客服说明 | 自动答疑未开放；无已审核材料/模型 | 无资料时不伪答、不伪造人工接入 |
| Q37 | 助手 tab→ClawAssistantViewController / Conversation | 文字问答 UI/协议准备；`send.isEnabled=false`，无模型不能生成 | 服务开通后真实问题/上下文；不读取其他聊天 |
| Q38 | ClawAssistantHistoryViewController / History | 账号历史、分页和整段删除确认源在；本轮跨设备未验 | 两页/401/410、取消、删除结果未知 |
| Q39 | ClawAssistantRun / Stream / Session；Conversation 控制 | 读取/停止已知run、恢复原回答源在；无真实模型，新生成硬禁 | 断流/停止未知/原run恢复，禁止自动重生成 |
| Q40 | Messages2Call→CallViewController / CallManager | 保留既有入口；用户已明确后续单独验收 | 本批不算通话完成，不开启付费或真实通知 |

本轮优先缺口：新身份恢复补丁的原生回归；CI51 媒体原生失败的准确复测结论；Q05 origin 持久绑定差距；正式身份供应商；Q35 客服提交链；真实模型；APNs/大陆设备推送；iPhone/第二设备。未开展新的视觉方向、数据库重写或额外功能扩张。

## 2026-09-27 本批资源时序与 CI 更正

以上“无第二台 Android”和末尾“第二设备”缺口是本表初次采样时的状态，已被总控本批新实测更新覆盖：现已有 **vivo + 三星两台 Android**。总控报告已测双机 seq 38–45 的文字、3.175 秒语音、图片、两条视频（含 5 MB 外链）以及离线重启队列。此段来源为总控本轮实测回报，本 iOS 协作者未操作两台手机；详细步骤、版本和原证据由总控统一台账保存，不能据此标记本表 iOS 对应格通过。

iOS 本机仍无 Mac / iPhone，iPhone 真机和 Android/iOS 跨端 **NOT_RUN**。云端 macOS 的 CI51 attempt 2 已于北京时间 07:46:17 结束：原生 SDK 44/44、App / SQLite 288/293，合计 332/337 通过、5 失败、0 跳过。依赖安装已成功；失败为 3 个图片重试等待阶段和 AAC / 独立 PCM 两个真实完成回调。独立导航、封包、冷启动未运行。准确诊断和下一窄任务见 `CI51-ATTEMPT2.md`。

该 CI 输入固定 `0877d9a8`，不含本批 `92208c6` / `3d94981` 两生产文件修补，不能作为新修补原生通过证据。新修补依旧只有本地静态及独立源审查；后续原生回归尚待执行。原 `SOURCE-SEAL.json` 对应文档提交 `a09eab354d17a9da296a0c5dbce9fe9d036c3518` 的初版报告，保持原样；本追加更正由独立 `RESOURCE-ADDENDUM-SEAL.json` 记录 hash。
