# CI38 普通字号标题被跨年时间挤压

源提交 `b004af0d5c5d8ce2f7560fad04ed8711694c8e23`，父 `e9eba400129c734315e8176d00e5b2a52e2bc74f`。仅 `Tinodios/widgets/ChatListViewCell.swift` 和 `TinodiosUITests/CoreListLayoutTests.swift`，未混 B、formatter、XIB、SDK、DB 或 CI。

## 原件与根因

CI38 Core 六方法通过，但总控和本端独立读原图/JSON均确认视觉缺口：根目录 `artifacts/integration/20260919/R4-ios-ci38-native-review/11AF4BC5-3DE8-46C7-A447-C67B474514AE.png`，配套 `338C92A4-58AE-485B-A841-7EB07BAD9564.json`。320pt、Large 时标题 font16 / width27 / height114.6667；完整跨年时间 width161。六个汉字逐字竖排，badge 已正确 28×24。六方法绿不能代替画面验收。

测试仍用 ts=1700000000，走真实 `RelativeDateFormatter.shortDate` 的跨年 medium 日期+时间。不是夹具直接注入长时间字符串。normal titleRow 水平，时间压缩抗性 required，标题250且连续模式不限行，因而时间占据空间，标题折成六行。没有把未知无名 badge 高度约束推断为此问题原因。

## 最小修正

只在 continuous 的非 AX 模式限制 timeRow 不超过标题行一半；时间单行尾截且压缩抗性249，标题保留至多两行。完整时间字符串和 cell accessibilityLabel 原样保留。AX 仍为纵向、标题自然增长不限行，默认旧 card 消费者保持原布局策略。原头像/未读/状态/数据语义未改。

原六方法和 96 行已有 XCTAssert 均保留，原3秒/真实旧 timestamp 不变。在原 XIB 标准初始及 AX→Large 浅/深两色路径增加实际字体的四汉字最小有意义宽度、标题至多两行、时间预算/单行/完整读屏文字、实际 frame 不重叠检查。原 PNG 与 geometry 继续输出，新增 labelLines/lineHeight/compressionHorizontal 数值；没有生成示意图代替运行画面。

## 证据边界

`CI38-title-checks.json` 源保留检查、`CI38-title-static.json` 44/44 策略、diff --check 通过。零新增方法，累计仍为 B 后继预期293 native + navigation3。实际 UIKit 约束、CoreText 和新画面 **NOT_RUN**，不得把 Windows 策略或 CI38 的旧源结果算作本修复运行通过。

独立两路径 `core-title.patch` 和真正临时 index 正向还原全树/mode/blob/SHA 证据在 `../AI-CLIENT-B01/successor-manifests.json`。原 CI38 原件和之前 CORE 修复报告保留。
