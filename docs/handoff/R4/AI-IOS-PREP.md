# R4-AI-IOS-PREP — A 批客户端准备（只读）

状态：方案待总控冻结实施；本报告没有实现助手，也没有触发 CI。日期：2026-09-19。

## 固定来源和本轮边界

- 独占树：`work/r3-20260918-ios`；分支 `codex/r3-20260918-ios`。
- 读取起点 HEAD：`9905a45d51f8fc4204c3591df2bb7132487ac57f`（UI-CORE01 文档提交）。
- 当前代码候选：`c84ab98db11685a656dfe483cd1db59c055fd81e`；其中生产改动封于 `a2db7d1f1413370b67f7140f1189da068a60b21e`，c84 只修真实我页测试的 AX 增长/末端可达要求。
- 本轮开始 tracked dirty=0；19782 个既有未跟踪文件保留。仅新增本文件。
- 根已派发 CI34 `35389096537 / 105742997819` 验证 c84；本报告按待收结果记录，不将旧 CI33 的结果扩展至 R4。
- 唯一业务依据：根 `docs/context/PROTOCOL_CONTRACT.md:275–310` 的 AI-A1-20260919 A；参考 `R4_AI_HISTORY01_TASK_PACK.md`、ACTIVE_CONTEXT、WORKSTREAMS 当前段。根共享文件中的旧准备时间点不替代最新冻结。
- C3/AUTH、Tinode SDK、SQLite/schema、现有上传/通知/客服均不在拟改范围。AI 历史属于服务器独立存储；客户端不依赖 PG 表结构。

## 已确认的真实入口与身份事实

| 固定源码定位 | 当前事实 | A 批接线约束 |
|---|---|---|
| `Tinodios/NewChatTabController.swift:11–78` | `ClawMainTabBarController` 在此文件，make 创建消息导航、Find 导航、我导航；消息索引 0、通讯录 1，未读 badge 只用首项 | 增加助手为索引 2，我移至 3；保留原消息/通讯录索引及命名导航引用，不重建聊天入口 |
| `Tinodios/UiUtils.swift:338–388` | logout 绑定原 owner；登录路由按 Cache generation；消息路由依赖命名的 messagesNavigationController | 助手不能绕过原登录完成/账号切换路径；不根据新增 tab 索引改消息路由 |
| `Tinodios/ClawIdentityFlow.swift:82–100,331–360` | flow 有失效代次；主线程消费前复查；HTTP UID 与 WS UID 一致且 commitSession 成功后才返回登录成功 | 不把 AUTH HTTP 返回 token 或 AI capabilities 成功当作既有登录流程已完成 |
| `Tinodios/Utils.swift:1249–1305` | identity coordinator 捕获 owner/host/TLS，token 经 loginToken，复验 authenticated/UID 后持久登录；旧号另走原 basic 入口 | 新 AI scope 复用已完成的会话门禁，不改新旧身份请求、密码或旧登录兼容语义 |
| `Tinodios/LoginViewController.swift:148–165` | 切 host 失效原 coordinator；成功回调才按原 owner 跳消息 | 新页面不会另存一套登录凭据，不从旧回调取后来 Cache.tinode |
| `Tinodios/Cache.swift:28–47,61–93` | 锁顺序 SDK session→Cache；ifCurrent 同时检查 active SDK 与 slot identity；invalidate 退休、清凭据并递增 generation | 助手 scope 必须绑定同 owner/UID/generation，并补最小同步失效登记；网络取消/界面通知必须出锁 |
| `Tinodios/Cache.swift:159–181` | connectAndLogin 的网络失败分支可因保留本地账号和 Keychain token 返回 true | 这个 Bool 不能单独当“刚完成 WS 鉴权”证据；首次 AI scope 须另核实际 authenticated/token/UID |
| `TinodeSDK/Tinode.swift:445–480,1138–1177,1214–1240` | token 为不透明字符串；SDK logout 退休实例；客户端没有公开的数值认证 epoch | 不解码 token，不伪造 epoch=0，不把 Cache generation 当服务器 epoch；epoch 的有效性由 A 服务验证 |
| `TinodeSDK/Tinode.swift:657–692` | addAuthQueryParams 把凭据放 URL；getRequestHeaders 使用 X-Tinode-Auth | 两者都不能用于 AI。AI 独立构造唯一 Authorization: token 头和 X-Tinode-APIKey |
| `Tinodios/ClawIdentityService.swift:170–197,235–266` | 现服务固定 /v0/auth；已有 HTTPS/回环校验、拒重定向和无 cookie/cache 模式，方法/大小限制属于 AUTH | 复用设计原则，不将该 AUTH 对象或其 body/响应限制冒充通用 AI transport |

上述 SDK/身份文件仅作为只读依据。未读取 SharedUtils 私有配置内容，也没有输出 token/API key。

## Figma 已取得真实 design_context

同一文件 `CreMqit00K1MAJju69YoOv`，使用已读的 figma-design-to-code / figma-use 工作流，保留 UIKit 和 ClawTheme，不引入 React/SwiftUI：

| 节点 | 读取结果与实现取舍 |
|---|---|
| [252:1269 助手入口](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=252-1269) | 标题、提示、开始提问、历史入口；样例不是历史消息。generation=false 时不显示可用生成承诺，开始提问最多进入本地草稿界面，不创建空服务器会话 |
| [251:1171 四导航](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=251-1171) | 消息/通讯录/助手/我；AI 是识别字样不是新品牌。沿原生 UITabBar 安全区，不用网页固定底栏 |
| [276:1394 历史](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=276-1394) | 当前账号历史；图中存在摘要样例，但 A 没有 preview，实际仅 title、updated_at；空 title 显示“新对话”，不能逐行额外拉消息伪造摘要 |
| [276:1371 暂不可用及草稿](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=276-1371) | 保留实际输入，禁用生成；仅实际存在草稿时说明保留，没有草稿不能声称“你的问题已保留” |
| [277:1424 删除确认](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=277-1424) | 按账号整段对话、同步范围、不可撤销，二次确认；不冒充普通 Tinode 聊天删除 |
| [287:1415 删除结果未确认](https://www.figma.com/design/CreMqit00K1MAJju69YoOv?node-id=287-1415) | 重新核对/稍后处理；重查原 ID 的权威历史，不重新生成答案，关闭提示不等于撤回 DELETE |

R4.D1 青绿浅/深、系统字体和 UIFontMetrics、正文自然增长、原生导航、52pt 主要内容动作。原生 tab/nav 的平台触区及 AX 布局由真实 UIKit 测量，不套固定画布高度。示例题只可作为明确的输入建议，不能变成已发送用户提问、已保存历史或模型回答。

## 建议生产边界：9 个文件

下面是待批准的精确名单，不是已经写入的文件。

| # | 仓库相对路径 | 最小责任 |
|---|---|---|
| 1 | `Tinodios/NewChatTabController.swift` | 第四 tab 和助手导航栈；原消息/通讯录入口、badge 和我页真实内容保持 |
| 2 | `Tinodios/ClawAssistantModels.swift`（新） | A DTO：活记录/最小墓碑、历史消息、capabilities、错误；UUID/十进制字符串/RFC3339 验证，不发明 B 的状态枚举或 wire |
| 3 | `Tinodios/ClawAssistantService.swift`（新） | 独立同源 /v0/ai HTTP、正确认证头、拒全部重定向、无 cookie/cache、取消任务、真实响应/错误分类 |
| 4 | `Tinodios/ClawAssistantSession.swift`（新） | 捕获账号/owner/Cache 代次/服务 origin/token，任务登记与退休、页面请求代次；在 UI 消费处复验，提供生产共用门禁 |
| 5 | `Tinodios/ClawAssistantHistory.swift`（新） | 当前账号的完整分页暂存/替换、snapshot_changed 重新读取、消息分页、删除确认/未知/核对状态；只内存，不新建 SQLite 表 |
| 6 | `Tinodios/ClawAssistantViewController.swift`（新） | 助手入口、真实 capabilities、不可用恢复和账号内本页草稿、历史入口 |
| 7 | `Tinodios/ClawAssistantHistoryViewController.swift`（新） | 真实 title+updated_at 列表；加载、空、旧快照待更新、错误、墓碑及整会话删除入口 |
| 8 | `Tinodios/ClawAssistantConversationViewController.swift`（新） | 真实服务历史详情、草稿/503反馈、二次删除和未知核对；没有流式接收、停止、假答案 |
| 9 | `Tinodios/Cache.swift` | 仅登记/摘除助手 scope 并在原 invalidate 两分支同步标记退休；出锁取消任务和通知隐藏。保留现锁序、Recorder/上传/凭据逻辑，不重写 Cache |

可分为 transport+scope、历史状态机、四导航+真实页面三个可审提交，但必须合起来验证身份门禁。若实施发现必需修改 SDK/Identity/DB、AppDelegate 或其它生产路径，先回总控列新依赖，不暗中超过九文件。

## 请求与账号生命周期

1. 只在既有登录完成后，Cache.ifCurrent 原 owner 内原子捕获 UID、Cache generation、服务 origin、API key、当前非空 token/有效期。请求不带客户端 owner；服务端从 token 确定 owner。
2. 每个 HTTP 操作用不可变 scope 和操作代次。任务登记/退休使用同一状态门禁；不得在 callback 临时读取新的 Cache.tinode 或拼新的 token。后台网络完成后，上主线程再复查原 owner、UID、代次、origin/token 和页面操作代次，之后才写本账号状态或重绘。
3. 切 host、退出、换号先同步标记旧 scope 不可消费/清可见内容；网络 cancel、UI 回调均在 SDK/Cache 锁外。按 SDK→Cache→scope 锁序，scope 不反向取 Cache。不能在锁内等待主线程、HTTP 或 getResult。
4. 普通 WS 断开不等于退出。已取得并仍属于同 owner 的有效 token 可以继续 A HTTP；不能因为暂时断开清掉该账号草稿。冷启动若只有保留的本地账号而 SDK 尚无可信 token/登录完成状态，建议沿原连接登录恢复后再建立 scope，期间明确可恢复；不能把 connectAndLogin 的离线 true 分支当 fresh login。这个保守启动行为须写入下一实施包。
5. token 更新后旧请求不能取得新 token 续命。旧 token 的晚 401 不得清新 token 或 B 账号；只有仍为同一当前 scope 才进入本账号鉴权失效处理。401 先隐藏旧内容，再按原 owner 退出/重新登录；403 显示权限不足，不能自行推断账户已删除。
6. HTTP capability 检查不建立登录、不替代 AUTH 的 HTTP/WS UID 一致门禁；AI 不存在无 AUTH 服务时的旧 basic fallback。服务器认证 epoch 不向客户端暴露，本地代次只防旧回包，不代表服务端授权。
7. 页面离开废弃页面渲染票据，不能把已经发出的 DELETE 当作撤销。原 scope 退休时取消/隐藏，已入网请求可能完成，因此清理 UI 不是服务器回滚保证。

HTTP 层沿实际 origin 和非回环 HTTPS 门禁，不接受 credential URL、外源跳转、cookie 或 query 认证。唯一 Authorization 值来自原 token 字节，不打印头/URL 凭据/正文；错误只用稳定 code。limit 默认20、最大100；请求 body 按64KiB、文字按 UTF-8 32000bytes。不要把 AUTH 的小 body 或响应上限直接套到一页合法 AI 历史；响应预算须按冻结字段及 page limit 独立有界，并测试边界。整数全程十进制字符串，不能转 Double，也不使用 Tinode seq 或 updated_at 作游标。

## 权威历史与 snapshot_changed

- 新请求先保存当前已完整显示的列表为旧快照；新页只进隔离 staging，带原 scope+读取操作代次。
- 第一页不带 cursor/revision；下一页只用响应 next_cursor 及同一 snapshot_revision。列表 cursor/next_cursor 是上一页末项 conversation 的小写 UUIDv4，不是十进制数；after_seq/next_after_seq/revision/snapshot_revision 才按十进制字符串校验。校验合法/不重复 ID、游标前进、单页字段、scope 未失效；没有完整末页前不合并进原列表。
- 409 snapshot_changed：丢弃这一轮 staging，原列表不动，从第一页重新获取。建议最多两轮自动重启，持续变动则显示“历史已变化，请重新加载”，用户可再试；不无限重试、不按已有 cursor 跳过中间项。自动次数属客户端恢复建议，不是新增 wire。
- 只有完整、同 revision 的全集成功才一次替换当前账号列表，并处理该账号墓碑。部分页错误、401、晚回包均不能写入 B 的列表或删除旧账号之外数据。
- 列表保持服务端不可复用 ID 的分页顺序；若将来展示按 updated_at 排序，只能在完整快照内排序，不用显示末项充当下一页 cursor。
- 详情同理：after_seq 与 next_after_seq 是服务器十进制字符串；每轮所有消息共用 snapshot revision。跨设备变动导致409时重新拉，不用“相同正文”去重、不自动启动 run。
- 暂无本地 AI 数据库；完整服务器历史支持跨设备同步由真实 A 服务提供。应用重开重新鉴权拉全快照，不把本机内存缓存称为跨重启离线历史。

## 删除语义与结果未知

- 对真实 conversation_id 二次确认；请求不带 body/query。确认 ticket 固定原 scope/ID/操作代次，禁止全滑直接删除。
- 只有匹配原 ID 的有效200、deleted=true、有效 revision 才确认本次完成；不是任意2xx/缺字段成功。随后刷新完整列表，不把单条 DELETE 响应当账号全集。
- 超时、断连、提交后取消、无法确认的5xx/畸形响应均进入“删除结果暂未确认”。原行可保留为待核对占位，但必须标注非权威，不承诺内容仍保留或删除失败。
- “重新核对”只读原 owner 的完整权威历史/墓碑，或同会话只对 owner 返回的410；不创建新会话、不发送提问。得到原ID墓碑/所属会话410可确认已删除。
- 查到 active 只能说明该次快照仍存在：旧 DELETE 可能尚在途，不能承诺之后绝不提交。保持未确认并允许再核对；若提供显式再次删除，只能同 ID 幂等请求，仍按同样确认规则，不悄悄重放。
- 404 同时代表未知/非 owner，不能单凭404虚构“已删除”；鉴权失效先隐藏，不能跨账号继续核对。无关成功响应、旧操作的晚响应不得清新的列表。
- 删除界面说明账号内整段和其他设备恢复同步后的变化，不承诺离线设备瞬时清除、第三方/系统副本擦除。没有跨重启 pending journal 的本批不承诺恢复原操作过程；重开按账号权威快照恢复现状。

## 暂无模型时的可用功能和草稿

- 能力可用性分成 history / generation / stream，不把 history可用渲染成模型已可用。A 当前 generation=false、stream=false；网络 GET 失败显示连接/重试语境，不显示“发送结果未知”。
- 历史可用即可查看真实已有历史/整段删除；history不可用给可恢复说明，不用示例填空态。
- 本地草稿可编辑、保留当前账号当前页面的实际文本；不开自动建空会话。已知 generation=false 时发送入口禁用并解释未开通，不构造待发送消息泡泡。
- 若已发出的受控 A runs 请求返回503 provider_not_configured（例如状态切换/服务端最终拒绝），逐字保留原草稿，不显示已发、正在回答或202。没有 draft 时不声称保留；字数超限是本地输入反馈，不改用户内容以求提交。
- A 的 POST conversations 仅低层显式元数据接口；本轮普通入口不主动调用以铺设“伪新对话”。runs 不做自动重试；超时语义不借尚未冻结的 B 幂等恢复协议猜测。
- 草稿内存按 origin+UID 绑定，退出隐藏并释放旧 scope；不进 UserDefaults/日志。跨重启草稿持久化不在这九文件方案中，若产品需要另列存储/保护/删除决定，不能暗中承诺。
- 不实现 SSE、stop、自动重生成、模型选择、联网或工具，不读其他通讯内容。客服仍保持已存在的帮助内容；没有人工接收通道/资料上线证据，不能把“留言提交”做成本地成功提示。

## 原生验证方案（待实现后确定方法数）

保留现 UI-CORE01 候选的248原生+3导航全部选择与断言；它们尚待CI34结果，不是本轮已验。新增测试建议：

- `TinodiosUITests/AssistantHistoryTests.swift`：实际生产 Service/History/Session。URLProtocol/受控 HTTP 响应验证真实 URLRequest 头、禁止重定向、no-store、非法源/错误响应、合法最大分页/UTF8、十进制精度；不是实际服务联机验收。
- 同文件覆盖真实状态机：多页中间 snapshot_changed、增删造成 revision变化、部分失败保留旧列表、墓碑、空 title、晚A回包到B、token换新后旧401、重复回调/页面代次、DELETE200/410/404/timeout/5xx/再次active/后续墓碑、503草稿逐字保留。
- 账号用 actual Tinode 与现有 SQLite 合成夹具/生产共用 gate；无法在纯 unit 链接完整 Cache 的部分放 App-hosted，不用手写 Boolean 模型替代实际消费门禁。
- `TinodiosUITests/AssistantLayoutTests.swift`：现 App-hosted 真四 tab 与真 VC、320pt/AX/浅深色/键盘/安全区、消息/通讯录既有索引与 badge 路由、真实列表无preview、二次确认/取消/未知恢复、换号后旧页面不可显示。数据只用合成 fixtures，不造生产答案。
- 必要成员接线为 `Tinodios.xcodeproj/project.pbxproj` 和原 `Scripts/ci/verify_publish_outcomes_macos.sh` selector；不新增 workflow、Pod 或依赖版本。准确新增方法数量待代码可审时统计，不预设数字凑覆盖。
- 后续根控制 Mac 编译、真实模拟器截图与必要服务回环联调。Mac runner不能访问本机6097；Windows静态、合成transport、原生UIKit和真实部署各自记证据，不相互替代。

## 实施前依赖及关闭标准

1. 总控冻结以上九文件与最小 Cache 退休挂钩，特别冷启动恢复和本页内存草稿边界。
2. 后端 A 候选的真实 capability/分页/错误/删除证据及安全连接资源由总控提供；当前未以服务已ready为前提，不碰旧6095/118。
3. 历史行无preview、删除未知核对及generationfalse必须按契约，不照搬图中样例数据或B行为。
4. 代码独立审、原native回归、新真实消费者/账号竞态/分页测试和原生UI证据完成后，才能声明A客户端落地；没有模型时只能声明历史/删除/不可用与草稿处理已验。
5. CI34若报真实失败优先修原候选，本方案不提前动生产；root负责新授权、公共资料及远端执行。

本轮结束状态：仅准备文档；无源码、测试、CI、协议、数据库或交付包变更，无push/dispatch。旧 CI33 包、R4 UI红/绿静态证据及当前 c84候选原样保留。
