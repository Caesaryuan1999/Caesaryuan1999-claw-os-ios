# R3 iOS 安全源码交付包（截至 E6E07AFF）

此包只封源码、必要测试和 CI 差异，不是 IPA，不包含签名、真实推送配置或用户数据库。封包不提高运行验收等级；CI17 的最终结果、产物和截图以总控单独复核为准。

## 精确版本与实体

- 已保全完整起点：34a8b3e5ad4df210117e2e03b308576796ba55b2。
- 精确累计目标：e6e07aff8215ea003312a518d6f83e0c1da0ee84。
- 最新生产视觉单元：1125ef87b14b24343dd1d3f7825cc8c28a9867f1（视频 UI）。其后的诊断报告和 E6 的两项 CI/测试修改不属于生产代码变化。
- 正式补丁：CLAW-IOS-R3-source-test-ci.patch，855,315 bytes。
- 补丁 SHA256：04cd1b9a2b1967bb405f2ea97ce745a3d474d0916da0430abaf39916a6f42f1e。
- 88 路径：63 修改、25 新增、0 删除；全部目标模式为 100644。
- 本目录自身的文档提交不是新的源码目标；不得将文档 HEAD 误写为经过 Mac 验证的源码 SHA。

本包覆盖起点到目标的 **全部 85 项非 docs 差异**，以及下列 3 项被 CI 或本地故障回归直接使用的 docs 下可执行文件：

1. docs/handoff/R3/CI-SMOKE/check_smoke_runner.py：实际 smoke/export Python runner 的受控外部系统边界回归。
2. docs/handoff/R3/LOCAL-DELETE/check_local_delete_sqlite.py：生产删除 SQL 的 SQLite 适配执行，非 Swift 执行。
3. docs/handoff/R3/LOCAL-DELETE-PLAN/reproduce_partial_delete.py：保留修前部分删除故障红证据生成器，使用合成内存库。

其余 167 项变更 docs 是报告、历史封包或生成证据，未混入源码补丁。scope-review.json 逐项列明排除路径；allowlist.json 逐项列明纳入依据。此次只封包，未再运行会生成证据的故障回归脚本。

## 实际正向恢复证据

file-manifest.json 记录真实执行，不是仅 reverse --check：

1. 在独立临时 GIT_INDEX_FILE 中 git read-tree 真实起点完整树（512 个 entry），不重建空上游。
2. 先 git apply --cached --check，再实际 git apply --cached --whitespace=nowarn。
3. 验证全部 88 个目标文件的 mode、Git blob 和字节 SHA256 精确一致。
4. 验证所有未选条目与原基线完全一致，真实工作索引前后哈希相同。
5. 只读取明确安全名单中的 blob；未 checkout 或读取 SharedUtils 等私有内容。临时目录位于本报告目录下，验证完按已解析边界清理。

应用后安全树为 da0a7df52f4d3aa1963654605bb799f04de13ab7。因为报告等未选变化保持基线，此树刻意不等于包含报告的完整目标树。

补丁保留 Git blob 原始字节。79 个工作树文件的行尾字节与 Git blob SHA 不同，manifest 分列 target_git_sha256 与 target_worktree_sha256，不得用工作树行尾重写补丁。源码范围 git diff --check BASE TARGET -- allowlist 已通过。原始 .patch 作为文档被 Git 检查时，实际出现 348 行合法空白上下文的尾空白提示（artifact diffcheck 返回 2）；其他 11 个封包文件 diffcheck 为 0。这是补丁实体格式，不是源码新增空白，不能修改补丁字节来消除该提示。已额外核实暂存的 patch blob 与实体字节完全相同。

在本已保全仓库复验（要求真实 BASE、TARGET 对象都存在；不执行 checkout 或改变当前 index）：

~~~powershell
rtk python -X utf8 -B docs/handoff/R3/FINAL-E6E07AFF/verify_forward_apply.py
~~~

若之后 Git checkout 自动转换本报告附件的行尾，应从已封 Git blob 按字节导出，或在同一已保全仓库执行该验证器的 --generate 后重核实体 SHA；不得手工 trim 补丁。

file-manifest.json 是逐文件结果；paths.tsv 提供简表；bundle-hashes.json 校验本包文件；commits.tsv 保留从起点到目标的分批提交顺序。

## 起点与排除项

必须使用已保全的真实起点及其原有依赖，不能拿空仓库或上游原版代替。baseline-prerequisites.json 记录未发生差异、因而不在 patch 中的必要文件：

- Scripts/ci/fixtures/ios113.sql：合成 A/B 账号、旧状态及附件 fixture，不是真实用户数据。
- Podfile.lock：既有依赖锁定文件；不打包 Pods。
- Scripts/ci/run_static_policies.py：既有源策略入口。

排除实际 SharedUtils 私有配置、真实 GoogleService/push 配置、证书/密钥/签名、Pods、build、.runtime、用户库、下载产物、PNG、xcresult 和旧封包。SharedUtils 相对起点无差异仅由 Git 路径元数据核实，未读取内容。CI workflow 的缺失文件分支只生成禁用的占位 push plist，不提供真实推送能力；不得把它替换为正式服务凭据再公开提交。

## 应用、安装与回退

1. 保留现用源码和本机数据备份。在另一份已保全起点副本中确认 git rev-parse HEAD 等于上述完整 BASE；确认待应用的 88 个路径及其索引无未提交更改。不得 reset/clean 原工作目录，不能覆盖已有私有配置。
2. 先校验补丁实体 SHA。PowerShell 可用 rtk proxy powershell -NoProfile -Command "Get-FileHash -Algorithm SHA256 -LiteralPath '<补丁绝对路径>'"。尖括号内容是需替换的路径，不是可直接执行的值。
3. 在该独立副本执行 rtk git apply --check --index '<补丁绝对路径>'，成功后执行 rtk git apply --index --whitespace=nowarn '<补丁绝对路径>'。任何不匹配先停止核对真实基线，不用强制、三方覆盖或改补丁猜测。
4. 按 file-manifest.json 核对已应用文件的 Git mode/blob/SHA；仅审查和提交明确名单，不能 git add . 把私有配置或生成证据带入。
5. 构建及模拟器安装通过既有 macOS CI 工作流完成，当前远端推送/dispatch 由总控执行。Windows 封包不能证明 Swift 编译。真实 iPhone 安装仍需受控签名、设备及服务资源，本包不能直接安装到手机。

源码回退使用另一个已保全起点副本，不通过删除当前源码或清空用户库实现。源码补丁不能撤销已发生的服务器操作、账号注销或消息，也不能证明数据库可由旧二进制安全降级。保留升级前备份；没有对应兼容验证时，旧二进制不要直接打开新库。当前未完成跨重启任意故障下的自动账号清理，不承诺数据库行删除等于磁盘文件物理擦除。

## 测试与产品验收边界

native-methods.json 从精确目标的真实 XCTest 类及扩展提取，并和 workflow 实际 -only-testing: 选择核对：

- 原生 196 方法：SDK 41，storage/App 单元 155。
- 真实 App 离线导航另计 3 方法。
- LocalMigration 的并发初始化是一个方法内 12 轮、24 次开库，不能计成 12 个方法。
- OwnedImageTests 的 21 方法包含 helper 后的 extension；不能漏算追加的下载测试。

已取得的准确历史事实：CI16 精确 74075fec5334a1e2325b2b194974828afdd6f2f3 的 SDK41、storage155、导航3 均通过并成功打包；随后同 UUID 模拟器 bootstatus 超过原 45 秒而失败，当时没有安装或启动 App，不能称 App 崩溃或完整 CI 成功。其后 VIDEO-UI 和 E6 有界诊断需要 CI17 精确目标结果，封包时仍待总控。

E6 在 Windows 的实际 Python runner 受控回归为 43/43；44 源策略通过，总控亦独立复核。它保留 45 秒失败门槛，只增加有界 boot/bootstatus 输出及失败后一次 5 秒的同 UUID 只读状态诊断；不会失败后继续安装、换机、强杀、重 boot 或隐藏失败。此处不等于 CoreSimulator/真机执行。

CI15 的真实密码输入长度、非 placeholder、键盘 geometry/hittable 断言通过，但 App 和 XCUIScreen PNG 仍为空密码且无可见软件键盘，视觉掩码/截图差异保留，不因断言通过而抹去。视频 VLC 内部缓存/重定向、真实媒体播放/分享、完整 VoiceOver/动态字号、真实设备/推送/正式服务均不得由这份补丁或测试数量推定完成。
