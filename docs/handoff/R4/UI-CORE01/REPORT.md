# R4-UI-CORE01：连续列表与紧凑我页

本单元只改变 UIKit 展示。源码基线为 `94af9225091278d676fca0f1eb13ca9e8a30dac2`；生产提交 `a2db7d1f1413370b67f7140f1189da068a60b21e`，后继测试候选 `c84ab98db11685a656dfe483cd1db59c055fd81e`。文档提交不是新的生产版本。独占分支 `codex/r3-20260918-ios`，origin 为既有自有 iOS 仓库；本轮没有 push 或 CI dispatch。

## 已落地与设计依据

已用 figma-design-to-code / figma-use 读取同文件 `CreMqit00K1MAJju69YoOv` 的真实 design_context 与截图：iOS 消息 `272:1296`、联系人 `261:1235`、我 `258:1193`。沿用 UIKit、ClawTheme、UIFontMetrics，未引入新图像、Web/SwiftUI 或新主题。

| 生产文件 | 本次行为 |
|---|---|
| Tinodios/ChatListViewController.swift | 单一原生“消息 / 发起聊天”栏；保留真实“搜索会话”本地名称/alias过滤；隐藏活跃联系人横条展示，但原构建数据、排序/在线信息及隐藏渲染代码保留。连续会话 cell 显式 opt-in。 |
| Tinodios/widgets/ChatListViewCell.swift | 使用原 XIB 与 fillFromTopic，连续行边界/头像48/分隔线，未读与时间同组；AX标题组垂直增长。默认卡片与复用回退保留，布局对象未就绪时守卫。 |
| Tinodios/FindViewController.swift | 原生“通讯录 / 添加联系人”栏、真实搜索与发起群聊入口；联系人 cell 显式 opt-in；查询、远端结果验收、保存/权限逻辑未变。 |
| Tinodios/widgets/ContactViewCell.swift | 原cell约束参数显式切换连续行，默认旧卡片/选择delegate仍可用；复用撤回opt-in。 |
| Tinodios/widgets/ContactViewCell.xib | 仅连接六个既有约束 outlet，默认约束值/资源/原出口不变。 |
| Tinodios/AccountSettingsViewController.swift | 56pt头像与昵称/编辑同排、CLAW号与明确“复制”入口、紧凑区块；AX可增长。外观仍是只读“跟随系统”，原关于/帮助内容与路由保留。 |

原生导航适配差异：两个动作遵循44pt系统导航栏，不照抄Figma48pt头部按钮；单行文本用UIFontMetrics并限制导航字号上限20pt，正文与列表仍完整AX增长。导航标题沿原平台居中；不新增第四导航、助手/客服假入口、联网模型或模拟回复。

## 准确文件范围

6生产 + 6测试/接线：
- 新 `TinodiosUITests/CoreListLayoutTests.swift`。
- `Tinodios.xcodeproj/project.pbxproj` 仅接入现有 `TinodiosVoiceLayoutTests` App-hosted Sources。
- `Scripts/ci/verify_publish_outcomes_macos.sh` 唯一一行新增 `-only-testing:TinodiosVoiceLayoutTests/CoreListLayoutTests`。
- `Scripts/ci/test_chat_list_branding_policy.py`、`test_active_contacts_layout_policy.py` 只适配已批准的新标题/展示结构。
- 总控追加批准 `Scripts/ci/test_premium_secondary_ui_policy.py` 仅原头像高度期望64→56，其余断言逐字保留。

未改变原242个原生测试、3导航测试、workflow、Pod/版本、SDK、DB、协议、发送/存储、SharedUtils私有配置与历史封包。初始19782个未跟踪文件保留；本端仅新增交付文档和本批测试，未清理目录。

## 验证与真实边界

Windows 实际：
- 44源策略先43 PASS/1 FAIL（旧64pt断言），`static-policies-red.json` 原样保留；批准窄修后44/44 PASS见 `static-policies-green.json`。
- 三个原策略的Git原字节对新布局独立执行均失败，见 `old-policy-red.json`；这是旧设计规则冲突，不能称原生红测。
- 17个原数据/搜索/显示/副作用方法全文对照不变；6 XIB出口目标均存在；PBX成员与脚本唯一selector差异核对，见 `bounded-checks.json`。
- 源清单的12路径 raw SHA256、Git blob/mode/SHA256和clean-filter一致性见 `SOURCE-MANIFEST.json`。raw CRLF与Git LF分别标注，不冒充同一字节。
- 两提交 diff --check 通过；生产文件未运行Swift编译。

新增6个原生方法，下一准确期望为 **248 native（44 SDK + 204 storage/App）+ 原3 navigation**，全部新方法当前 **NOT_RUN**：
1. 原会话XIB、真实Topic/StoredMessage/Drafty预览及未读数据、opt-in/复用、真实消息页面搜索消费者；标准/AX 320pt导航动作布局。
2. 原联系人XIB、选择delegate、连续与默认卡片/复用。
3. 原共享XIB在320pt、最大AX与浅深主题下字体/自然高度/文字几何。
4. 原Find storyboard和真实displayLocalContacts消费者：公开alias、缺资料、空态、真实导航按钮及群入口；业务port受控，不发目录请求或保存。
5. 原我页storyboard/真实reloadData + 合成内存me Topic：资料未获取与公开alias优先、只读外观/既有帮助边界。
6. 相同账号合成内容在标准→AX自然增长、contentSize覆盖header、必要时真实滚动至末端并检查退出按钮可见/文字无裁切。没有“必须大于屏幕”的虚构高度要求。

测试不连接真实服务、不登录、不触发通讯录授权或读取、不点击发送/复制/退出。Find系统同步依赖在fixture内设denied，拒绝既有authorized初态；teardown只清本fixture匿名SDK的定时器和内存topic并还原原值。原生UI控件和原数据展示方法是真实的；业务依赖/合成资料仍是受控输入，不能称认证后全旅程、真实目录/通讯或设备可用。

测试保存原UIKit绘制PNG与仅合成几何JSON（keepAlways），复用现有storage附件导出。图像与实际导航/AX布局必须在后续精确Mac CI采集并由总控查看；Windows策略不能替代截图/VoiceOver实际朗读或真机。

## 后继测试审查

总控对 a2db 的第6方法提出“AX内容必须比视口高”并非产品要求。c84 只修改该方法：与同内容标准字体比较自然增长、验证contentSize覆盖header，超出可见范围才滚动，末端动作与文字必须位于真实viewport。保留原6方法数量、尺寸/正文无裁切断言与3秒deadline；其他5方法和6生产文件不变。

## 依赖和回退

总控/独立审查固定 c84 后才推现有获授权验证分支并执行准确Mac CI。旧CI33与旧交付包继续只证明旧生产b098，不升级为本R4证据。

只接受此R4展示单元回退：在新的独立审查分支，先撤销 c84 测试提交，再撤销 a2db 展示提交，回到94af代码；确认无本地未提交改动后由总控决定操作，当前未执行回退。此单元没有数据库/协议变更，无需迁移数据库或删除本地内容；不能将此说明用于回退更老的不兼容C3二进制。

本次不重封旧09631/e30/6c0包、不安装App、不删缓存/数据库、不写共享台账。源码恢复/原生构建/真实服务与设备验收各自分层。
