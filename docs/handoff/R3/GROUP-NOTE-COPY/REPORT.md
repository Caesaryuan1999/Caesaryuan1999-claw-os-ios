# GROUP-NOTE-COPY：建群私人备注文案

基线 `e1ed950147233f8e9df05ad025e5e356d0097dae`；协议 C3 + AUTH-A1、设计 R3.D1 不变。单生产文件 `Tinodios/NewGroupViewController.swift`，与后续缺资料展示分开提交。

真实创建表单说明改为“设置群名称，可添加仅自己可见的备注。”；placeholder 改为“备注（仅自己可见，可选）”，该输入的 accessibilityLabel 与 placeholder 同源。原字段实际写入 private.comment，此次仅消除公开群说明的误解，没有把私有备注改成公开字段。

Windows 完成 5 个源级检查，见 checks.json：将两句文字、翻译注释和一行读屏赋值精确反向还原，并按 Git 将工作树 CRLF 归一为 LF 后，整个文件与基线 blob 逐字节一致。首次未归一比较因行尾差异失败，已据实际行尾修正核验方式。因此保存方法、头像、名称、tags、成员/权限内容均未变，工作树原 CRLF 保留。git diff --check 通过。没有新增镜像测试、原生方法或 CI 选择；累计方法数量仍为 232 原生 + 独立导航 3，尚不代表此提交已在 Mac 执行。CI29 仍只验证原 e1ed。

本批未运行 VoiceOver、真实建群、多账号、动态字体或设备流程。回退仅反向应用本单元三个展示赋值差异，不改存储/旧数据，不回退消息或身份可靠性。原始只读发现保留在 UI-NEXT-UNITS-DRAFT.md，后继实现以本报告为准。
