# R3 iOS 安全源码交付包 · 1B20EC2

固定源码、必要测试及 CI 的累计补丁；不是完整发行仓库、IPA 或真实设备验收。复用 FINAL-E6E07AFF / VIDEO-OWNED-02-PACKAGE 的临时索引正向应用流程，旧包、私有配置、原失败证据和未跟踪工作均保留。

## 精确版本与范围

- 已保全完整起点：`34a8b3e5ad4df210117e2e03b308576796ba55b2`。
- 固定源码/测试/CI 目标：`1b20ec2971061dbc002d1748f0f252d87b69d0f7`。
- 最新生产提交：`603476bf93b652821af7f83afdba00bb023c3cf4`；1b20 是真实组件测试前置/可见性修正，不是新的产品代码。
- 封包前分支 `codex/r3-20260918-ios`、tracked dirty=0；origin 为自有 `https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios.git`。原五组 untracked 见 repo-state-before.json，未清理或纳入补丁。
- 正式实体 `CLAW-IOS-R3-source-test-ci.patch`：**1,165,207 bytes**，SHA256 **448633865dec72f1c178dce9ff0f4690b14bdc7eed039c38b1fe91259d85580f**。
- **102 路径：71 修改、31 新增、0 删除；目标模式全部 100644。**其中 98 项为 BASE→TARGET 的全部非 docs 差异，另外四项为继承已审的必要可执行合成回归脚本。
- 本目录的后继文档提交只封交付，不改变上述源码目标。不得把文档 HEAD 冒充 Mac 测试 SHA。

allowlist.json 逐路径列出范围依据，paths.tsv / file-manifest.json 列出字节与 Git 对象；commits.tsv 保存分批提交完整 SHA。相对 VIDEO-OWNED-02 包新增路径仅 EditMembersViewController、NewGroupViewController、VoiceLayoutTests，分别来自已批准的缺资料展示、私有备注文案、真实 App 组件测试；其余变化是同一已审范围的后继提交。

四项 docs 可执行文件为：CI-SMOKE/check_smoke_runner.py、CI21-CONFIG-01/verify_real_config.rb、LOCAL-DELETE/check_local_delete_sqlite.py、LOCAL-DELETE-PLAN/reproduce_partial_delete.py，均在 docs/handoff/R3 下。它们分别为真实 runner 的受控系统边界、真实 Ruby Config、生产 SQL 适配与原合成故障证据，不含真实账号或数据库。本次封包没有重跑这些回归，也没有据此提高 Swift/设备验收等级。

排除其他 310 项变更 docs（历史报告、旧封包和生成证据）；逐项见 scope-review.json。SharedUtils 私有源、真实 GoogleService/push 文件、签名/密钥、Pods/build/.runtime、用户库、便携工具、PNG/视频/xcresult、大量原始日志均不纳入。SharedUtils 没有 BASE→TARGET 差异仅由路径元数据核对，未读取内容。既有 CI 只生成禁用的 push 占位文件，不提供正式推送能力。

## 实际正向应用

在独立临时 GIT_INDEX_FILE 中加载真实完整 BASE（512 个条目），执行 `git apply --cached --check` 后实际 `git apply --cached --whitespace=nowarn`，不是只有反向检查：

1. 全部 102 个目标文件 mode、Git blob、内容 SHA256 精确匹配目标。
2. 全部未选择的基线条目原样保留；应用后安全树 `34ee0b1eab725402e69ab3ee344df42f76be649a`。因为报告等变化未应用，此树有意不等于完整目标提交树。
3. 当前真实工作索引前后 SHA 不变；没有 checkout 私有文件或读取其 blob。临时目录仅在本报告目录下，使用解析后的边界检查并在完成后清理。
4. 源范围 `git diff --check BASE TARGET -- <allowlist>` 通过。补丁保存 Git 原始字节；74 项 Windows 工作树 SHA 与 Git blob 不同，manifest 分列两者，不用工作树行尾改写补丁。

在保留 BASE/TARGET 对象的本仓库复验，不改变实际索引：

~~~powershell
rtk python -X utf8 -B docs/handoff/R3/FINAL-1B20EC2/verify_forward_apply.py
~~~

补丁自身是带空白上下文行的 Git 协议文本；把它作为普通新增文本检查可能报告上下文空白，不得 trim 改写实体以消除提示。若 checkout 转换了附件行尾，可运行验证器 `--generate` 从固定 Git 对象恢复原字节，再核上述 SHA。bundle-hashes.json 校验本目录其他实体；seal_package.py 仅重建同格式清单及已存在证据的引用，不构建、不执行原生测试、不访问网络。

## 当前准确运行证据

精确 1b20 的 [CI30 run35361193265](https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios/actions/runs/35361193265)，job105652584258：

| 层级 | 实际结果 |
|---|---|
| SDK | 44 PASS / 0 FAIL / 0 SKIP |
| UIrunner 单元 | 175 PASS |
| 独立 VLC host | 7 PASS，属于所列真实依赖行为观察，不能概括为全格式播放安全 |
| 真实 App SendMessageBar/XIB 组件 | 6 PASS；中性 inputAccessory 容器、合成输入/受控 handler，不是真实录音、上传、发送或完整聊天 |
| 原生合计 | 232 PASS；真实离线 App 导航另计 3 PASS |
| 打包 | PASS，未签名模拟器 App ZIP 37,450,313 bytes，SHA256 `a16037ed92f5b7fb37e93c904faec1941a4ee69e1ba200fe61434c3425bcc3fd` |
| 独立冷启动 | 模拟器 readiness 前置失败；未到 install/launch，没有本轮冷启 App/PID/PNG 验收 |
| CI31 | 同一 SHA 的唯一次已授权环境复跑 run35364243217；此包封存时待总控结果，未推定通过 |

CI30 artifact10554503451：49,411,977 bytes，SHA256 `58b0fe764142d67d8ffc1cb408fd8de9c281067987f56ffca7d9844f16dfaedd`。本次独立复核原 ZIP、App ZIP、三份 summary、冷启 manifest 和 38 项真实组件附件文件哈希；不把这些实体重复嵌入源码补丁。ci30-evidence-index.json 保存原路径、SHA、方法与附件名，引用总控原图复核；封包没有重新目视全部截图。

原件根目录：`C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci30-evidence/ios-01-a-20260918-151503`。总控报告：同级根 artifacts/integration/20260918/R3-ios-ci30-root-review.json。

冷启原始事实：同 UUID 初态 Shutdown，boot 返回 0；bootstatus 在 45 秒预算超时（实际记录 46.685563 秒），其后唯一一次 5 秒只读查询见 Booted。四份 boot stdout/stderr 都为空，具体就绪子阶段未知。Booted 不替代 ready，更不证明 App 已启动后崩溃或无崩溃；CI30 整体 FAIL 保留，未因原生通过而改写。CI31 不改 45 秒或其他门禁。

native-methods.json 从固定源码的实际 selector、XCTest 类及 extension 提取 44+175+7+6，导航 3 分列，不用文件全局方法数替代目标归属。旧库并发初始化仍为一个方法内 12 轮，不冒计 12 方法。CI26 已有的视频证据、CI28/29 原失败及 CI30 的修正结果均保留，不倒填历史通过。

## 应用、安装、回退

1. 使用已保全的完整 R3 BASE 独立副本，先核 HEAD 为上述完整 BASE，目标路径和索引 clean。不要用空上游代替；不要 reset/clean 原目录或覆盖本机配置/数据库。
2. 校验补丁实体 SHA。在该独立副本先执行 `rtk git apply --check --index '<补丁绝对路径>'`；通过后再 `rtk git apply --index --whitespace=nowarn '<补丁绝对路径>'`。不匹配立即停止，不强制覆盖或猜测合并。
3. 对照 file-manifest 逐项核 Git mode/blob/SHA，只提交明确名单，不能 git add 全目录。baseline-prerequisites.json 记录实际旧夹具与锁文件；本次 Podfile.lock 已变化并包含在补丁，不沿用 E6 的“锁未变”描述。
4. 本包本身不可安装。当前 CI30 App ZIP 仅 iOS Simulator、未签名、build1736、禁用 push、127.0.0.1:9，不是 iPhone IPA，也没有本轮独立冷启验收。Mac 续测由总控按固定 SHA/包 hash 执行；Windows 正向封包不等于 Swift 编译。真实 iPhone 仍需正式受控签名和设备资源。
5. 源码回退用另一份已保全基线，不删除当前源码或用户库。旧二进制不得直接打开未验证可降级的新状态数据库，使用升级前备份；本包不能撤销远端发送、注销等已发生操作。

真实 Android↔iOS、多设备、真实用户旧库升级、正式服务/SMS/SMTP/APNs、系统权限和完整语音/视频页面旅程尚未验收。媒体文件停止/临时清理不承诺跨进程任意故障恢复；消息级音频重新上传仍未实现，既有文案为重新录制后发送。fileURL 不等于任意容器网络隔离，真实 VLC 观测只覆盖有限合成夹具。账号数据库删除也不承诺磁盘全擦除。历史滚动的八文件计划仍仅只读提案，未进入本补丁。
