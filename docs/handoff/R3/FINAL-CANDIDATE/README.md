# CLAW OS iOS R3 累计可审查候选

源码基线：34a8b3e5ad4df210117e2e03b308576796ba55b2
源码候选：f3043d923aa0f0c996b6a2967a9d2c33acefb435
源码封存时 dirty=0；本目录随后生成的是交接产物，不改变该源码候选。

## 正式源码补丁
- CLAW-IOS-R3-source-test-ci.patch：55文件，44修改、11新增；Git原生diff --binary --full-index --no-renames生成，保留新增文件mode与原始Git字节。
- SHA-256：27045cbce487250932bf91ad0219cd0a2bc7d2c5912e0deaced76218f59d261a
- 仅源码、测试、工程、Podfile及CI白名单。排除SharedUtils私有配置、服务配置、凭据、runtime、pycache、docs报告和本交接产物；未复制它们到验证目录。
- file-manifest.json逐文件记录基线/目标Git字节/实际应用后SHA-256、Git blob OID与mode，同时单列Windows工作文件字节SHA。Git LF与Windows CRLF可能不同，不混称同一字节。
- 本地真实验证：只重建涉及的安全基线文件和Git index，先git apply --check --index，再实际git apply --index，55/55内容、Git mode、blob OID与候选一致。临时副本已清理，原始和旧交付树未动。
- 初次临时index未刷新stat导致预检查失败，修正夹具setup后成功；补丁字节未变化。失败说明apply-setup-first-attempt.json保留。

在本候选工作树复现验证（只写本目录下短期安全副本，不在当前树应用补丁）：

~~~powershell
rtk python -X utf8 -B docs/handoff/R3/FINAL-CANDIDATE/verify_forward_apply.py
~~~

若在另一个授权的干净基线副本正式应用，应先确认其HEAD等于上述基线，随后使用：

~~~powershell
rtk git apply --check --index <补丁绝对路径>
rtk git apply --index <补丁绝对路径>
~~~

此处命令不授权覆盖原工作树或私有配置。完整Git基线副本需保留自身配置；测试重建只复制55个安全文件。本补丁不是签名IPA，也不包含上线资源。

## 分批提交索引
完整26项、精确SHA和标题见commits.tsv，顺序如下：

| 批次 | 提交 |
| --- | --- |
| UI01主题/主导航，UI02聊天输入 | 7a0966a / 12c9245 |
| AUTH1及旧AUTH端点兼容 | d077e02 / 7f0b8a4 |
| AUTH3改密退休、AUTH4身份只读 | f93235f / 9f591cc |
| UX会话删除/退出群/解散确认 | 8712f7b |
| 许可原始文字保全/XML修复及空白 | df372b1 / b056526 |
| PUBLIC1别名持久化/显示，AUTH编译 | 62ce847 / ae88055 |
| UI03联系人/我/资料、解散文案、身份未获取状态 | adf55d1 / ff6487e / 4681442 |
| 原账号独立旧SDK传输 | 69e2b80 |
| 免签模拟器冷启动证据/脚本说明 | 34da10e / e67e68f |
| AUTH测试前置纠正（不放开禁用cap） | 557d900 |
| PUBLIC02精确查询、世代/账号结果门禁 | 8927c05 |
| 数据库初始化安全诊断（无重试修复） | fd7d0c5 |
| PUBLIC旧basic长度、退出原owner、离线联系人 | 61fd4ae / 80d17a0 / a02c61c |
| 入站固定日志、正式searchTextField API、固定失败日志 | 1be51a5 / 3f3d438 / f3043d9 |

## 验证与未决
- 最终源策略：37/37，见static-policies.json。Windows没有Swift/Xcode执行证明。
- 最终原生130：SDK26、DB53、AUTH29、删除动作9、PUBLIC13。CI5精确f3043d9（run35282019867/job105405880687）已运行：SDK26/26通过，storage104项中103通过、1失败、0跳过；AUTH29、删除动作9、PUBLIC13、Publish4全通过。失败仅LocalMigration并发初始化：line432 available1!=2，migrationBegin主码10（SQLITE_IOERR）、extended=none，0.793秒。测试未全过，打包和冷启动未执行；不能交付已验模拟器App。
- R3CI1在许可XML阶段失败，Swift未执行；CI2许可修复通过后缺creds参数编译失败；CI3/ae88055 SDK26通过，storage82通过、2方法失败、1runner错误。AUTH失败的错误前置已在557d900改测试，生产禁用能力没有放宽。
- CI4/run35280802910/fd7d0c SDK26通过，storage/App在UISearchBar.textField编译失败；DB诊断和冷启动没有运行，不能算新的数据库失败。3f3d438修正确实存在且部署目标支持的API，CI5编译通过。
- 原并发初始化CI3在0.205秒只成功1/2，CI5再次复现并确认BEGIN阶段I/O主码10；更细OS/VFS根因仍未确定。fd7d0c只增加固定阶段/错误类别/数值码，不增加重试、不放宽schema或两个initializer均成功的断言。该问题不能标为已解决。
- 消息C3/SQLite迁移语义保持R2基线；BaseDb生产变化仅诊断。另有已批准的UserDb公开号首次alias提取，不改schema/账号范围。UI、HTTP身份、公开目录及退出调用者变更分别报告。
- 无真iPhone、正式签名、APNs/FCM设备、真实OTP服务或用户旧库升级验收；不把Windows检查、合成SQLite或模拟器冷启动描述为正式上线验证。
- 所有既有失败报告保留；根与后端独立复核报告由对应owner保管。本目录只汇总本端事实，不覆写共享合同。

CI5原始证据由总控保管：artifacts/integration/20260918/R3-ios-ci5-evidence.zip，SHA-256 5da1972f8c3663343e1869ef50e97f063fc90e6e789b852244548d9300956fb7。补丁是该失败候选的准确重建包，不标为验收通过。
