# VOICE-RESET-02 — 可选手势快照完整消费者补正

父提交09408df45b2ad28864ac98f4c422ecf2a7fbb389；独立于CI22音频quote编译修复。此前4902997将CGPoint!改为CGPoint?并修reset，但遗漏longPressed.changed中两个.x/.y访问，属于确定Swift编译阻断。Backend独立源审发现；490没有Mac编译通过，原Windows5检查/4待执行UIKit用例只覆盖capture/reset方法，未发现该遗漏，原报告保留。

仅1生产SendMessageBar.swift：changed入口`guard recordingStarted, let origin = sendButtonConstrains else { return }`；移动使用origin.x/y。没有snapshot时不移动，不强解包；方向选择、60pt阈值、锁定/取消/发送/录音行为未变。

逐项核实全文件5处snapshot引用：可选声明、changed绑定、capture赋值、reset绑定、reset消费清nil。没有直接成员访问或force unwrap。三个实际reset/capture方法与490逐字不变；只有手势完整消费者安全解包。

必要CI脚本增强：在原严格HEAD绑定/固定完整方法hash外，唯一提取整个longPressed，核changed首先绑定snapshot、移动用origin，且全文件拒绝直接或强制可选成员访问；记录完整gestureConsumerSHA256。该部分是源码检查，不冒充执行gesture或加载XIB。原4真实UIKit源适配方法不改、不新增native数量。

Windows实际执行当前CI提取器5边界全部符合预期：当前固定源成功；dirty拒绝；原490真实源因遗漏changed绑定拒绝；直接可选移动拒绝；其它强解包消费者拒绝。`checks.json`保存结果和全部snapshot行；`adapter-source-hashes.json`保存固定生成/方法/完整手势hash。原5检查未覆盖本次问题的事实不覆盖、不改成当时已绿。

定向media_attachment/brand_ui源策略、bash -n与diff --check通过；未运行Swift/UIKit/实际XIB/聊天页。下一精确候选预期 **SDK44 + UIrunner167 + VLC4 =215，导航3另列**，包括094的新1真实Drafty构造用例。当前CI22只有SDK43实际PASS；UIrunner、VLC、导航、包/冷启动未运行。

总控/后端固定源审后交唯一总控CI；未push。视觉面板仍独立后继提交，保持inputAccessoryView与录音lease/文件责任。本单元无协议/DB/配置变化，不能以适配器替代实际聊天首次返回、真实长按与布局验收。
