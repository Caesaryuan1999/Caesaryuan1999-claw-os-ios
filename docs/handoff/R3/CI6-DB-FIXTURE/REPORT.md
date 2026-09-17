# CI6-DB-FIXTURE：真实绑定断言纠正与有界并发复现

本提交生产文件变化为0；只修改现有 TinodiosUITests/TinodiosUITests.swift、增加本报告/检查证据。父提交 f46c9f085528db4c99acc2d35f7f13e2fa1f3db8 含独立批准的群备注单元，不把UI改动混称数据库修复。

## CI6 的真实结果

精确4821062 / run35283743877：SDK26通过，storage105方法104通过、1失败；唯一失败为新诊断用例 line525 错误地要求 Statement 必非nil。原并发2/2本次通过，不能据单次通过关闭CI3/CI5的间歇初始化I/O错误；本轮没有取得新的 IOERR 扩展码。

## 为什么必须修正测试期待

[SQLite.swift 0.15.4 Connection.run](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Connection.swift)通过prepare().run执行，不是sqlite3_exec。其[Statement.step](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Statement.swift)调用connection.check(sqlite3_step(handle))未传statement:self；check默认statement:nil，实际 UNIQUE step 错误因此合法携带nil。

测试现在明确assertNil，同时仍检查原.error case、code19和捕获原code相等、原message在内存相等（XCTAssertTrue不输出文本）、可空statement同一性。nil===nil单独不当作完整异常保留证据。live2067、版本、memory枚举、不开扩展错误开关和过期live码拒绝归因等断言保持。

## 并发复现增强

同一个原生方法 testTwoConcurrentInitializersCommitOnlyOneMarker 内执行12轮，每轮调用原withFixture，创建独立UUID目录和非空旧113库；每轮两条并发实际BaseDb初始化，共24次初始化。

每轮必须独立满足available==2、marker==2、status35==5；失败消息只增加round编号与原安全数字诊断。失败后继续下一独立夹具是增加复现样本，不是对同一失败连接重试。没有改生产锁、timeout、事务、schema门禁或代码路径，也没有把测试串行化成两个顺序initializer。

## 验证与限制

Windows39/39 source policies、diff --check通过。新增轮数不增加原生方法数；下一累计候选期望135：SDK30（含4备注方法）+storage105。此提交还没有Mac执行，12轮不算12个新方法，不能报告24初始化已成功。

由总控保持既有失败日志、push准确候选并执行CI7；本端没有推送/触发CI。需要下一轮真实数值决定是否修生产实现，不能凭更改夹具断言或一次并发成功宣布迁移完成。
