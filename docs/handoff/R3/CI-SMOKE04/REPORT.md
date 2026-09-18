# CI-SMOKE04：同设备 boot 超时诊断保全

日期：2026-09-18。独占工作树 work/r3-20260918-ios，codex/r3-20260918-ios。父文档提交1f24a88bfb7510d5af17e90e80e33f06fe9aec69，生产UI候选1125ef87保持。总控已批准两个CI/测试文件；未push/dispatch。

## 已知失败与本单元目的

CI16固定74075fec，SDK41+storage155共196原生、另3个真实离线身份导航及打包通过。冷启动停于同UUID bootstatus45秒超时，尚未install/launch。原ZIP、SHA、命令耗时与CI14对照保留在../CI16-SMOKE-DIAG.md及根R3-ios-ci16-evidence。不能把本单元称作已修复CoreSimulator启动根因，也不把CI16记整体通过。

## 修改边界

1. Scripts/ci/smoke_simulator_launch.py：只新增boot输出保全和失败后只读观察。
2. docs/handoff/R3/CI-SMOKE/check_smoke_runner.py：执行同一生产Python runner的受控命令边界回归；不是镜像启动实现。

另新增本目录REPORT/red/green/static-policies交付证据。App/Swift/Storyboard/VLC/SDK/DB、原生方法和selector、workflow、导出XCTest附件逻辑均未改。

## 精确行为

- 只对固定boot_tested_device和wait_tested_device_boot保存stdout/stderr；包括正常返回、非零和TimeoutExpired携带的部分输出。
- 每个流最多保留末尾65536字节，最多两个步骤四文件（内容上限256KiB）。manifest记录captured、原字节数、保存字节数、truncated、保留tail、文件名和SHA256。字符串按UTF-8编码；异常的bytes原字节保留；None单独标captured=false并保存空文件。截断可能落在UTF-8字符中间，原字节不重写，阅读器可替换显示。
- 文件名仅固定步骤+stdout/stderr.txt，不记录环境变量/凭据或ps全量输出。此处是独立CI模拟器的固定boot命令输出；不扩收全系统日志。
- 原命令仍timeout=45，不retry、不改阈值。超时后仅一次只读simctl list devices --json，额外timeout=5，记录实际elapsed；只落同一UUID的runtime/state/isAvailable，其他设备名称和完整JSON不保存。
- 观察得到Booted也仍抛原45秒错误，保持FAIL；不继续install/launch，不再次boot/terminate，不换机/erase/重置。
- 只读诊断非零、超时或格式错误只记录安全类别/数值，不覆盖原故障，不写异常文本。输出文件写入失败也不能遮盖原boot失败；成功boot但诊断输出无法落盘则明确FAIL。
- 原进程前置、精确路径/hash、安装、launch、PNG与crash部分从previous_app_processes开始至文件末尾逐字一致。现有workflow的launch-smoke/**已上传新增小文件，无需改workflow。

## 红绿与实际层级

新增8个方法在原1125版本runner下实际执行：43方法中原35通过，新7失败+1错误。证据red.json。修改后43/43通过（35 smoke +8 export；本批新增8 smoke），green.json保存SHA与边界比较。

新增案例覆盖：成功和非零boot输出；超时部分bytes尾部截断/哈希；无输出None；诊断Booted仍失败/零install；诊断非零/5秒超时/错误JSON不替换原故障；initial boot超时只观察同UUID一次且无设备替换。所有原方法仍执行；真实runner而非替代算法，macOS subprocess、proc_pidpath与sleep边界受控。

已执行命令：
- rtk python -B docs/handoff/R3/CI-SMOKE/check_smoke_runner.py — 红8失败/错误，绿43/43。
- rtk python -B Scripts/ci/run_static_policies.py --report docs/handoff/R3/CI-SMOKE04/static-policies.json — 44/44。
- rtk proxy git diff --check — PASS。

以上是Windows Python/源码验证，不是simctl或宿主启动证据。下一Mac精确候选仍196原生+3真实身份导航，包含独立1125新视频UI的编译；新增Python方法不加入196。模拟器boot根因尚未证，等待下一准确候选的原始boot诊断和整轮结果，不盲重跑旧SHA。

回退本CI单元仅回到父提交，生产仍1125；不涉及数据迁移/擦除或用户环境。总控唯一负责审核固定SHA及授权CI17。
