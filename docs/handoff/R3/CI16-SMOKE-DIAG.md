# CI16 冷启动失败只读诊断

日期：2026-09-18。精确CI源74075fec5334a1e2325b2b194974828afdd6f2f3；run35322005060 / job105526377380。本报告在UI候选1125ef87之后仅追加handoff；未修改生产、测试、超时、workflow，不push/dispatch。

## 已核事实

原artifact10537879247：38,346,129字节，SHA256 4d817577d7650bd91def419eb8cbb7b0c392af29ebb351b246b4d26f28f5c4a1。本端实际重新计算ZIP hash一致。根原件目录 artifacts/integration/20260918/R3-ios-ci16-evidence/ios-01-a-20260918-075911；原失败不覆盖。

| 层级 | 实際证据 |
| --- | --- |
| SDK | sdk-summary：41通过，0失败/0跳过 |
| 存储与业务 | storage-summary：155通过，0失败/0跳过；与SDK共196原生 |
| 真实App离线身份导航 | navigation-summary：3通过，0失败/0跳过，独立于196 |
| 导航截图导出 | PASS_EXPORTED_ONLY；没有在本报告再次目视所有PNG |
| 打包 | 成功；unsigned simulator ZIP SHA e56132ce5565a619e9de99d0a357a5d3bd2b3e429e657183bf617e33c18b949f |
| 独立冷启动 | FAIL，停在bootstatus前置；尚未install/枚举旧进程/terminate/launch/PNG |

launch-smoke/manifest.json 的唯一三个命令：

1. list_existing_devices：rc0，2.659337秒。同一UUID DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9，iOS18.5，isAvailable=true，state=Shutdown。
2. boot_tested_device：rc0，1.948966秒。
3. wait_tested_device_boot：45秒超时，实测45.705279秒；returncode=null。没有随后Booted复查。

GitHub fetch_workflow_job_logs的structuredContent.content已读：08:16:22.328748Z进入smoke，08:17:13.030630Z输出wait_tested_device_boot exceeded 45 seconds并exit1。最后导航方法在08:16:04.351939Z通过；导航teardown实际terminate PID42704；附件导出08:16:16.289113Z完成。不得据此推断导航关闭了这个固定UUID，xcodebuild本身的设备生命周期没有被记录。

crash_reports=[]仅因为本轮没有App launch PID可供筛选，不证明App无崩溃，也不证明App导致本轮失败。最精确分类是“模拟器启动就绪前置未在阈值内完成”；CoreSimulator内部卡住阶段/宿主压力/是否晚于45秒就绪均未证。

## 与CI13/14的区别及脚本检查

- CI13卡在无条件terminate_previous；CI-SMOKE03补了精确安装路径和ucomm→proc_pidpath进程前置，在确认未运行时才跳过terminate。
- 本轮根本未进入进程检查，因此不是已知terminate路径再次复现。
- CI14同UUID/iOS18.5：bootstatus22.507605秒rc0，之后Booted复查/安装/进程/launch/PNG通过。
- smoke_simulator_launch.py在56c4a7f、74075fec、1125ef87的Git blob字节SHA完全相同：e2a85b0fa82cb7c0e29b53aa28715a5b5513b63cb49c95225e89b8a86715fc4b。新视频UI并未改冷启动脚本。

脚本55–67行的command()用capture_output=true取得子进程输出，但超时59–62行没有保留TimeoutExpired.stdout/stderr；正常/非零命令也只在manifest存rc和耗时。boot返回值的stdout未被消费。ZIP中launch-smoke仅manifest，没有boot输出、err文件或冷启动PNG。job完整日志也没有boot阶段明细，所以既有证据不能还原具体bootstatus文本。

Python官方说明TimeoutExpired可携带已捕获的输出（可能为bytes/None），run超时会结束其子进程后抛错。这为后续保全诊断提供现有接口，不要求改命令或延长45秒：[Python subprocess](https://docs.python.org/3/library/subprocess.html#subprocess.TimeoutExpired)。不能把结束simctl等待进程称为已经关闭/修复CoreSimulator。

## 最小必要提案（尚未实施）

仅2个测试/CI文件：Scripts/ci/smoke_simulator_launch.py 与 docs/handoff/R3/CI-SMOKE/check_smoke_runner.py。

1. 仅针对固定boot/bootstatus命令保存有界stdout/stderr（成功、非零、TimeoutExpired已有部分输出），记录字节数/截断情况。不给ps全量列表或其他进程参数落盘，不新增全系统日志。
2. 原bootstatus超时仍判FAIL且抛出原错误。可以在失败诊断中做一次有界只读simctl list，仅记录同UUID的runtime/state/isAvailable；该诊断即便看到Booted也不得变PASS或继续install/launch，查询失败不得覆盖原超时。
3. 保留45秒门禁、同UUID、安装/进程/路径/hash/PNG/crash断言；不加sleep重试、不重boot、不换机、不forcekill模拟器、不改App。
4. 在真实Python runner的受控subprocess边界补输出保全/bytes与None/截断/诊断失败原错误优先/超时之后零install与launch等回归。仍不等于macOS运行；原196+3测试不变。

没有证据支持当前修改生产、直接延长timeout或声称已修复宿主根因。下一次准确CI应以必要诊断改动及/或独立批准UI候选为依据，由总控协调；本报告不自行重跑。本轮整体FAIL与196+3和打包成功必须分层保留。
