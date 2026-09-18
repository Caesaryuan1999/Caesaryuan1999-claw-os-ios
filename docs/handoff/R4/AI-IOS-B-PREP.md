# R4 iOS AI-B1 客户端准备（只读，未实施）

2026-09-19。本报告读源基线 docs HEAD `6d332899c8e50579a77de75e3d31155efb5a934c`，A生产固定 `6a0e8584ff9f135528f4832184eb92b3f0eeb9a3`。分支 `codex/r3-20260918-ios`，origin `https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git`；开始写文前 tracked dirty 0、untracked 19782。封文前总控回报CI36/run35395649605失败：SDK44通过，AssistantLayoutTests未import DB导致SharedUtils不可见，225 storage方法/导航/打包/冷启均未执行。已按根授权独立封一行测试import修正 `5c91a4b67f58b2be7ec957ddc38c0b3136274450`，本文随其后docs-only提交，生产仍6a。15 History + 6 Layout方法及全部正文/断言保持；累计269原生+3导航仍待后继Mac验证。本文不实施B，不改A生产、SDK、数据库、CI或原交付包。

依据为公共 `docs/context/PROTOCOL_CONTRACT.md:314–346` AI-B1 及 A 身份/快照/删除规则；只读固定后端 `da785bb3a4187ec22ca42fdc86500d69008747ac` 的 `server/assistant/types.go`、`server/hdl_ai_stream.go`、`server/hdl_ai.go`、`server/db/postgres/assistant_runs.go`。另读 Android `docs/handoff/R4/AI-ANDROID-B-PREP.md` 比对边界，不改对端。未请求6097/6099、未读私有配置、未构建/触发CI。

## 建议结论与待冻结点

B 可以继续使用 A 的账号 scope、原生页面和第四导航；不能把现有整响应 JSON reader 直接改名当作 SSE。建议最多十生产文件，传输/恢复和页面接线分提交，共同验收后才允许开启真实生成。当前生产 DisabledProvider 下仍可读取真实旧 run，不能自动建立空会话或伪造回答。

**跨进程丢回执不能由现有 A 内存草稿解决。** 推荐在本次 B 范围内显式冻结账号隔离的未决请求 journal（下述第10文件）：在首次 POST 前保存原 cid/request_id/text/retry_of，进程重建只恢复原票据供用户明确核对。若总控选择首批仍仅内存，则必须在交付中写明：无回执且无已知 run_id 的提交在进程死亡后无法可靠关联；不能以同文、新 request_id 或“重新发送”弥补，也不能称满足跨进程恢复。本报告提出 journal，并未自行批准正文持久化、保留期或退出后的留存政策。

须在实施包冻结三项本地策略：①是否采用 journal，以及正常退出/账号注销的保留或删除规则；②只在可见前台进行读取恢复，建议异常读重试最多3次、1/2/4秒，连续无进展耗尽后提供手动核对（正常60秒轮换不当作生成重试）；③补记后端已实现的503 `execution_unavailable`、事件可选字段和对应中文。以下具体值均为工程提案，不是已开放承诺。

## 十生产文件边界

| # | 仓库相对路径 | 有界职责 |
|---|---|---|
| 1 | `Tinodios/ClawAssistantModels.swift` | B能力/按role的message状态、run receipt/snapshot、event/page DTO、严格匹配及错误枚举；A旧模式仍独立严格解析 |
| 2 | `Tinodios/ClawAssistantService.swift` | 复用原 origin/APIKey/token 建请求；增加显式create、submit、GET run/events、stop，各路由精确成功码；保留A JSON/DELETE行为和401优先门禁 |
| 3 | `Tinodios/ClawAssistantSession.swift` | 持有账号内 run 协调器；原 scope/token 退休、401、同UID换token时取消旧网络/订阅；新scope只从原run或明确票据恢复 |
| 4 | `Tinodios/ClawAssistantHistory.swift` | B协商后的全快照状态解析、墓碑/pending-delete与run投影协调；不放松分页完整性，不把每个delta写成一次历史全量重拉 |
| 5 | `Tinodios/ClawAssistantViewController.swift` | 已有助手首页的B能力反馈、共享页面前后台/订阅接线；第四导航、历史标题/时间和账号设置恢复入口不重做 |
| 6 | `Tinodios/ClawAssistantConversationViewController.swift` | 真实发送、正在核对/读取、停止待确认、手动retry_of、legacy说明；键盘/AX/52pt动作沿原UIKit，不自动滚走正在回看的用户 |
| 7 | `Tinodios/Cache.swift` | 仅既有assistant detach/新scope接线，同步退休令牌与锁外取消；若journal批准，绑定新真实登录后的原origin+UID账户，而不在Cache锁内读写文件 |
| 8 | 新 `Tinodios/ClawAssistantRun.swift` | 主线程run状态机、冻结原请求、串行提交与独立stop、同run投影/游标、读恢复与一次性回包门禁；不直接访问当前Cache取新凭据 |
| 9 | 新 `Tinodios/ClawAssistantStream.swift` | 独立ephemeral URLSession增量SSE、有限缓冲/绝对连接期限、真实delegate取消；不接新生成或修改全局HTTP配置 |
| 10 | 新 `Tinodios/ClawAssistantRequestJournal.swift` | **待明确批准的本地持久单元**：原请求不可变记录、原子写/损坏拒绝/隔离/清除责任。若首批拒绝journal，删除此文件与Cache不必要接线，并明确跨进程未完成边界 |

现有 `NewChatTabController.swift` 已是四导航，无需修改；HistoryViewController保留真实title/updated_at与删除反馈。无 storyboard/XIB、主题重写、依赖版本、普通Tinode消息/SQLite schema、AUTH/C3、客服工单修改。必要测试/项目成员与现selector另计，workflow/Podfile不在建议范围。

## 现有源事实与复用方式

1. `Cache.swift:109–143` 初建scope要求当前SDK已实际鉴权、Store UID一致、Keychain token与SDK token相同；scope复用检查owner对象/generation/origin/token。`ClawAssistantSession.swift:48–82` 继续核原SDK、UID、token、有效期、Store、origin。**客户端没有可凭空使用的服务端epoch字段**，token保持不透明，最终epoch由服务端验证。不能用BaseDb仍留UID单独创建B权限。
2. 原已建scope允许纯WebSocket断线但未变的有效HTTP token继续使用，见Session.withCurrent；不能为B误加必须WS实时在线的限制。token改变时旧scope停止，新scope在再次真实登录门禁后恢复同rid；不能让旧回调读取新token后继续执行。
3. `Cache.swift:62–106` 在SDK→Cache锁内detach/markRetired，defer出锁才finishRetirement；`Session.swift:97–114` 的service.cancelAll/notify亦锁外。B沿此顺序同步废scope/操作代次，出锁取消stream、JSON与timer，UI更新主线程后再检查原scope/run/页面代次。禁止锁内等网络、文件、main.sync；禁止stream回调反取新Cache账号。
4. `Service.swift:31–48,98–134,180–225` 已有同源TLS、认证头、ephemeral/no-cache/no-cookie、禁止redirect及真实401优先处理，但只接受HTTP200，并在完成后整包解码；JSON request/resource分别20/30秒。B按路由增加create201/200、submit202/200、run/events/stop200；不全局接受任意2xx。流单独text/event-stream reader，不扩大A的30秒资源上限。
5. `History.swift:66–81` 在main上按原操作票据/当前scope原子apply；分页两次409重启后保旧完整快照，墓碑废除晚GET/DELETE。B保留这些规则。运行时高频revision变化不意味着可以提交半页历史；独立run投影只覆盖明确answer ID，稳定终态/回到历史再完整刷新。
6. `Session.swift:5–28` 的AccountMemory仅内存文本，logout会retire并清；`ConversationViewController.swift:67` A恒禁发送。`Models.swift:139–149` A仅partial/interrupted。B必须按已协商 `run_protocol=claw-ai-run-v1` 及冻结role-state集合选择解析模式，未知state整详情失败留旧快照；不能仅见generation=true就开B。旧无B服务保持A读取/禁B操作，已有A的“未来字段不启用B”测试应继续覆盖未协商模式，不能简单删掉。

## 首次提交、已知run与持久票据

用户明确点击发送且generation可用时才冻结UTF-8原text（不trim、不Unicode归一化）、小写UUIDv4 request_id及可选retry_of。正文非空、≤32000 bytes，实际序列化JSON≤65536 bytes。新会话才分配cid，只有这次明确发送触发POST conversations；返回匹配201/200后才POST runs。create超时保留同cid供显式核对，不换cid自动再建。即使provider在create后失效，已建空元数据可能存在，不能宣称整个两请求链原子或绝无空会话。

run POST必须匹配cid/request_id及新run非空question/answer UUID；receipt202只是接受，不是回答完成。receipt不带完整answer text，因此**不能仅采用receipt.last_event作游标**而丢掉此前已经写出的delta：先GET原rid取得一致的text+last_event，或从0完整回放，建议前者。

未知submit包括已dispatch后的timeout/断连/不匹配回执/非预期成功码/不确定5xx。保留原key及body，不清输入后画“已发送”；已知rid只读GET，未知rid须明确“核对原请求”后以同key/同text/同retry_of重放。已有key恢复在provider关闭时仍可返回原run；新key503 provider_not_configured才按冻结合同视为未接收。先前请求未知时，后一次明确拒绝不自动证明先前永不提交，仍保原票据待权威结果。页面离开不等于取消已提交写操作。

建议journal字段（本地格式，不新增wire）：格式版本、原origin/UID、cid、request_id、text、retry_of（无则不序列化）、操作种类create/submit/stop、已known rid（可无）、派发阶段、待核对状态。持久化同一解析载荷并保留首次body字节校验值；不保存APIKey/token/SID/密码/伪造epoch。stop不需要问题正文，但须记录同rid的停止未决事实，不能重启后错误展示已停止。

建议每个origin+UID最多一个未决写票据（与“每账号最多一个活跃run”不同，属本地提交互斥），不会覆盖前一未知请求。**先持久化成功，再允许网络resume**；写失败零POST并准确说明无法保全请求。写入后、resume前崩溃也按未知保守恢复，不能推定已发/未发。收到回执后记录rid失败时仍保原key，不换ID。权威结果已匹配后可以删除原正文票据并从服务历史恢复，清除失败须有追踪责任，不能无证承诺落盘副本已清。

本地介质建议为App Application Support专用目录，原origin+UID派生不含原文的文件键、版本化加密记录、原子替换、禁止backup。加密键可用系统CryptoKit和Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不引入依赖；锁屏/密钥不可用/认证标签失败/未知格式一律拒读拒派发，不自动删坏记录后用新key重发。Apple说明该Keychain类别仅解锁可访问、设备限定；这不是磁盘物理擦除保证。[Apple文档](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)

文件I/O在journal专用串行队列，不持SDK/Cache锁；异步完成后原scope再核才能dispatch或呈现。journal本身还需每账户record代次/墓碑，保证较早写完成不能在较晚删除/退休后复活票据。正常logout立即隐藏并取消网络；是否保留加密未决票据给**下一次真实认证同origin+UID**显式恢复、还是退出即删除，是本包待总控冻结的产品边界。不能把内存generation跨进程持久当认证，也不能向B账号列出A未决记录。账号注销、手动删除会话、密钥/文件删除失败的策略需同时冻结；若需要改现有注销消费路径，超过上表十文件时另报窄依赖，不藏在Cache广泛重构里。

若不批准journal：当前进程保原票据；重启后只通过真实历史的run_id读run及文本恢复，不按正文猜关联。后端虽能同key重放，但丢掉key的客户端不能利用此保证。Android准备稿目前明确是此内存方案；不能把两端不同恢复能力写成双端等价。

## SSE、GET恢复与停止的独立生命周期

- Service统一构造受控请求，token/APIKey不暴露给View。stream占独立URLSession delegate通道；submit/stop/GET仍走独立短JSON请求，不排在长stream后。每scope最多一个活跃reader，每run一个stop在途，取消reader不会cancel整个service，更不会自动POST stop。scope退休则两种通道都取消。
- 逐字节解析UTF-8：codepoint/行/帧可跨任意delegate块，支持LF/CRLF/CR及多data行、空行结束、comment心跳。有限64KiB单事件缓冲建议由4KiB delta最坏JSON转义与元数据推导；校验解码delta≤4KiB、run输出≤256KiB、事件≤1024。不是把整60秒body存入Data。分帧依据[WHATWG SSE解析](https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream)；本契约另行禁止redirect、限制事件种类，不照搬浏览器自动重连/204完成语义。
- 请求只用Last-Event-ID或after_event之一，建议Header。持久accepted/delta/terminal的SSE id必须等于data.id、event名等于kind；十进制字符串0…Int64.max，无Double。control access_error不分配持久id，comment不增游标。terminal无reason时合法（omitempty），GET.reason必须存在但可空；不能用一个字段要求误拒真实completed。
- `GET /runs/{rid}` 的text是**已保存answer输出**，固定后端`assistant_runs.go:28–37`取output_text；将text/state/reason/revision/last_event按同一原run快照原子替换。此后仅追加严格next id，≤snapshot.last_event不重复拼接。新GET与旧stream用operation代次互斥；gap/矛盾重复/未知event/游标越界先废reader并GET原run，不调用生成。
- events JSON每页独立权威last_event/state可能前进，按连续ID和next_after_event补读，不假造A的snapshot_revision查询；遇缺口停止并核GET。完整历史的snapshot_changed仍从第一页有限重拉、旧完整页保留，不用run投影替换会话全集。
- stream绝对60秒截止用单调时钟，心跳/有数据不得延长；token到期或owner失效也取消。当前A的20秒idle策略不能直接作为SSE“执行失败”；新连接独立预算。EOF/204/超时不等于completed，GET核对原run，仍active时只恢复读取。正常轮换/异常退避都不在后台无限常驻；后台/离页取消reader，前台回来先GET。已提交run不因本地reader取消自动停止，不能承诺供应商停止计费。
- snapshot已terminal，迟到queued/running/delta不得回退；同终态也不能用更旧text覆盖。既知本地更高游标而GET返回较低快照不应清零接受，保留当前内容并显示核对异常。410墓碑立即废该cid所有consumer，晚事件不得重新显示。DELETE pending/unknown冻结run新写动作及流呈现，只有权威墓碑可说已删除；临时active读取不证明删除未发生。
- stop点按只发同rid无body/query，显示“正在停止”；返回匹配200权威终态及完整text，以可能已completed等实际状态为准。timeout/5xx/坏回执为“停止结果暂未确认”，一次active GET不消除该未决意图；同rid明确再次停止可幂等，绝不再发问题。stop取消句柄与reader取消句柄独立，stop结果不能被reader取消错误覆盖。
- legacy:true只读，允许真正缺失的question/answer指针空串，不能虚构；即使有question也不允许retry_of。新run两指针必须UUID。只有非legacy、最后一题interrupted/failed才显示明确重新回答，取匹配question_message_id的真实原字节、新request_id+retry_of；旧partial/answer保留。stopped/completed不重试该run；服务409处理另一设备已发新题/已活跃竞态。

## 错误与页面反馈分层

| 情形 | B消费行为（最终中文待根规范统一） |
|---|---|
| HTTP401，含非JSON/缺MIME；SSE access_error authentication_required | 原助手scope封闭/隐藏，取消原reader；仅现有“前往账号设置”，不普通logout/清库，不借新token继续旧consumer |
| 403 / 404 | 明确权限/无法访问原run；404不当删除墓碑。旧未知写不能被后一次拒绝抹成确定未执行 |
| 410 conversation_deleted | 原cid权威删除，清本scope投影与待核对入口；处理本地journal清理责任，不能复活 |
| 409 snapshot_changed | A完整历史重新分批获取；不是重新提问 |
| 409 cursor_ahead | GET原run核游标，不换rid、不生成；异常快照不回退已知终态 |
| 409 request_conflict | 原key/载荷关联错误，禁止自动新key；保全原票据、让用户核对 |
| 409 run_in_progress / retry_not_allowed | 刷真实历史/run后明确说明，不能用当前编辑框偷偷改retry正文 |
| 413 body_too_large / context_too_large | 原提问/上下文超工程保护范围，保草稿，不静默截历史或分拆生成 |
| 503 provider_not_configured | 首次新key按合同零run/问题写，草稿保留；已有key恢复仍可成功，不因当前cap=false屏蔽所有原票据核对 |
| 503 execution_unavailable / history_unavailable；500；非预期成功/损坏body | 区分读失败和已派发写未知，不统称未发送/provider缺失；execution_unavailable码须公共合同补记 |
| SSE access_error其它白名单；未知code/帧、EOF/204 | 不显示原始body/error文本；终止该reader，按原scope核GET或显示兼容/待核对，绝不猜完成 |
| queued/running / partial / completed/stopped/interrupted/failed | 活跃状态来自run，不从message.partial推测；user.completed只指问题入助手历史，不套普通消息送达/已读 |

已确认R4.D1设计索引：恢复/中断/已停止275:1384/1411/1440，停止等待/结果未知278:1404/1436，状态组件274:1372；本次仅核公共索引，没有重新get_design_context或把旧设计截图当实现证据。正式实施前获取受影响节点最新上下文，不添加样例回答。现有52pt中文按钮、深浅/AX、真实账号标题/时间、无preview保持；流更新只更新对应真实answer，用户回看不被每delta抢底。

## 原生证据计划（待实施后按实际方法锁数）

复用当前App-hosted `TinodiosVoiceLayoutTests`，生产类直接成员/`@testable import Tinodios`，不新建替身播放器/状态模型。建议新增 `TinodiosUITests/AssistantRunTests.swift`、`AssistantStreamTests.swift`、`AssistantRequestJournalTests.swift`，现有 `AssistantLayoutTests.swift`加真实动作消费与画面；`Tinodios.xcodeproj/project.pbxproj`和`Scripts/ci/verify_publish_outcomes_macos.sh`仅追加必要成员/selector。总控冻结最终文件与方法后再计算CI数，当前269+3全部保留，不能先加一批虚拟计数。

| 实际生产入口 / 用例建议 | 证据与不能替代的边界 |
|---|---|
| Run：先存票据再dispatch，存失败零POST；create超时同cid；202/200严格回执及原body重放 | 真实Service/Run/Journal + URLProtocol受控lost response；另一次loopback实际socket验证请求确已收到。不是正式provider |
| Run：GET text+last_event恢复，snapshot与旧stream重叠、重复delta/gap/较旧快照 | 使用真实Run消费方法与Service DTO，不镜像拼字符串算法；保留原已确认前缀/终态 |
| Run：reader阻塞时stop实际独立发出；stop丢回执→GETactive→随后terminal | 双真实HTTP连接及屏障观察请求次序，无sleep猜测；completed抢先不能被stopped覆盖 |
| Run：同UID换token、logout换B、同UID重登、origin变化、旧scope401/lateevent | 实际Tinode/独立BaseDb夹具；Cache slot边界若注入必须明说，不能据此宣称真实Keychain登录全链通过 |
| Run：legacy空/有效指针、禁止legacy/stopped重试；最后一题failed/interrupted正确retry_of | 真实DTO与question匹配，无正文相同去重；合成服务409模拟跨设备新题，真实跨端待联机 |
| Run：墓碑与晚stream/GET/submit/stop；未知DELETE仍active | 原History与Run真实联合消费，A原21方法全部保留 |
| Stream：任意字节分块的中文/emoji、CRLF/LF/CR、多data/comment、帧跨块与EOF半帧 | 实际增量parser；URLProtocol可控块只属delegate证据，另真实loopback分块HTTP与取消证明未等EOF才消费 |
| Stream：id/kind不符、连续/重复/缺口、Int64边界、unknownstate、terminal省略reason、access_error无id | 严格wire检查；不把unknown帧跳过后继续当完整输出 |
| Stream：64KiB帧/4KiBdelta/256KiB输出/1024事件、持续心跳仍到绝对deadline | 真实生产计时入口可注入单调时钟做边界；另一次实际有界连接证明60秒约束，不能只改测试布尔 |
| Stream：同源头/redirect拒绝/no-cookie-cache、401 HTML及nilMIME、204/EOF非完成 | 真实URLSession delegate；不以parser单测代替网络行为 |
| Journal：真实临时目录加密写/读取/损坏/未知版本/密钥不可用/容量与写失败 | 真FileManager+CryptoKit，Keychain设备类别需独立系统证据；不记录正文/密钥/token |
| Journal：崩溃边界重建新对象/可行时host子进程，原key/body精确一致，晚写不能复活删除 | 对象重建不称进程kill；真正跨进程需保存前一进程输出、确认重启后读取同记录且零自动POST |
| UIKit：真实页面pending→流前缀→stop未知→GET恢复；重新回答保存旧partial | 原UIKit类、320pt/AX/深浅/键盘/52pt、截图几何；确认动作真正route到生产Run，不仅测按钮文字 |
| UIKit：离页/后台取消reader但不stop、返回同run、换号隐藏、provider关闭草稿 | 原页面/生命周期测试；不能把受控callback当完整真实通讯或后台系统调度通过 |

Windows只可做源/项目/差异和文档检查，不宣称Swift/Mac通过。6099/PG120由总控独立验，真实provider仍关闭；本端未调用它。后续若需联机，只使用总控冻结的专属合成账号/fixture；Mac云端不能直接访问本机Windows loopback，真实本机socket在Mac测试宿主自己启动。真实模型、跨设备、iPhone、签名发行及provider停止费用都另有边界。

## 固定输入与继续条件

| 6a固定Git输入 | blob |
|---|---|
| Tinodios/Cache.swift | 4154c4e96fbcc7a7ee414d4191d44943f29fb1cf |
| Tinodios/ClawAssistantModels.swift | 893b4f016a7ff01f21cbb1104d4d9013ad2802f6 |
| Tinodios/ClawAssistantService.swift | 4757c5cf0c51ecff09dfae6d3b3b1ca7915231b1 |
| Tinodios/ClawAssistantSession.swift | de78d33069ac20c2363c0822a281dc40aa74891b |
| Tinodios/ClawAssistantHistory.swift | 9b11585f43d2555f9cd7f6b954a591dff69d00fd |
| Tinodios/ClawAssistantViewController.swift | 38996c22673ed297bca0ffc2c094e01f6a932646 |
| Tinodios/ClawAssistantConversationViewController.swift | 4d7e5f07c8250493f79b3916177e489996cb2054 |

下一步由总控冻结本地journal选择/留存清理、B细码/字段、最终测试接线及中文恢复动作，再实施。本报告只提交文档；原6d后继包、6a生产源、CI35/CI36失败及19782原未跟踪资料保持。另封5c91测试import不覆盖原失败，也不算B实现。没有“等待模型密钥才能继续”的新增阻塞，但未配置provider时真实生成仍不可用。
