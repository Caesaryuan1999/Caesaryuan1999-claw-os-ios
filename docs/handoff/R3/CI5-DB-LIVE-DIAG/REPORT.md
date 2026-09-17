# CI5-DB-LIVE-DIAG：初始化失败的 live SQLite 数值诊断

本单元仅补可用于下一次真实 CI 定位的数值证据，没有修复或绕过并发初始化失败。基线源码 f3043d923aa0f0c996b6a2967a9d2c33acefb435；其累计包另由 docs-only 4cb9f496b2a458bb813c4d5e6c1d787dc18c88ae 封存。

## CI5 已确认事实

- run35282019867 / job105405880687：SDK 26/26 PASS；storage 104 方法中 103 PASS、1 FAIL、0 skip。
- AUTH 29、Removal 9、PUBLIC 13、Publish 4 全过；LocalMigration 49 中 48 过。
- 唯一失败 testTwoConcurrentInitializersCommitOnlyOneMarker，line432，available 1 != 2。诊断 migrationBegin:sqlite:primary=10:extended=none，0.79309797 秒。随后 markers=2/status35=5 断言没有失败。
- 原始 zip SHA-256：5da1972f8c3663343e1869ef50e97f063fc90e6e789b852244548d9300956fb7，由总控保管。storage.log 无另一个 OS/VFS 错误输出。
- primary 10 是 I/O 错误，不是 BUSY 5；只读句柄关闭交错等仍是待验证假设，不能以此断言根因。测试门禁失败，未打包、未冷启动。

## 最小修改范围

1 个生产文件 TinodiosDB/BaseDb.swift，1 个原生测试文件 TinodiosUITests/TinodiosUITests.swift；另 1 个 source policy 与本报告/证据。

- 在 RO 和 RW 连接既有作用域内，用同一个仅 catch 的 helper 包裹原操作；成功顺序、超时、连接标志、事务和返回值保留。
- 失败时先复制 sqlite3_extended_errcode(handle) 和 sqlite3_system_errno(handle)，再读取 sqlite3_libversion_number()。仅 live 扩展主码匹配原异常主码才关联 errno/扩展码；不匹配标 mismatched，不把该 live 码作为根因。
- 已复制数字后，才尽力读取不带赋值的 PRAGMA main.journal_mode。结果只允许 delete/truncate/persist/memory/wal/off/unknown；读取失败用 unknown，不替换原错误。
- 不启用 usesExtendedErrorCodes，不改变后续业务对 .error 的匹配。原捕获 error 原样 throw。没有 SQL/path/account/bindings/exception 文本输出。
- 连接构造自身失败时没有可安全使用的 live 句柄，仍走原安全 stage/category/primary 诊断。rollback 已覆盖错误时会显示 live=mismatched；不宣称恢复了已经丢失的错误。
- source-evidence.json 比较确认 prepareDatabase 至文件尾（迁移、schemaRows、validateSchema）完全不变，SQL 常量不变。并发 2/2、两 marker、旧状态隔离断言原样保留，没有串行化测试或增加重试。

## 验证层级

- Windows 38/38 source policies PASS，diff --check 通过；这不是 Swift 执行证据。
- 新增 1 个真实原生 SQLite 方法 testLiveInitializationDiagnosticPreservesOriginalSQLiteError：制造 UNIQUE 约束失败，通过同生产 helper 捕获 live 扩展 2067，验证仍抛原 .error 19 和同一 Statement；数字版本、memory 固定 journal、不泄漏合成绑定值、扩展开关未改变；后续 live 码被覆盖时拒绝关联。
- 下一候选预期原生 131：SDK26、LocalMigration50、Publish4、AUTH29、Removal9、PUBLIC13。现有 workflow 已选择整个 LocalMigrationTests 类，无需改 selector。此新增方法在 Windows 未运行；实际 CI6 结果由总控回填。
- 不伪造 IOERR，不用 UNIQUE 结果声称根因已定位；此测试验证真实 API 捕获与原异常保持。

## API 依据

SQLite.swift 0.15.4 的 [Connection](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Connection.swift) 默认 usesExtendedErrorCodes=false，transaction 在进入 block 前执行 BEGIN；[Result](https://github.com/stephencelis/SQLite.swift/blob/0.15.4/Sources/SQLite/Core/Result.swift) 在开关关闭时只构造 primary case。故 CI5 extended=none 不能证明底层没有扩展码。

SQLite 官方说明 [extended_errcode](https://sqlite.org/c3ref/errcode.html) 不依赖扩展开关，后续 SQLite 调用可能改错误码；[system_errno](https://sqlite.org/c3ref/system_errno.html) 返回系统相关的数值错误号；[libversion_number](https://sqlite.org/c3ref/libversion.html) 为运行库版本；[journal_mode](https://sqlite.org/pragma.html#pragma_journal_mode) 无赋值形式用于读取模式。只读 journal 在错误数字已复制之后执行，不作为改变 journal 的手段。
