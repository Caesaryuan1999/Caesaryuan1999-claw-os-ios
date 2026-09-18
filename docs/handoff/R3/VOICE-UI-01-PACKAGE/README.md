# VOICE-UI-01 累计安全源码候选

此包是源码/必要测试/CI交付，**不是已通过运行验收的新App或IPA**。

- 完整保全起点：`34a8b3e5ad4df210117e2e03b308576796ba55b2`。
- 精确目标及最新生产提交：`e6d0aa978daf6c2aa92f88e88deb2060658226f9`。
- 累计补丁：`CLAW-IOS-R3-source-test-ci.patch`，1,072,487 bytes，SHA256 `b88e2a1dda2004d4890f5c2f529dcd588fad8becced514aefff1642eb9ee6d1f`。
- 99路径：69修改、30新增。包括全部95项非docs差异，及4份明确合成测试工具：原CI-SMOKE runner、LOCAL-DELETE SQL回归/红证据、CI21真实Ruby Config回归。
- 单元补丁在兄弟目录 `VOICE-UI-01/unit.patch`：从0a7到e6d的恰4生产文件，51,144 bytes，SHA256 `5cabdf2df18f0af582260ea0252a2ce6b739df0962608cee422dc27f933094ca`。

`allowlist.json`逐项范围、`scope-review.json`排除项、`commits.tsv`累计提交、`file-manifest.json`实际恢复结果、`native-methods.json`完整真实方法清单。旧FINAL-E6E07AFF和全部失败证据原样保留；本包文档提交不是新生产SHA。

## 已实际正向验证

在独立临时GIT_INDEX_FILE中read-tree完整真实BASE；先apply --cached --check，再实际apply --cached。99文件目标mode/blob/原Git字节SHA逐项匹配，所有未选基线条目保持，实际工作索引前后SHA相同。没有空仓库替代基线、没有checkout/读取私有配置。四文件unit另做同样正向应用及未选项检查，见unit-forward.json。

复验累计包：

~~~powershell
rtk python -X utf8 -B docs/handoff/R3/VOICE-UI-01-PACKAGE/verify_forward_apply.py
~~~

要求完整BASE与TARGET对象存在，当前明确安全路径与TARGET语义一致。补丁以Git blob原始字节生成，不把Windows工作树行尾冒充Git字节；manifest分列两种SHA。若Git checkout转换补丁附件行尾，按已封Git blob按字节导出或在保全仓库用验证器`--generate`重建后核SHA。

未纳入：SharedUtils、真实GoogleService/push、签名/密钥、Pods、build、runtime、Ruby安装工具、xcresult/PNG/视频/数据库、报告与旧封包。SharedUtils无差异仅由路径元数据核实；不读取内容。VLC probe空host是必要测试源，不入正式Archive，不带账号/真实网络凭据。

## 验证等级

本次视觉source/XML19、既有源策略44通过。原CI实际capture/reset适配器已在固定e6d干净源码执行提取成功，生成文件不进补丁；三个生产方法固定哈希和断言不变。这是Python提取，不是UIKit执行。

清单从精确目标脚本selector和实际测试class/extension逐项提取：44 SDK + 167 UIrunner + 4独立VLC host = **215原生**，真实App离线身份导航3另列。本次没有新增方法，不把12轮并发fixture计成12个方法。

总控CI23精确0a7：44+167全部通过；VLC4是3PASS/1FAIL（reopen-403-timeout），导航/包/冷启动NOT_RUN。该轮不含新面板；3个VLC观测成功也不能宣称播放安全，owner退役继续读/重定向行为另由总控处理。CI22旧应用编译失败原证据保留。最新完整已验应用仍CI17/e6e07aff，不能使用相似前缀的本次e6d0aa9替代。

新面板完整Swift/XIB编译、聊天页真实手势/布局、深浅/辅助字/VoiceOver、系统麦克风/声音/中断、真实服务与跨端均未验。新增用户界面不提高旧可靠性或依赖测试的证据等级。

## 应用、安装、回退

1. 在另一个完整保全BASE副本确认HEAD与目标路径clean，备份本机数据；不reset/clean原目录。
2. 核补丁SHA，再`rtk git apply --check --index <绝对补丁路径>`；通过才执行`rtk git apply --index --whitespace=nowarn <绝对补丁路径>`。不匹配即停止，不强制覆盖私人配置。
3. 按manifest核mode/blob，仅提交明确名单。不能`git add .`。
4. 由总控审定精确源SHA后推既有验证分支运行Mac。只有对应准确SHA的未签名模拟器App ZIP可供同平台安装续测；Windows源码补丁不能直接装iPhone，签名/推送未提供。
5. 视觉回退只从精确e6d且四文件clean的独立树对unit.patch先`git apply --reverse --check`，再反向应用；它只回到0a7视觉，保留已封录音可靠性/文件责任/RESET/quote修复。整体退版本用备份，不让旧二进制直接打开未验证兼容的新库。补丁不撤销远端发送/注销，也不承诺磁盘全擦除。
