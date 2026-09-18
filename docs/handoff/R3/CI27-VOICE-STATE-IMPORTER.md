# CI27 VoiceLayout state 导入兼容修正

- 失败基线：`d45cbeacda88b0d7c9a371c95579e63d60153f82`，CI27 run `35351962458` / job `105621991726`。
- 总控实际读取 13:51:15Z Mac 日志：`VoiceLayoutTests.swift:379:18: cannot override mutable property with read-only property 'state'`。SDK 44 PASS；其余 UI/VLC/组件/导航/打包/冷启动 NOT_RUN，不把编译前阶段记为通过。
- 原 artifact `10551185734`，总控提供 810,299 字节、SHA-256 `321c37ab68f7146618e371f3cdade573c2dc174cbd03303fddc4e05fc7c06c5f`；由总控保全，本单元不重复下载或替换原失败。
- 先前仅凭 API 文档不能确定 runner 的 Swift 导入声明；该疑点当时未改动，现已由实际 Mac 编译失败确证，不能继续称仅猜测。

唯一测试源码变化：`TinodiosUITests/VoiceLayoutTests.swift` 显式 `import UIKit.UIGestureRecognizerSubclass`，将受控手势 `state` 改为 `get { phase }` / `set { phase = newValue }`。主 `UIKit` import 保留；显式 subclass 模块表达手势子类所需可写接口，不能把“未 import 子模块”单独说成已证全部根因。测试仍以受控 phase/location 调用完整真实 handler，不冒称 UIKit 触摸识别。

Windows 五项精确检查全通过，结果在同行 JSON：仅两处获批改动；六方法、全部原断言及其它字节反向还原一致；生产代码和 PBX/Podfile/lock/selector 无差异。没有执行 Swift/UIKit，也没有新增镜像 XCTest 或放宽断言。

下一精确候选仍期望 232 native（SDK44 + UIrunner175 + VLC7 + 组件6）及独立导航3；真实结果留待总控 CI28。原 CI26 的 226+3 通过不覆盖新增组件六方法。
