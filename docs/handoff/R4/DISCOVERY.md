# R4 iOS 现状发现（只读盘点）

日期：2026-09-19。任务：R4-DISCOVERY-01。完整逐页清单见同目录 `PAGE_INVENTORY.json`；该清单是当前客户端路由事实，不替代项目根 `docs/design/r2` 的唯一设计规范。

## 结论与代码基线

当前可达路由归并为 **27 个业务页面、22 类可复用组件**。Main.storyboard 的 **28 个自定义 Controller 场景**全部分类：25 个当前业务页、1 个有效二级导航容器、1 个隐藏的旧凭据编辑页、1 个条件可达但后续验收的通话页；另有设置密码和开源许可 2 个动态业务页。登录方式、权限弹窗、录音面板、消息菜单和系统分享是页面状态/组件，不拆成额外业务页。不据此计算“整套 UI 完成率”。

- 独占目录：`C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios`。
- 分支：`codex/r3-20260918-ios`。
- 读取起点 HEAD：`dc2e17dd8f8d1b0a88c2112701566397e77e433f`。
- 当前生产/测试/CI 来源：`b0984075ca79ffef93658f702005dd19a773616b`；与读取起点的全部非 docs 差异为空。
- origin：`https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git`，只读取，未访问远端或推送。
- 开始时 tracked dirty 0、untracked 19,782。原有未跟踪内容保留；本批仅新增本目录 2 份 UTF-8/LF 文档。显式暂存和提交这两份后，tracked dirty 回到 0、untracked 仍为 19,782。文档提交的完整 SHA 由提交完成后的消息交付，不能把文档 HEAD 当成新生产版本。

读取了根 AGENTS/RTK、ACTIVE_CONTEXT、WORKSTREAMS、CAPABILITY_REPORT、R3_INSTALL_AND_RESUME、R4_BATCH01_TASK_PACK，以及本端 CI33 交接。独占树没有额外 AGENTS。全程 shell 使用 rtk 前缀；未读私有 SharedUtils 配置。

## 用户确认与待定边界

总控本轮消息已转达用户确认：延续 A 青绿浅色/深色主题；新增独立「助手」主导航；客服保持「我 → 帮助与客服」；客服采用 AI 客服加人工留言；助手定位为类似豆包的通用文字问答。这一新答复优先于任务包尚未同步的“四问待答”段落。

模型与费用、可读数据、工具和执行权限、历史保存/同步/删除、客服资料、人工接待和留言状态仍待确认。本批未创建 AI 服务、客服流程、权限或任何新页面。已有 C3-20260918、AUTH-A1-20260918 和 R3.D1 保持。

## 有效页面与实际入口

详细源文件/行、Controller、组件、关键状态和证据编号均在 JSON，以下为入口关系摘要。

| 模块 | 稳定页面 ID（省略 IOS- 前缀） | 真实入口与范围 |
|---|---|---|
| 身份 | AUTH-LOGIN | StartNavigator 根页；手机号/邮箱密码与次级原账号登录是同页模式 |
| 身份 | AUTH-REGISTER / AUTH-RESET | 登录页「注册账号」「找回密码」；共用 ClawIdentityEntryController，保留 purpose 区别 |
| 身份 | AUTH-CODE / AUTH-PASSWORD | 获取验证码后推 Credentials；验证后推动态 ClawSetIdentityPassword；不把 stock OTP 当 AUTH-A1 |
| 身份 | AUTH-CONNECTION | 登录页连接设置 → Branding，扫码配置及返回；不是服务器列表或域名编辑器 |
| 消息 | CHATS / ARCHIVE | 主导航消息；归档入口及恢复归档会话 |
| 联系人 | CONTACTS | 主导航通讯录；本地联系人、远端公开目录搜索与空态 |
| 联系人 | CONTACT-QR | 消息 → 发起聊天 → 二级 NewChatTab 中的 AddByID；公开 CLAW 号查询/二维码，不直接手输私有 UID |
| 群组 | GROUP-CREATE / GROUP-MEMBERS | 通讯录发起群聊或消息发起聊天 → 选成员 → 群资料；已有群信息也可进成员管理 |
| 聊天 | CHAT | 消息行、联系人、归档、受控通知路由；历史锚点、回到最新、回复/编辑/转发、附件与录音属于该页状态 |
| 聊天资料 | TOPIC-INFO / TOPIC-EDIT / TOPIC-SECURITY | 聊天顶部 → 聊天信息 → 资料/权限或群管理；角色控制动作与危险确认 |
| 转发 | FORWARD | 消息长按 → ForwardToNavController；选目的地后回真实聊天确认/发送链 |
| 媒体 | MEDIA-FILE | 选择本地文件 → 原 FilePreview；确认发送/读取失败。远端附件下载和系统分享不冒充这个发送前确认页 |
| 媒体 | MEDIA-IMAGE | 本地选图确认或消息图片预览；加载/失败/重试/无权/分享就绪分别处理 |
| 媒体 | MEDIA-VIDEO | 本地视频确认或消息视频预览；远端先准备完整 owned 文件，再交 VLC；分享是独立动作 |
| 我 | ME / PROFILE | 主导航我 → 个人资料；公开 CLAW 号复制，手机号/邮箱只读，不重新开放旧绑定 |
| 设置 | NOTIFICATIONS / ACCOUNT-SECURITY / BLOCKED | 我 → 通知/安全；安全 → 已屏蔽联系人；退出/注销/本机清理恢复是确认状态 |
| 帮助 | HELP / LICENSES | 我当前行名为「关于 CLAW OS」→ 帮助；右上许可入口推动态许可文本页 |

主导航实际只有消息/通讯录/我。对应 `NewChatTabController.swift:14–32,40–52`；它同时包含另一个仍使用的二级 NewChatTabController，不能仅因新主导航存在就把该二级入口判为失效。

隐藏和后续入口单列：

- CredentialsChangeViewController 保留原 storyboard，但个人资料的旧 section 已隐藏；其动作只说明更换手机号或邮箱未开放。
- CredentialsViewController 的 nil coordinator 旧凭据验证分支和 UiUtils.routeToCredentialsVC 仍存在；本轮未找到当前 Swift 调用者，不算新的默认注册/找回路径。
- CallViewController 可经允许通话的聊天菜单/原调用链条件进入；通话历史 ClawCallsHistoryViewController 没有主导航实例化入口。两者不扩成本轮已验功能。
- 新群组动态资料页隐藏了原 table 的公开 tag/channel 选项；保存方法仍读原字段，不把隐藏选项描述为可见新功能。
- 「外观」当前是跟随系统的展示行，独立外观页/独立隐私菜单尚未实现。系统选择器、权限弹层、UIActivityViewController 和启动画面不计自建业务页。

## 可复用组件与明确显示差异

`Utils.swift:21` 的 ClawTheme 已提供青绿浅深配色与 UIFontMetrics 字号；实际复用包括主导航、IdentityForm、联系人/会话行、头像、空态、MessageCell/格式化内容、SendMessageBar 原 XIB、置顶/转发条、附件菜单、进度、媒体状态、ProfileLayout、通知状态和权限编辑。原 Logo 资产位于 `Tinodios/Supporting Files/Assets.xcassets/logo-ios.imageset`，本批未改图、未新建主题。

当前路由可见差异已记录，留给总控整套 UI 统一排期：

- 我页面入口仍是「关于 CLAW OS」，帮助页标题是「帮助」，客服点击只提示未配置、联系管理员；它不等于新确认的「帮助与客服」已落地。
- 注册入口已是「注册账号」，动态注册页标题仍是「创建账号」（Utils:1508）。这是显示术语差异，不是第二种注册协议。
- 发起聊天二级容器仍有两个「查找」子标签；必须按实际 Find/AddByID 功能区分后再统一。
- 连接扫码进度仍显示英文 `Configuring. Config ID:`（Branding:49），随后立即返回上页（51）；本批没有验证异步配置成功或失败的用户旅程。

这些事实不是本批实施许可；没有根据缺 Figma 节点推断代码错误。已知节点按共享规范/既有交接记录填写，未知留 null；本轮没有重新读取 Figma API 或声称节点视觉验收。

## 助手与客服的真实现状、第四导航依赖

SettingsHelpViewController:49/135 的客服入口只有未配置提示。条款/隐私链接未核实，当前也是明确不可用提示；版本、连接诊断和开源许可为已有实际内容。未发现内置客服会话、人工留言提交/接待状态、模型流式响应、模型工具授权或独立助手 Controller。结论范围是当前 Tinodios/TinodeSDK Swift 路由和有界词搜索，不代表后端一定没有 bot 示例。

通讯录的「CLAW 文件助手」来自 `slf` 保存消息（Find:274、MessageDisplayLogic:47、TopicInfo:127），并非大模型。新「助手」不能复用这个名称就宣称接入模型。

增加第四导航的已知依赖：

1. `NewChatTabController.swift:14–32,40–52` 构造、主题/标签，以及目前消息 index 0、通讯录 index 1 的调用假设；保留原会话跳转。
2. 新独立助手页面与工程成员接线；服务接口、历史和权限未冻结，不能先套现有 Tinode 消息发送语义。
3. `AccountSettingsViewController.swift:111,271` 帮助入口及 `SettingsHelpViewController.swift:33,135` 内容路由；人工留言状态、AI/人工身份、处理承诺需总控与后端确定。
4. 若后续共享 UI 组件需拆分，由独立批次确定文件边界。本盘点不承诺以现有三份文件就能完成真实助手/客服。

## 媒体恢复分层

- 上传：LargeFileHelper 的 activeUploads 是内存映射（141），活动请求内有最多 3 次瞬态重试（9/406）；multipart 临时副本在终态清理。MessageInteractor:947/965 把未完成音频明确提示重新录制。没有发现持久上传 journal、进程重启重建回调或用户点击消息重新上传入口。background URLSession 的存在不证明业务恢复已经完成。
- 图片：合法 ref 加载失败有重试；403、无源/损坏数据与分享未就绪有各自状态。按原 owner 和缓存身份管理，不把下载重试当作上传恢复。
- 视频：原 owner 完整 owned 下载、容量/预算检查、播放和分享独立文件责任、返回取消、停止确认后清播放文件已经接入。断点续传/跨进程恢复和全格式网络隔离没有交付；实际 VLC 对本地 playlist 仍可能发生次级网络访问，fileURL 不是隔离保证。
- 录音：首次授权回调不自动开录；同页同 owner 的中断可保留预览，离页退休只处理本次未提交录音；下游接受 Data 后清原录音文件。没有跨进程预览或音频消息级重新上传。
- C3：上传成功 URL 写入 Drafty 并 msgReady 后才交原发送链（MessageInteractor:970–995）。35/36 的未知发送资格和同键重派发不能代替文件重新上传，也不能新补 UUID 把旧未知消息变成安全重试。

## 已有证据与本轮存在性核对

CI33 来源仍为 b098，run `35375538413`、job `105699232079`：**SDK 44 + storage 198 = 242 原生方法通过，另 3 个真实 App 离线身份导航通过，0 fail/skip**；打包和同模拟器冷启动通过。它证明本轮读取代码有历史编译/限定验证基础，不证明 27 页全部状态、真实聊天/客服或手机推送可用。

本轮重新读取以下 5 个实体并核长度/SHA-256，与旧交接完全一致：

| 实体 | 字节 | SHA-256 |
|---|---:|---|
| 根 artifacts/integration/20260918/R3-ios-ci33-evidence.zip | 50,270,844 | 0e7227eeec0d351efe518632f23e1f90af1c4f9f6bb3acb6be6ab72af3158f1d |
| 同证据展开目录 ios-01-a-20260918-173905/CLAW-OS-unsigned-simulator.zip | 37,665,378 | 22c2ad33ec01022c6eef3d9291f733779d6573e3cda4eee26cdcbc167c763e96 |
| FINAL-1B20EC2/CLAW-IOS-R3-source-test-ci.patch | 1,165,207 | 448633865dec72f1c178dce9ff0f4690b14bdc7eed039c38b1fe91259d85580f |
| CHAT-SCROLL-01/FINAL-FDEDF825/unit.patch | 97,716 | 29cc92f25a9b21100c9fb38b29796460810d946f146a7d365a3b60cb2e48e9f3 |
| CHAT-SCROLL-01/FOLLOWUP-B098407/unit.patch | 16,477 | 718837601a66f7e344b0f37c7c6e4f8ae0f9f63dfac3a25e314f1e37874c8da8 |

上表后 3 条位于本端 `docs/handoff/R3`。三段包的顺序仍是 **09631 → e30 → 6c0**，本批没有重新 apply、重封包或更改原还原指引。

限定运行证据：

- 身份导航为真实 App 离线输入/导航；无真实验证码或登录提交，secure 截图的显示掩码边界保留。
- 10 个聊天滚动方法使用真实 VC/UICollectionView 和中性 cell/FlowLayout；不是完整生产消息气泡布局或真实通讯验收。
- 6 个语音布局方法使用真实 XIB/UIKit，Recorder 方法使用实际类与受控 AV 依赖；不代表麦克风、设备权限或录音发送旅程。
- 7 个 VLC 方法是真实依赖/合成文件和 loopback 行为观察；PASS 不能解释为所有格式无外连，原完整 VideoPreview 页面未实例化。
- CI33 的原冷启动登录图、组件图/JSON和测试附件保留在原证据目录；本次存在性核对没有制造新截图或升级原证据等级。

## 本轮实际检查与未执行

实际执行：rtk 前缀下读取 Git branch/HEAD/origin/status；`git diff b098 HEAD -- . ':(exclude)docs/**'`；rg 定向查 Controller、segue、instantiate/push/present/动态导航与 help/bot；Python XML 解析 Main.storyboard 并与真实调用者核对；逐页源码阅读；5 实体 SHA-256/长度核对；JSON 解析、唯一 ID、源路径/行号有效范围、28 场景分类和引用存在性检查；提交前 diff --check 及新两文档 UTF-8/LF/raw=Git 字节核对。

未执行：生产修改、Swift/Xcode 构建、任何测试重跑、CI dispatch、远端 push、真机、真实 OTP/模型/客服、跨账号真实聊天、通知到达、系统分享、完整录音/视频 UI 旅程、恢复演练或包重建。后续测试/实现仅在总控冻结相应任务后进行。
