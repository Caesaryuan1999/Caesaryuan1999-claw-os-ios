# CI35 未读徽标夹具修正

源码后继 `9a6f8153a6b7b7314a2abb1ee43749beabe6ad11`，只有 `TinodiosUITests/CoreListLayoutTests.swift`，5增/2删，生产0。父为A初版报告提交0fd4f899；不是把A内容混入此单提交。原bff和CI35失败保留，不重封旧CORE包。

本端独立从根原ZIP读取sdk/storage summary并核SHA：`artifacts/integration/20260919/R4-ios-ci35-evidence.zip`，SHA256 `29cd041c6cb3c84a19964bf6172ae6d6e513eb123f62bb5335fa4636f342b7c3`。精确bff92a4、run35393297461/job105756331195，SDK44PASS；storage203PASS/1FAIL，无skip。唯一失败CoreListLayoutTests的AX两appearance方法，line319期望9+但实际旧文字5；Core六方法5PASS/1FAIL，导航/打包/冷启动未执行。

确证根因：原真实SDK `Topic.read` setter（Topic.swift:250–258）仅接受大于已有值的更新。本夹具同一个topic先read7，再read=seq12，最后read2不会回退；生产cell保持隐藏，并仍存有上次5字符串。失败不是字体修改后把9+变成5。不可将期望改为5，也不可放宽字形断言或改SDK已读单调语义。

修正是复用同一真实cell但以现有topic()构造新实例（seq12/read2），显式断言新实例read2、原实例仍read==seq。保留9+→5→隐藏→新topic9+，AX→标准→AX，以及原六方法/全部旧assertion/3秒期限。没有生产、业务或SDK变动。

本端另独立从原附件manifest核图并实际view：

- `E103FDAB-1275-46E1-9278-58A5ACE7AE81.png`（rows-ax-light）已可见完整9+；配套`9D96A5FF-7A85-4C1C-976F-D33AEE22231D.json`当前font38/width62/height54/真实CoreText字形49.0285。
- `3E928553-4E86-4416-B898-9474F5D76D2A.png`（single-ax-light）完整单数字5；配套`133F3EBD-1024-4744-A78F-90FE9F1D0F35.json`font38/width54/height54/字形23.5632。
- 根原件目录为`R4-ios-ci35-native-review`，以上不是重绘。方法在light后半失败；新暗色和往返完成仍待后继CI，不能从两张浅色成功图关闭整个AX单元。

Windows限定检查：diffcheck PASS；六方法名称/旧XCTAssert行全部保留。新增fixture尚未Mac执行。独立patch `../AI-CLIENT01/successor-9a6f815.patch`，1133字节，SHA `203bf174f50db3d328fbcd8064fd6d4ef75a06b35e5cbf2e4f0a1caf3897a227`；与后继A窄修分开保存，实际私有index正向应用记录在对应successor-checks.json。
