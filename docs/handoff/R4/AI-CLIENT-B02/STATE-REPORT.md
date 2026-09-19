# R4-AI-CLIENT-B02 状态与服务批

起点 `2e758cfc76e01f99a9a5fef7effd7f7c5f13eeff`，独占分支 `codex/r3-20260918-ios`。本批仅五生产文件、新 `AssistantKnownRunTests.swift`、原 PBX membership、原 selector 追加，共八代码路径。三个 UIKit 页面仍在下一独立批接线；本批不宣称页面功能已开放。

## 实际变化

- B 独立 message/page 与显式 `limit=10`。user 上限 32000、assistant 上限 262144 UTF-8 字节；A 原类型/limit20 保留。完整分页同 revision 提交、最多两次 snapshot_changed 重启，坏页保留完整旧快照。
- Session 持有唯一已知 run，Run 弱回持 Session。known-only 的三个生成入口在通知/联网前拒绝；generation=true 也不产生新会话或新 run POST。
- 当前完整历史选最后真实非空 rid。qid 必须对应同 cid 的 user 且早于 aid；aid 必须对应同 cid/rid assistant。retry_of 旧问题的 run_id 不强求等于新 rid。缺行只补查一次；不制造回答行。
- 历史账号全局 revision 与 run 自身 revision 分离。旧 terminal run 不覆盖较新完整历史；合法新投影只替换匹配的既有回答行。terminal 对齐最多一次，不重复追加前缀。
- UUID 页面读取租约独立于 Session。旧页面 release 不关闭新 reader；离页只关读，不发 stop。stop pending/unknown 保留，跨 cid 在改变 selection 前拒绝。新历史快照遇到旧 stop 未决不消费 token，终态后再绑定最新 rid。
- 能力降到 A/不可用时暂停 reader 与后续 stop，不清除未知停止；手动恢复重新协商，并将确认的能力回写同 scope 的 History。401 只封原 scope，不 logout/清库。删除墓碑先提交，再在 SDK/Cache/scope 锁外单向清 run；其他 cid 墓碑不动当前内容。

## 验证和准确层级

原生新增 12 方法，实际使用原 internal `AssistantFixture`（真实 SDK、隔离 SQLite、实际 URLSession/URLProtocol）与 `AssistantBFixture`。没有借用 private bare/TCP helper，也没有修改旧测试文件。覆盖字节边界/最大转义页、分页失败保旧、known-only、真实指针、全局 revision、租约、停止未知/晚回包、删除、401/同步退休、前缀恢复及能力降级。

Windows：44 项既有源策略通过；允许路径、原 Swift 文件、单 selector、PBX membership、方法数量与原始 SHA 由 `check-state-source.py` 验证。它们不是 Swift 编译或原生运行结果。12 新方法尚未在 Mac 执行，预期累计 307 native + 原 3 navigation；不把预期写成通过。

CI43 固定 2e758c 的两次尝试均在官方 MobileVLCKit 下载失败，原生未启动。总控保留原件并处理依赖；本窗口未改 Pod/锁/CI 工作流，未推送/派发 CI。

## 后继与回退

下一批仅冻结的三个 UIKit 文件及新布局测试：真实页面 lease、known-run 状态/恢复/停止、跨 cid 提示、messageID 行复用和阅读锚点。生成、重新生成、客服提交、跨进程 journal 均保持未开放；不改 DB/wire/Keychain/账号流程。

审查和 Mac 准入前不安装/发布此中间状态批。若需撤销，以本批显式代码路径的逆向补丁/独立 Git revert 恢复到固定起点；保留旧包、未跟踪资料和私有配置，禁止 reset/clean。后续安全补丁在固定提交后单独生成，不将文档 HEAD 冒充 CI 来源。
