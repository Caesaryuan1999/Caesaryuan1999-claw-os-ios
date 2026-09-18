# PUBLIC-NAME-FALLBACK：缺少公开资料时不展示内部 UID

基线 `1a9f978636f29d9a42132e14463c5a576b53af65`（前一单文件建群私人备注文案已独立封存）；本批仅 `Tinodios/EditMembersViewController.swift` 与 `Tinodios/MessageViewController.swift`。不改 C3、AUTH、SDK、DB、目录或现 CI29 的 e1ed 候选。

三个实际展示位置复用现有 `AccountNames.contactDisplayName`：成员列表标题、已选成员条目、群消息发件人标题。先使用 trim 后非空的已有公开昵称，再用现有公开 accountName；没有可用资料时显示“资料未获取”。UID 仅供 helper 排除历史自动生成的展示名，不被返回为回退值。用户自己设置的正常非空昵称不按 UID 前缀猜测删除。

成员 accountName 仍取原 ContactHolder；来源已核 `ContactsManager.fetchContacts` 的 StoredUser.accountName，原写入由 FndSubscription 的公开 tags 提取。没有从认证用户名或 UID 派生新值。群订阅模型原本只有 public.fn、没有 accountName，本消费传 nil，不新增跨账号 Cache/DB 查询。三处每次渲染直接读取当前模型、重算展示，不持久化“资料未获取”；后续已有模型更新后再渲染可显示公开信息，不承诺本批新增自动拉取/自动刷新网络能力。

Windows 7 个源绑定检查通过，见 checks.json：两个生产文件、三个默认上下文 diff 块；三个实际消费调用及回退 key；群消息沿用原订阅；删除旧 UID 回退与不必要 senderName 强解包；完整选中、查找、点击和移除方法字节不变；公开号 helper/来源、SDK/DB、测试/CI 无 diff；git diff --check 通过。`EditMembers` 原 CRLF、`MessageViewController` 原 LF 保留。检查仅源级，不是 UIKit/成员/群聊运行。未写镜像行为测试。

原生选择与数量不变：232 原生 + 独立导航 3。本批尚未 Mac 编译或设备验证；原 PublicDirectoryTests 的公开号来源与无 UID 造名方法保持，不能将其原结果冒作三个新消费者已经运行。当前 CI29 已有真实失败由总控另行保存，本批不覆盖其证据。

回退：仅反向应用本提交的三个展示差异；不要更改 selection/remove/source UID，亦不回退既有身份、消息、私有备注与存储修复。真实多账号、资料晚到后的整页刷新、VoiceOver 和动态字体仍待 UI/设备验收。
