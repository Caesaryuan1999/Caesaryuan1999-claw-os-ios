# R4-AI-CLIENT01 — iOS A 客户端候选

源码 `f3640f69171490c8278796e8026ae1fdb32058ed`，父 `d21d69fcd69ecc5946df2cad134bddef98a24a96`。仅九生产、两新测试、PBX/selector两接线，共13路径。源码已固定，Windows检查通过，新增Swift编译/19原生方法和页面截图尚未运行。交总控/独立审查后，仍由总控负责精确Mac候选与原验证分支；本端未push/dispatch。

总控固定源审随后提出两项必须后继修正：401非JSON/缺Content-Type当前被格式错误抢先覆盖；十进制字符串尚未限制PG Int64上界。本初版源码包保留可复查，不作为可发布最终候选；后继三路径修正及新增原生方法另提交/记录。

## 基线与保全

- 独占 `work/r3-20260918-ios`，分支 `codex/r3-20260918-ios`，origin `https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git`。
- A最初从 `4d7f5539e1cd225735b5a64f541d3a26e44180bd` 实施。中途按总控指示将CORE AX徽标缺陷独立封为 `bff92a46301891a0b67055611e3eb0a8c10dc6e5`；其docs父线d21是本补丁精确起点。CORE的2文件不混进本13路径，A的11个WIP文件在CORE提交前后逐一raw SHA保持。
- A提交前实测tracked dirty4、untracked19795（原19782保留，增量仅本批源/交接）。显式stage13文件，不全目录add、不reset/clean，不输出SharedUtils配置、runtime或真实凭据。
- 原CI34 c84实际248原生+3导航、打包/冷启通过；原图AX未读截断仍由CORE单元承担。CORE后继CI35归总控，本报告不提前引用其结果。A没有新Mac结果。

## 实现与冻结合同

唯一合同AI-A1-20260919 A；C3/AUTH-A1、SDK、普通消息、SQLite、媒体、通话没有改动。B服务端能力的附加JSON字段被安全忽略，即使generation/stream=true也不启用问答发送，显示本版本需要更新；当前无provider时按实际草稿存在与否显示“服务暂未开通”或“服务暂未开通，你的问题已保留”。

| 生产路径 | 实际作用 |
|---|---|
| `Tinodios/NewChatTabController.swift` | 消息/通讯录/助手/我四原生导航；既有消息、联系人、我页对象/入口保留；账号设置恢复选第四项 |
| `Tinodios/Cache.swift` | 实际已完成登录+Store UID+Keychain token匹配后登记首次scope；两invalidate分支同步摘除/标退休，出SDK/Cache锁再取消HTTP和通知；纯WS断连不自动废弃仍有效同token scope |
| `Tinodios/ClawAssistantModels.swift` | A严格DTO/十进制字符串比较/小写v4/UTC日期；未知role/state整详情不兼容；仅真实title/updated_at，不发明preview |
| `Tinodios/ClawAssistantService.swift` | GET能力/列表/详情，显式DELETE；没有POST API。独立唯一Authorization与APIKey、无媒体鉴权头、无query token；HTTPS/字面回环HTTP、禁所有重定向/cookie/cache；有限读取和取消 |
| `Tinodios/ClawAssistantSession.swift` | 捕获真实SDK对象、UID、Cache generation、origin、原opaque token；原Store UID/活跃会话/有效期/host前后核对。401只屏蔽助手，不普通logout或清库；不解析token epoch |
| `Tinodios/ClawAssistantHistory.swift` | 主线程状态；所有分页暂存，完整同revision才替换；409有限从头重拉；旧页面/旧账号回包失效；最小墓碑单向确认；DELETE未知与同ID显式重试；同账号内存草稿 |
| `Tinodios/ClawAssistantViewController.swift` | 原生助手首页/共享页面scope/删除确认/账号设置入口；开始提问仅打开未发送草稿，没有空会话创建 |
| `Tinodios/ClawAssistantHistoryViewController.swift` | 完整账号历史、真实标题/更新时间、AX自适应行；同步/已确认空/失败/鉴权失效分别显示；危险动作先确认且禁止全滑直接删除 |
| `Tinodios/ClawAssistantConversationViewController.swift` | 实际历史正文及partial/interrupted状态；本账号草稿、禁用发送；删除pending/unknown/确认/拒绝分别显示；退休清正文/草稿显示与原私有导航标题；原生安全区和键盘inset |

HTTP每请求20秒、resource30秒，单响应24MiB，可覆盖100×32000字节正文的最坏JSON转义约19.2MB加元数据；详情暂存工程上限64MiB，列表20000项、分页1000页；超限整批失败，不截断或静默跳页。这些是客户端内存/读取保护，不是用户套餐或服务配额。409最多额外重启两次；无自动写操作。

DELETE只有匹配ID的200 receipt或已认证owner权威410/墓碑清历史；超时/断连/5xx/坏receipt/205保持结果未知。随后active GET不证明原DELETE永不会提交；继续未知，可重新核对或确认后同ID重试。权威墓碑先到时会使迟到DELETE回包失效，旧GET/旧页也不能复活。404不当作已删除。关闭确认对话框不会撤销已发请求。草稿只在同UID/origin/generation的内存中保留，token更新可继承，退出清理；不承诺跨进程恢复。

## 设计与真实页面

已读取Figma同文件 `CreMqit00K1MAJju69YoOv` 的252:1269助手首页、251:1171四导航、276:1394历史、276:1371未开通、277:1424删除、287:1415未知结果、290:1416历史行，以及291:1426/1462/1500/1538同步/空/失败/鉴权失效。

保留UIKit/ClawTheme/UIFontMetrics、系统返回/单一导航标题，52pt以上动作，历史行76仅最小高度、40pt AI字样为装饰，标题17/更新时间13随AX增长；无假头像/未读/preview。Figma正文通过原UILabel/stack/table适配，不复制Web代码或固定390宽。首次空状态必须完整拉取成功；旧完整快照在刷新失败或分页变化时保留。鉴权恢复按钮“前往账号设置”只走现有我页和显式退出确认，没有新认证/客服流程。

## 测试与证据层级

Windows实际：原44源码策略PASS；`git diff --cached --check` PASS；`check_sources.py`固定13输入/原16Swift测试文件不变/仅新增两个selector；真实便携Ruby3.3.12 + Xcodeproj1.28.1解析PBX，7新源只属App、2测试只属既有TinodiosVoiceLayoutTests，未新建target或重复编译。`static-policies.json`、`source-checks.json`、`project-checks.json`分别记录，均不是Swift运行。

新增19个原生方法，完整名称在source-checks.json：

- AssistantHistoryTests 14：实际Service/Session/History与真实SDK对象、独立真实SQLite。URLProtocol只控制网络传输；覆盖TLS/头、redirect delegate、响应预算/大正文、首次scope鉴权与WS断连、token/host/Store UID/世代、草稿、完整分页+409、持续变化有界失败、未知state、精确十进制cursor、旧回包、旧401/当前401、DELETE未知/重放/迟GET/坏receipt/明确拒绝/墓碑及503零POST。
- AssistantLayoutTests 5：真实App四tab和UIKit页面、真实标题/时间/partial显示、320pt AX行、草稿返回、真实删除确认呈现和关闭、未知结果重核按钮、401隐藏。记录原UIKit PNG与安全几何JSON；禁用联系人系统依赖且恢复。HTTP/历史合成，不登录真实账号，不向模型/客服发送。
- Session测试替换的是Cache slot/generation注入边界，仍执行生产SDK/Store/Token/Session门禁；设置的认证状态是合成前提，不能称真实WS登录完成验证。Cache首scope Keychain完成条件由源审/编译接线核实，尚无真实登录联机证据。
- 删除弹窗验证呈现、cancel默认、destructive动作及未确认零DELETE；测试随后直接调用实际History提交，再操作真实核对按钮。未通过私有KVC触发UIAlertAction，不能称真人确认点击流程已通过。
- 迟回包通过真实注入gate的主线程消费信号等待，不固定sleep。没有复制生产状态机镜像。

现有248原生+3导航不删；累计计划SDK44 + storage223 = 267原生，导航仍3，全部新方法NOT_RUN。沿用现有storage.xcresult/原附件export，不增加workflow权限/超时。Windows没有Swift/Xcode，不能声称新增测试编译或通过，也不能把后端6097的48HTTP/SQL项算iOS联机。真实提供商、SSE、跨设备、设备推送/签名、客服受理仍OPEN。

## 安全恢复与回退

必须先有精确d21基线/其继承源（包括CORE bff），不能从空上游套补丁。`unit.patch`为Git原始binary/full-index差异，13路径、127050字节，SHA256 `9022e7eeced47ca4b7a43459346d0251e73c186182e1b44b0bffdd2d1e837fe6`。manifest记录目标mode/blob及Git字节SHA；source-checks中的raw SHA则准确表示工作树字节，不混同CRLF clean-filter。

`package_unit.py`在独立临时index先read-tree d21，实际`git apply --cached --check`再`git apply --cached`，核全树mode/blob等于f364的tree `0ead04002dca1ee7b5442cd398ff79f6f15df3a9`，原index摘要不变。只导出13个白名单源文件并逐文件Git字节SHA核对；未读取/物化其他私有源，不含配置/签名/推送/Pods/build/runtime或巨量附件。具体前后条目数和临时目录在forward-checks.json。

供已有基线的独立副本复验：先`git apply --check <绝对unit.patch>`，再`git apply <绝对unit.patch>`；逐路径比较manifest（Windowsraw行尾与Git clean blob分开）。不直接覆盖有WIP的旧树。需要回退时先确认这13路径没有后续改动，在独立副本`git apply -R --check`后反向应用本补丁；不reset/clean，不重封旧09631/e30/6c0等包。没有DB/wire迁移。新模拟器App应待总控精确候选CI产物；本包不含安装包或iPhone IPA。
