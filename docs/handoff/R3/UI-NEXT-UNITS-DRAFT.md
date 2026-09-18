# R3 iOS 下一批界面缺口草案（只读，未授权实施）

- 核查基线：`e1ed950147233f8e9df05ad025e5e356d0097dae`，分支 `codex/r3-20260918-ios`。
- 依据：根目录唯一 `docs/design/r2/DESIGN_SPEC.md` 当前 R3.D1（第 11、33、35、37、41 行），`PAGE_STATE_MATRIX.md` 当前覆盖表第 10–12 行。未修改这些共享文件。
- 当前任务只列最多三个有源码依据的后续单元；没有改生产、测试、CI、协议或数据。下面是源码确证及待执行的验收建议，不是新增运行结果。
- e1ed 的录音组件两文件修正由总控派发 CI29；本草案不提前引用其结果，不重复已封的身份、主导航、通讯录目录、我、通知、媒体或录音修复。

## 1. P2：建群时“群聊说明”实际保存为仅自己可见的备注

**真实入口与证据。** `Tinodios/NewGroupViewController.swift:229` 进入已有成员选择，返回后由 `rebuildPremiumGroupDetails` 安装群资料表头。第 258 行文案是“添加群名称和说明，创建后仍可修改”，第 286 行输入占位是“群聊说明（可选）”；第 304 行将该输入装入真实表单。保存第 370–374 行将它作为 `privateInfo/subtitled` 传递，实际第 459–462 行写入 `topic.priv["comment"]`。无头像第 475 行及头像分支均构造名称/头像公开资料，没有将该输入写入公开说明。

**影响与复现条件。** 创建群聊时填写“群聊说明”，创建者容易把它理解为其他成员可见的群说明，但当前字段只有创建者自己的私有备注。这里没有认定信息被公开；问题恰是可见范围的文案与实际保存范围不一致。它不同于已封的 TopicGeneral 既有群备注保存修复。

**建议最小包：1 个生产文件。** 仅 `NewGroupViewController.swift` 的说明和 placeholder 对齐“备注（仅自己可见）”及可选含义。保持原 `private.comment`、公开名称、头像、tags、成员与权限语义，不迁移旧备注、不另造公开群说明字段。

**后续验收。** 实际表头文案与可访问性值核验；SDK/创建请求的 private.comment 原样保留、pub 与 tags 不变。真正多账号建群与他端可见范围需服务/设备验收，不能由文案检查替代。

## 2. P2：资料缺失时，成员选择和群消息发件人展示内部 UID

**真实入口与证据。** `NewGroupToEditMembers` 和 `TopicInfo2EditMembers` 的 storyboard segue 分别在 `Tinodios/Base.lproj/Main.storyboard:2569`、`:4121`；对应真实成员编辑控制器中：

- `Tinodios/EditMembersViewController.swift:260` 列表标题为 `pub.fn ?? accountName ?? uniqueId`。
- 同文件第 423–426 行已选成员条目为 `pub.fn ?? accountName ?? uid`，资料尚缺时会直接采用内部选择键。
- `Tinodios/MessageViewController.swift:1152–1159` 在需要显示群消息发件人名称而订阅公开名称缺失时，将 `message.from` 格式化成“未知 %@”。此处同样展示 UID，不是公开 alias。

**影响与复现条件。** 一个实际缓存联系人缺少公开名称和 accountName，或已选成员资料尚未加载，成员列表/已选条目显示其内部 UID。群消息来源订阅缺失或 `pub.fn == nil` 时显示“未知 usr…”等内部值。这违反 R3.D1 的公开标识与 UID 分离要求；不声称该 UID 是密码或据此证明越权。

**建议最小包：2 个生产文件。** 仅 `EditMembersViewController.swift` 和 `MessageViewController.swift` 的名称展示回退：优先保留已取得的公开名称/公开号，否则采用准确中文匿名或资料未获取文案。UID 继续作为内部选择、移除、邀请和消息来源键；不改目录查询规则，不从内部用户名或 UID 推导公开号，不修改 SDK/DB。

**后续验收。** 真实成员 cell/已选条目与 `senderFullName` 分别覆盖有昵称、有公开 accountName、缺资料、资料稍后到达；断言可见文本不包含内部 UID，原选择/移除键不变。完整系统通讯录、权限与群消息页面仍需单独运行，不把纯格式化用例当完整流程。

## 3. P2：回看历史时，最新消息触发的整批刷新仍会滚底；返回最新缺中文动作名

**真实调用链与证据。** `Tinodios/MessageInteractor.swift:1017–1023` 按收到的 seq 判定 `newData` 后调用 `loadMessagesFromCache(scrollToMostRecentMessage: newData)`，第 449–456 行把标志随真实存储页面传给 presenter；`MessagePresenter.swift:58–60` 在主线程原样传递。实际 `MessageViewController+MessageDisplayLogic.swift:128–144` 统计更新批次；当旧消息非空而累计新增超过阈值 5（`MessageViewController.swift:148–150`，300ms 批次窗口）时，重载后仅凭该标志调用 `scrollToBottom()`，没有读取用户是否正在回看。第 181–188 行的变更刷新分支也仅凭同一标志滚底。`MessageView.swift:72–75` 实际滚动到内容底端，没有第二层回看门禁。

另外，`MessageViewController.swift:570–598` 的真实“回到最新”按钮只有 chevron.down 图像，未设置中文标题或 accessibilityLabel；`Utils.swift:282–293` 的图标样式方法也不补动作名。第 1528–1533 行只根据距离底部 40 点控制可见性。

**有界复现。** 先让真实消息 collectionView 显示非空历史并滚离底部；经真实 `displayChatMessages` 传入比旧数据多 6 条的页面与 `scrollToMostRecentMessage == true`，进入整批刷新分支后会请求滚底。线上连续新消息可走此链，但本次没有执行真实网络/页面滚动，不声称每个单条新消息都会滚底（仅插入、无 refresh 的分支不在此结论内）。

**建议最小包：2 个生产文件起步，须另冻结方案。** `MessageViewController+MessageDisplayLogic.swift` 在更新前捕获真实视口/可见消息锚点，区分首次装载、用户已在底部、回看历史；`MessageViewController.swift` 为现有返回最新入口提供明确“回到最新消息”的可见/读屏表达并保留真实 action。不改消息队列、seq、已读、发送回执或数据库；若必须把发送后的显式定位意图与来消息提示拆开，先另报精确调用点，不能把当前所有 true 一律忽略。

**后续验收。** 使用真实 collectionView/消息布局验证：回看 + 超阈值新增保持原锚点、底部用户继续跟随、首次装载和显式按钮到最新、更新/分页不会跳错位置。保留原消息数据与 C3 回归；UI 源策略只能证明接线，不能替代真实 UIKit 布局/滚动结果。

## 范围与交付界限

建议顺序为 1（单文件语义修正）→ 2（缺资料展示）→ 3（真实滚动状态）。三个单元均为待总控冻结的独立提案，本草案没有实施它们。

本次未把固定字号、Figma 尚未覆盖、未知设备效果或未运行页面一概登记为代码缺陷。身份真实供应商/法律资源、APNs/真机、完整媒体播放/分享、系统麦克风与已知消息级重上传缺口继续沿既有台账，不在此重复扩项。

核查只读代码与唯一规范；没有运行 Swift/Xcode、界面或新构建。CI29 结果由总控另行收证，当前源 SHA 仍为 e1ed950。
