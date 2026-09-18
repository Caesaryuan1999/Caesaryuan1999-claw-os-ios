# R4 AI iOS B02：已知 run 查看 / 恢复 / 明确停止（只读提案）

本提案读取总控 `R4_AI_CLIENT_B02_TASK_PACK.md`，没有实施授权、没有源码/测试/CI 修改。当前 docs HEAD `d9f43b1848f1f0a8ee72071b9b2e6f3f2066f9c8`，生产 `b004af0d5c5d8ce2f7560fad04ed8711694c8e23`，B 核心 `e9eba400129c734315e8176d00e5b2a52e2bc74f`。CI39 run35402042528 / job105783842048 由总控执行；当前只知 SDK44 已通过，storage 仍在构建，不能把293+3期望写成通过。

## 当前实际入口与缺口

- `Tinodios/ClawAssistantViewController.swift:29` 的 ClawAssistantPage 持有 Session 并观察 History；`:46–59` 仅隐藏后台页面、激活时调用 refreshVisibleScope，没有 run reader 生命周期。主页开始提问仅开本账号草稿页，没有 POST；历史按钮 push 真实列表。
- `Tinodios/ClawAssistantHistoryViewController.swift:96` 的 didSelectRow 直接 push 详情，尚无停止未知跨 cid 决策。
- `Tinodios/ClawAssistantConversationViewController.swift:51` 进入读取 A 历史，`:57` render 仅 A details；`:100` 起按数组重建 UIStackView。发送恒 disabled、没有发送 target。页面未创建 B Run，也没有停止、恢复或 run 状态渲染，不能因 B1 存在就声称已接流。
- `Tinodios/ClawAssistantHistory.swift:149–203` 有全分页暂存、同 revision、最多两次 snapshot_changed 重启、完整页集成功后替换；A details 仍是 ClawAssistantMessage。`:207–246` 有原删除 pending/unknown/tombstone，但没有 B 投影通知。
- `Tinodios/ClawAssistantService.swift:79–88` 只有 A messages limit20。`ClawAssistantModels.swift:297–343` A 仅 partial/interrupted；不能为 B 直接放宽它。
- B1 Run 只在测试中创建；它持有 Session，只有内存 ticket/receipt/projection，setVisible(false) 关闭 reader/delay，stop 有独立 task。缺少跨页面持有者和已知 run 专用生成门禁；不能在详情 VC deinit 时 retire 它而丢 stop pending/unknown。
- `Tinodios/Cache.swift:103–143` 已负责 scope 捕获/退役：首次要求实际鉴权和持久账号；同 SDK/UID/token/origin/generation 可复用。markRetired 在锁内，finishRetirement 在锁外。此处只读，建议 B02 不修改 Cache/SDK/登录入口。

## 建议精确八生产文件

| 仓库相对路径 | 最小变化 |
|---|---|
| `Tinodios/ClawAssistantModels.swift` | 独立 B message/page DTO、协商后的角色状态与角色字节限额、视图只读投影值；保留 A validator |
| `Tinodios/ClawAssistantService.swift` | 显式 messagesB，固定 limit10/items≤10、after_seq/revision 校验，沿原24MiB响应限额/同源门禁 |
| `Tinodios/ClawAssistantRun.swift` | 显式 knownRunsOnly 模式，在 submit/retrySubmission/retryAnswer 联网前拒绝；已知身份绑定和页面 reader lease；弱 Session 引用及完整 nil/current 门禁避免持有环 |
| `Tinodios/ClawAssistantSession.swift` | 持有唯一已知 run 上下文及当前页面 lease，跨页面保留 stop pending/unknown；统一选中 cid/rid 决策与删除协调，沿原退出通知在锁外取消 |
| `Tinodios/ClawAssistantHistory.swift` | 保留 A details，另存完整 B 历史快照和 snapshot revision；显式 B 分页、旧快照保留、单向删除状态通知 |
| `Tinodios/ClawAssistantViewController.swift` | 原 shared Page 加入实际前后台/可见页面挂接与 reader lease；共享“原停止结果未确认”提示及返回确切旧回答；不新接登录 |
| `Tinodios/ClawAssistantHistoryViewController.swift` | 打开另一 cid 前先检查原 stop，取消不改变 selectedId，允许仍返回列表/主页 |
| `Tinodios/ClawAssistantConversationViewController.swift` | 已知 run 的真实状态/恢复/明确停止、按真实 message ID 更新一行和保阅读锚点；生成保持 disabled，无发送/重生成动作 |

不新增生产文件、target、依赖、协议、schema、持久 journal 或 Keychain；不改 ClawMainTabBarController、导航层级或既有认证流程。UI 与实际状态门禁可分提交，但需共同验收。若实现时八文件无法闭合，先报具体依赖，不自行扩范围。

## 数据流与所有权

### 1. 明确协商后才读 B；全部成功才替换

以当前 Session 的 capabilities.validateRuns 成功为显式 B 读取条件，不以 generation.available 推断；stream=false 仍可读 GET/历史。每次 load 固定当前读取模式、能力、cid、page generation，不在后续回调里借新能力解释旧页。

B messages 每页10；user32KiB、assistant256KiB，UTF8逐字节计数，未知角色/状态整详情失效。最坏10个256KiB正文全部6倍JSON转义约15MiB，连元数据小于现24MiB预算；需真实最大转义页测试。新 POST 输入仍32000字节，本批没有提交入口，不将提交限额和历史读取上界混为一项。A limit20及 validator 原样。

同一个 snapshot_revision 完整页集与重复 ID/seq/cursor 校验后一次提交；snapshot_changed 最多两次从头重取，仍保留上次完整快照。失败不跳行、不把暂存半页显示成完整历史。

### 2. 只恢复最后一个真实已知 run

从完整详情按 seq 取最后一条具有非空 run_id 的行，只发一个 GET，不逐行扇出。GET cid/rid/question_message_id/answer_message_id 与完整详情中真实 user/assistant 角色相合才绑定；不从正文推测、不填假行。legacy 空指针仅历史展示，缺行先重读权威详情，不凭空插入。

A/B 完整历史与 Run 投影分别保留；页面派生一个只读渲染快照，只覆盖同 cid/rid/answer ID 的 assistant 行。比较明确的 snapshot_revision 与 run revision，不让旧历史覆盖更新投影；历史不提供 last_event，绝不据正文长度制造 cursor。Run 仍通过 GET 原子接受 text+last_event。terminal 只触发一次权威详情对齐，不能由 changed 回调循环加载。

### 3. 原 Session 保留 stop，页面只租用 reader

Session 持有单一 known-run 上下文（cid/rid/原身份和 pending/unknown stop）。Run 改为弱 Session，防止 Session→Run→Session 环；已在 B1 封存的 current/operation/身份检查仍需保留。UI 的页面 lease 为独立 UUID；旧 viewWillDisappear、后台或 deinit 只能释放自身 lease，不能关闭后来页面 reader。

真实 viewWillAppear / viewWillDisappear、willResignActive / didBecomeActive 结合原 nav.top、window 和 page lease。离开、切 tab、后台关闭 reader/定时恢复而不 stop；回来仅 GET 原 rid，不能自动 POST。仅 viewDidLoad/历史会话 id 不代表可见。更旧页面的通知不能开启当前不可见 reader。

首次 scope 沿 Cache 的真实登录门禁；已建立 scope 的纯 WS 离线保留 HTTP 读取规则。401 只 block 原助手 scope、隐藏两套内容并显示“前往账号设置”，不自动 logout/清库。SDK/UID/token/origin/generation 退休让原 scope 立即不可消费；取消与 Run retire 在既有锁外 main 通知阶段执行。跨认证代次/进程只重建已知 run 的 GET，不承诺持久保存旧 stop 不确定性。

### 4. 停止未知与跨会话导航

queued/running 必须由实际 Run GET/事件证明；单独 partial 只写“回答尚未完成”。legacy/terminal 不提供停止或重新生成。knownRunsOnly 三个生成入口在 capability判断/notify/network 前都拒绝，generation=true 的合成样本仍零新会话/新run POST。

stop 捕获确切旧 cid/rid/身份；等待200真实terminal，completed不改名stopped。timeout/5xx保持unknown，active GET不能清掉。状态保留在Session而非VC，因此返回主页/列表不会丢失；点击不同cid先展示“上一段对话的停止结果尚未确认。请先查看原回答状态。”，取消不改selectedId，“查看原回答”回原cid/rid仅GET。另一个“再次停止回答”必须显式同run POST，不与只读按钮混同。

### 5. 删除与页面锚点

原确认流程保持。History pending 时协调相同cid reader暂停；200/合法410/权威墓碑先更新History，再在receive锁外通知Session清匹配Run，非当前cid不清另一投影。未知删除继续保留unknown，不能因active列表就称旧DELETE绝不会提交。禁止History和Run互相递归发布删除。

详情继续UIKit/UIScrollView；按message ID复用实际行，正文变化前记录首个可见行与像素偏移，布局后恢复。仅原本在底部或明确“回到最新”才跟随。键盘/安全区/AX变化同样保持实际锚点，不从流事件新增未读数。无需修改真实聊天的九文件滚动单元。

## 原生验收建议（方法数量待实现后实核）

新增 `TinodiosUITests/AssistantKnownRunTests.swift` 和 `AssistantKnownRunLayoutTests.swift`，复用现 App-hosted target 与实际 SDK/SQLite/URLSession consumer，追加 PBX membership/现 selector；不新 workflow/Pod/target，不重复未变60秒以凑数量。原293 native+3导航完整保留，只有真实受影响方法需要增量。

- 实际 Service+History：B10最大转义页、角色限额、完整分页/同revision/坏页保旧/未知状态、A20兼容。
- 实际 Session/Run：known-only 三入口 generation=true 零创建POST；单knownRID/角色指针校验；重复prefix、旧history和新run版本；legacy缺指针只读。
- 实际页面 lease + UINavigationController/生命周期：详情离开只取消reader，回来GET；旧view回调不关新reader；stop pending/unknown返回列表及再进原cid仍保留，跨cid明确提示/取消/返回原回答。
- 真正消费者：stop200completed、失败unknown、activeGET仍unknown、显式再次stop；401/同UID新认证/旧owner晚回包清内容不清本地账号；删除pending/墓碑/迟回包不会复活。
- 真实UIKit浅深/320pt/AX/52pt按钮、body增长和历史阅读锚点；截图与几何原样导出。合成账号/API边界不可写成真实模型、真实通讯或设备验收。

本次没有改上述八源、没有创建测试或任何运行样例。模型仍未配置，生成/重提交/重生成 UI不开放；journal/真实provider/跨设备运行恢复继续OPEN。实施需总控冻结iOS精确允许清单并取得B1实际Mac结论。
