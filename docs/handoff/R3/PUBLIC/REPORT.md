# R3 PUBLIC — 公开 CLAW 号提取

起点：b0565267689414f5642c7b8274062501196c57d2。只变更 2 个生产文件：TinodiosDB/UserDb.swift、Tinodios/Utils.swift；另追加既有 TinodiosUITests.swift 中 4 个 LocalMigrationTests 方法。不改 schema、SDK、身份 API、发送状态与私有配置。

根因：FndSubscription.private 的 alias 标签可供目录返回，但 UserDb.insert(sub:) 及界面 fromTags 只识别 basic；新注册账号无公开 basic tag，首次持久化因此丢失 CLAW 号。现在 UI 与 DB 共用 UserDb.publicAccountName：先查有效非空 alias，再保留历史 basic 规则，不依赖标签顺序；使用既有 SDK alias 格式检查，不按内部用户名的前缀猜测、不从 UID、手机号、邮箱、认证用户名补值。联系人显示允许 alias 中的下划线，旧 basic 查询语义不改。

真实 DB 原生用例已准备：使用现有合成非空 113 fixture，经生产 BaseDb/UserDb 实际首次 insert、重开读取、历史 basic 回退、无公开标签保持 NULL、匿名读取阻断、同联系人 UID 的 A/B 账号隔离。没有修改原 71 个 R2 用例或旧断言。现有 workflow -only-testing:TinodiosUITests/LocalMigrationTests 会自动收录新增 4 方法。

Windows 实际：34/34 源码策略及脚本通过；git diff --check 通过。这些不等于 Swift 编译或 SQLite.swift 执行。本批新 4 个 XCTest 在 Windows NOT_RUN；累计预期原生方法 110 = SDK 26 + DB 49 + 身份 26 + 删除意图 9，待总控最终 Mac CI。CI2 的已封存 b056 仍预期 106，不把本批算进其结果。

兼容：现有 account_name 列不变、不批量重写旧联系人；新目录插入或后续同步按真实公开标签补齐。无 alias/basic 时界面显示未设置，不暴露内部身份。Figma 中示例人名和号码不写入运行时数据。更换手机号/邮箱仍遵循 AUTH4 只读门禁。
