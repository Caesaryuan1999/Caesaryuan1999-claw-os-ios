# LOCAL-DELETE 只读提案

基于 4da8391b19ebe03d4a4ed7d4fb21ae428a89167e。尚未实施。
实际生产链仅 Tinode.finishAccountDeletion → Storage.deleteAccount → SqlStore.deleteAccount → BaseDb.deleteUid；直接 deleteUid 另有一个未知schema阻断测试。

## 可复现缺陷
Storage 的 deleteAccount 是 Void；SqlStore58–62吞结果。
BaseDb188–220在事务前清account指针，savepoint内子删除失败仅日志，仍release/return true。
TopicDb435–458消息先删、订阅失败即返回false；UserDb162–168与AccountDb116–122也吞SQL异常。
真实SQLite113合成A/B非空fixture，分别对subscriptions/users/accounts注入BEFORE DELETE RAISE(ABORT)，现调用顺序适配器3/3复现返回true+部分commit+A账号仍存在，B保留。见sqlite-red.json与reproduce_partial_delete.py。这是SQLite SQL/调用顺序证据，不是Windows执行Swift。

## 最小四生产文件建议
1. Tinode.swift: 新可选 AccountDeletionStorage:Storage 协议声明及专用错误，原 Storage void API不变。真实finish在精确200后调用可观察接口；true正常退休，false/unsupported仍立即退休但返回远端已注销、本机未完成的专用结果。没有再次发del请求。
2. SqlStore.swift: 实现新Bool接口，accountLock包裹；原void方法保留委托，固定失败日志。
3. BaseDb.swift: accessQueue中单immediate事务、参数绑定throwingSQL：按目标账号topic删除messages/subscriptions，然后topics/users/accounts。避免旧accessor把0行与失败混为false。查询目标账号不存在视为本地幂等成功；实际目标account删除必须一行。成功commit后才清对应内存account；失败回滚并保留原指针给既有logout去激活。若logout去激活也失败，既有block-store规则保留。无schema/状态/迁移改变。
4. SettingsSecurityVC: 捕获原Store；专用本地清理失败独立于远端拒绝处理。原owner退出/路由后仅在对应匿名logout世代展示明确错误，并提供仅调用原Store/UID本地清理的重试按钮，绝不重发远端注销。退出对话框不承诺重启自动清理。

## 测试建议
实际BaseDb/SqlStore原生fixture：子删除ABORT必须五表全量rollback、commit失败rollback、空子表可成功、重复本地清理、另一账号无变化、错误后注销隐藏保留数据。
SDK同生产finish+可观察Storage spy：true/false/unsupported及退休与固定错误；现精确ACK/旧owner七例保持。
页面实际调用共享世代门禁；UIKit系统展示与真机不由helper测试替代。
原生数量实施后按实际方法统计；当前候选169仅包含ACK七例，未包含此提案。
