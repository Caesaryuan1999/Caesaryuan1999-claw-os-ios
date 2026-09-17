# CI3-DB-DIAG：初始化失败诊断，非未经证实的修复

- 前置：8927c053a0360a767a13cdd87bb600c265fde9b9。1生产文件 BaseDb.swift +1原生测试文件。
- CI3 35277235637 / ae88055 的真实 xcresult 由 backend 只读取证：LocalMigrationTests.testTwoConcurrentInitializersCommitOnlyOneMarker，line430，available1/2，耗时0.2053499秒。两marker/status35=5断言未失败。原 initDb catch 丢失错误，activity/summary无法恢复原SQLite错误码；根因当前未知。
- SQLite.swift0.15.4 Connection 初始化没有隐式WAL修改，busyTimeout的单位为秒；现有两处5秒均在建立连接后、首个语句前。因此不把0.205秒失败归为超时耗尽，不加无证重试。
- BaseDb现在仅记录固定初始化阶段、固定错误类别、SQLite primary/extended 数值码。没有 Error.description/localizedDescription、SQL文本、路径、绑定值、账户或凭据进入诊断。上游仅primary码时extended=none，不伪造。
- 开库 catch 调用诊断后重抛同一错误。原validateSchema、SQL常量/完整schema、BEGIN DEFERRED与IMMEDIATE、两处5秒timeout、原不可用与保全规则均保留。没有新增重试/修复DDL/降级成功分支。
- 原并发==2断言保留，仅附两次初始化的安全诊断。新增2原生方法：真实openPreparedDatabase在受控writer锁保持时不暴露store、释放后完整完成；实际诊断formatter拒绝合成错误中的路径/SQL/secret，只输出阶段与数值。
- observeStage仅内部可见原生测试观测缝；正常app/NSE不传观察者。原生writer测试通过生产阶段信号确认抵达BEGIN IMMEDIATE前，再释放另一个writer，保留2marker/5unknown断言。
- Windows35/35源策略与SQLite适配器通过；额外直接源码比较确认SQL/schema门禁未变，diff --check通过。Swift未执行，不能称本诊断解决原并发失败。
- 累积原生期望127：SDK26 / DB51 / AUTH29 / Removal9 / PUBLIC12。下一次总控Mac CI需再次验证并发==2；失败则以本诊断精确定位。
- 官方源码依据：[Connection.swift 0.15.4](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Connection.swift) 与 [Result.swift 0.15.4](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Result.swift)。诊断未改变库错误处理语义。
