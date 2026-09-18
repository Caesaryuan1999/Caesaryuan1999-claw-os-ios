# CI29-VOICE-INPUT：仅测试夹具修正

基线 `603476bf93b652821af7f83afdba00bb023c3cf4`；之前两个展示提交为 1a9f978、603476b，已各自源审。此单元只改 `TinodiosUITests/VoiceLayoutTests.swift`，生产/SDK/DB/CI 选择与时限不变。诊断、原始 PNG/JSON 的实体 hash 与原失败另见 DIAGNOSIS.md / diagnosis.json，不覆盖 CI29 的 231 通过、1 失败。

原空→字→空用例现先请求真实输入框 becomeFirstResponder，并等本次同一个输入框的 textDidBeginEditing 通知计数增加与 firstResponder 成立（原 3 秒有界等待），再赋合成文字和断言 actualText 相等。没有伪发 UIKit 通知，也没有访问或改写私有 placeholder 标记。清空后增加 actualText 为空断言，保留原零发送/零业务动作。

保留 currentImage=nil、configuration=nil、“发送”标题、单行字体实际宽高、按钮尺寸、回空原 UIImage 相同及录音读屏等断言。仅把内部 imageView.image 必须 nil 的一条，替换为严格的无有效可见图像证据：原按钮必须有真实 window、层级可见并完整位于 window；图像必须无对象、脱离 window、存在 hidden 或 alpha 严格零的祖先，而且相关动画已结束。零 bounds、裁剪或“看起来没显示”不单独放行。读取当前子视图/祖先，不改 UI 状态、不消除动画。

原生 PNG 仍从原组件 drawHierarchy 取得；JSON 增加实际 imageView/祖先类别、hidden、alpha、bounds、windowFrame、windowPresent、clipsToBounds、动画 keys、判据类别，以及输入 begin 计数和 actualText 长度，不记录输入内容。失败 teardown 同样保留这些当前证据，不等待或重置后再拍失败状态。

Windows 完成 checks.json 中 8 个源绑定检查及严格 alpha/hidden/动画/零发送条件复核。六个方法名字不变，另五方法主体逐字不变；除原内部 image nil 断言外，所有原断言行保留。唯一代码 diff 为本测试文件；git diff --check 通过。没有执行 Swift、UIKit 或模拟器，不增加测试方法计数：下一候选仍为 SDK44 + UI175 + VLC7 + Voice6 = 232，导航 3 独立。

总控负责固定提交独立审查与后续 Mac CI。未观察到明确不可见条件仍失败，不通过放宽阈值或修改生产让测试通过。回退仅反向应用此测试夹具提交；已修生产按钮配置、私有备注文案与缺资料展示不随之回退。完整聊天、真实键盘像素、录音/系统权限/上传/发送不由中性组件容器验收代替。
