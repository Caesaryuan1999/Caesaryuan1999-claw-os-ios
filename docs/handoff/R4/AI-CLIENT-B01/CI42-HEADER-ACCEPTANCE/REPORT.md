# CI42 后继：响应长度与无响应期限分开验收

按总控冻结的 `docs/context/R4_IOS_STREAM_HEADER_ACCEPTANCE.md` 实施。起点 `fb85298c5cd9cb503221b2fee350ba2a7fa4294a`，唯一代码路径 `TinodiosUITests/AssistantStreamTests.swift`。生产网络、HELP、B02、PBX、selector与workflow不改。本窗口未推送/运行CI；期望 **295原生+3导航**，不是已执行结果。

## 保留CI42原红

总控已核的原CI42 run35415602665 / source1cb，293通过/1失败。原ZIP位于根 `artifacts/integration/20260919/R4-ios-ci42-evidence.zip`，95,493,395字节，SHA256 `69190f0507b085f2ad252548ffea2c202d71612e16a56decbb56b51d054a89a4`。本次引用总控原件复核，不再次运行旧候选。

原case7仅98字节响应头、无body/EOF，在5秒失败；导出的trace显示请求与send成功约在case开始后2.5ms，取消仅来自失败清理。实际Service同头+1字节的独立控制在5.331ms结束为invalidResponse且0events。这证明该输入下生产长度门禁有效，不证明原header-only满足5秒拒绝假设。裸probe原观察还受临时underlyingQueue生命周期警告限制；fb852的强持有修复和原控制必须后继重新实跑。

## 授权差异

原拒绝方法仅在case7原头后追加 `0x7B`，仍不EOF/关闭连接，保持5秒invalidResponse与零frame断言。前6case和全部其他原方法逐字保留，包括真实60秒heartbeat、原裸控制和安全清理。旧header-only失败不改写为通过。

恰新增 `testRealSocketHeaderOnlyEndsAtAbsoluteSixtySecondBudget`，使用实际Service、独立loopback server和原header-only字节。无时钟注入、无正文/EOF；从实际启动前的单调时钟测量，等待65秒，完成必须≥60且<64秒。仅允许真实deadline或transport类别，按原completion准确记录，不把transport重命名成deadline；其他错误、提前结束、取消或没有completion均不能通过。要求唯一请求/成功send、零事件、一次completion；显式清理后再检查一次计数，并在首个可能失败点前注册原生keepAlways附件保留清理后的最终计数。

记录固定类别、序号、字节数量与时间，绝不记录URL、凭据、header值或正文。新增附件名 `assistant-stream-header-only-deadline`。保留裸控制的强队列引用，原method本身没有额外修改。

## 检查与后续取证

`source-checks.json` 固定原/新SHA和13项Windows源码检查：只有单代码路径、原8方法中7个逐字相同、剩余方法恰为单字节表达式变化、原所有helper不变、仅新增第9方法、原60秒与5秒控制保留。`git diff --check`通过。没有Swift编译或新原生运行结果。

下一准确Mac候选须同时核：队列warning消除、295原生/3导航实际计数、原拒绝trace、裸控制trace、新60秒终结trace及类别/计数/时间，以及同候选HELP关闭说明/AX画面和许可导航。不能只看全部测试绿便宣布平台普遍缓冲行为或真实模型服务已经验收。

源码回退只对本提交做受审的 `git revert <本提交SHA>`，不reset/clean，不覆盖原CI42或既有恢复段；HELP与fb852保持各自独立提交。
