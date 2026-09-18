# VOICE-UPLOAD-COPY-01

独立一行显示修正；生产基线785461b2006dbc0260472ebfe3cd36907fcbca27，前置文档1c88c77。

MessageInteractor.swift上传失败回调的音频文案从“录音上传失败，请在消息中重试。”改为“录音上传未完成，请重新录制后发送。”非音频分支与上传/消息状态不变。

源码核实：当前没有本消息重新上传入口；markPendingFailed将draft10转failed40，queryUnsent只有20/36，因此不是bulk retry发布failed占位mid的漏洞。此单元仅纠正不可兑现的恢复文案，不新增retry、不改mid/srvUrl/状态/责任。重新上传能力仍未实现。

Windows原始字节单次替换验证：恰一旧字符串→新字符串，反替换与原文件逐字节一致；git diff --check通过。无新镜像测试，无Swift/Mac运行声明；原210+导航3方法数量不变。CI22固定785不包含本行，后续精确候选由总控执行。未推送。
