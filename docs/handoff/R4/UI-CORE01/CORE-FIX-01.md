# R4-UI-CORE01 / CORE-FIX-01 — AX 未读徽标

独立源码提交 `bff92a46301891a0b67055611e3eb0a8c10dc6e5`，父 `4d7f5539e1cd225735b5a64f541d3a26e44180bd`。只有 `Tinodios/widgets/ChatListViewCell.swift` 和 `TinodiosUITests/CoreListLayoutTests.swift`。助手 A 的九生产/两测试 WIP 没有 stage，封前后11文件 raw SHA 对应 `CORE-FIX-01-checks.json`，该记录仅代表这个保全时点。

## 真实反例与根因

CI34 `c84ab98d / run35389096537 / job105742997819` 的SDK44、storage204、导航3、打包及冷启动成功。248原生绿色不覆盖徽标真实字形宽度；本缺陷由根对原截图复核发现，并保留为原CI视觉缺口。

根原件 `artifacts/integration/20260919/R4-ios-ci34-evidence.zip` SHA256 `69171ac24b961ee75c10ca1bbcf1a759cebf7d7cc515029523c035811e1a88f8`。本端独立读取附件manifest，目视原浅色 `09BBFE61-2D6E-437B-A5C3-C176104AF4BF.png`、深色 `585AC8DC-14A7-4428-9F8E-733BCBF10670.png`，两图未读9+均实际变为省略号。

- 浅色几何 `6487459B-95D5-40FE-81B4-6C2FE147A920.json`：unreadCount font38、height54、width28。
- 深色几何 `4D1838D6-93ED-4A52-BF2F-0EAD367E8AC4.json`：同样38/54/28。
- 标准字号 `ABD129CD-78DC-46B5-BBF8-ADDCB1A538F2.json`：font12、height24、width28。

原 `fillFromTopic` 在赋文字时计算宽；真实trait传入后UILabel自动放大字体，`layoutSubviews`只重算高度，没有重算宽。因此AX沿用标准28宽。原测试只检查文本属性、徽标在cell内及标签高度，未证明字形能装入实际宽度。

## 最小修复与新增验收

统一当前文字/字体的徽标尺寸方法，在awake、fill及layout调用；宽取当前字形宽向上取整+12与当前高度的较大者。layout前后检查UIKit已解析的字体，只有尺寸改变才更新约束；保留Dynamic Type、不缩字、不改未读数/9+上限、不动XIB/徽标数据语义。标准12pt下9+仍为原28宽；单数字在AX下保持能包容字形的圆形最小宽。

原6个CoreList方法及每条旧XCTAssert保留。原有标准/浅深AX测试增加CoreText真实字体字形宽度对实际UILabel.bounds检查，保留12pt以上放大、单行、不缩字体、原containment；覆盖9+→5→隐藏→再9+与同一个cell AX→标准→AX。附件增加字形宽数值及单数字/恢复后的原UIKit截图。原3秒有界等待不变，无新方法、workflow、selector或超时变更。

## 当前验证等级

- Windows：`git diff --check`通过；现有 `test_chat_list_branding_policy.py`通过；6方法名保持、所有旧断言文本保持的限定比较通过；助手WIP raw SHA 11/11保持。
- 新CoreText/UIKit断言、字体变化和新截图尚未在Mac运行。预期仍248原生+3导航，不能把CI34旧绿色移到新SHA。
- 不作真机、真实账号/服务、完整聊天验收；由根审查固定SHA后决定精确CI。未自行push/dispatch。

回退：只在对应安全独立树对该两路径提交反向应用；不reset/clean，不覆盖助手WIP或原CI34/CORE资料。原包不重封。
