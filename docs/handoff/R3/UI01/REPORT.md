# R3 UI01 — A 主题、主导航、会话与我

状态：源码候选已完成；Windows 检查通过；本批 Swift 编译、模拟器 UI 与真机验证 **NOT_RUN**。交给总控独立审查后进行免签名 Mac CI。旧 R2 SDK 26 / DB 45 结果不属于 UI01 验证。

## 起点与范围

- 独占目录：work/r3-20260918-ios，分支 codex/r3-20260918-ios。
- 起点：34a8b3e5ad4df210117e2e03b308576796ba55b2，建立时 clean。
- 依据：总控确认 DESIGN_SPEC 顶部 R3.D1、COPY_GLOSSARY 与 PAGE_STATE_MATRIX；会话 Figma A 9:147 的已回读设计上下文。
- **10 个生产文件 + 5 个既有源策略文件**。策略只更新被 R3.D1 明确替代的旧数值/文案断言，保留可靠性策略和状态断言。
- 不修改旧 integration / verify 树、SharedUtils 私有配置、SDK、DB、C3、发送、通知隔离或认证逻辑。
- 身份批次独立实施；UI01 不是新的手机号/邮箱认证交付。

## 精确生产文件与页面映射

| 文件 | 入口 / 行为与设计映射 |
|---|---|
| Tinodios/Utils.swift | ClawTheme 接入 R3.D1 十组浅深语义颜色、12 按钮圆角、16 卡片圆角、48 通用触达尺寸和 UIFontMetrics。非主题辅助代码与起点完全相同。 |
| Tinodios/NewChatTabController.swift | 主导航仅消息 / 通讯录 / 我；通话类与旧新聊天选择器完整保留。 |
| Tinodios/ChatListViewController.swift | CLAW OS 品牌、消息页标题、发起聊天按钮；搜索会话只过滤既有名字/alias；无结果和空列表分开提示；自适应行高。 |
| Tinodios/widgets/ChatListViewCell.swift | 84 最小卡片、10 间距、48 头像、16 圆角、两行预览、动态字体、24 最小未读徽标和选中反馈；发送标记保留 deliveryMarkerIcon。 |
| Tinodios/widgets/ChatListViewCell.xib | 只改头像宽高 54→48 与未读徽标高 18→24，不改 outlet 或状态绑定。 |
| Tinodios/FindViewController.swift | 搜索联系人、CLAW 号术语、添加按钮可访问名称、84 行高；旧未核实下载链接改为邀请链接尚未配置提示。 |
| Tinodios/AccountSettingsViewController.swift | 我 → 个人资料 / 通知 / 账号与安全 / 帮助；公开卡片只展示/复制已有 alias/basic 标签的 CLAW 号，不显示私有 UID 或邀请码；资料未加载阻止空数据进入。 |
| Tinodios/AccountGeneralSettingsViewController.swift | 唯一修改为个人资料标题，昵称、头像、凭据处理不变。 |
| Tinodios/Base.lproj/Main.storyboard | 两个既有 segue 命名 Chats2NewChat / AccountSettings2Help；目标、连接和场景不变。 |
| Tinodios/SettingsHelpViewController.swift | 保留真实版本、当前连接诊断；条款 / 隐私 / 支持未配置时明确说明；本机许可只展示打包清单，失败明确提示。 |

## 行为边界

- 通话只从主导航移出，未删代码、数据、协议或会话内通话能力。
- CLAW 号仅是现有公开别名的显示名称，不使用 UID、手机号或邮箱作假替代，不生成新标识。
- 发起聊天复用既有选择器，搜索不是正文全文搜索。通讯录和活跃联系人算法不变。
- 退出确认说明本机待发/待确认保留，继续调用 IOS04 既有退出路径，不改变会话代次与账号隔离。
- 未核实的 veilping 域名与 support 邮箱不再从本批帮助/邀请入口跳转；未编造条款、隐私政策、支持邮箱或分发页。
- 既有使用 ClawTheme 的次级页继承新色值；不代表所有遗留 fixed-frame 控件已适配深色和最大字号。
- 聊天气泡、输入栏、附件属于下一独立 UI02。

## 验证与证据

- policies-before-update.json：新 UI 遇旧设计断言，33 脚本中 28 通过 / 5 失败。
- 5 个策略文件仅改旧颜色、尺寸与文案；认证、C3、删除、通知、账号和联系人会话断言保留。
- policies-final.json：python -X utf8 Scripts/ci/run_static_policies.py **33 / 33 通过**。包含源策略和 Windows SQLite 镜像适配器，不是 Swift/UIKit 执行。
- scope-and-hashes.json：8 项检查通过：恰 10 生产文件；SDK/DB/认证/消息实现无 diff；非主题 Utils 和通话/新聊天类完整保留；Storyboard 仅两个 segue 命名；XIB 仅三个尺寸；帮助/邀请无旧未核实域名；集中发送标记入口保留。列出全部 15 个变更源码/策略原始字节 SHA256。
- Storyboard / XIB 实际 XML 解析并和基线对比，git diff --check 通过。
- 首次 runner 未带 -X utf8，Windows GBK 使失败报告打印异常；随后带参数完整记录，未改 runner 或关闭断言。

## 后续 Mac / UI 验收

1. 精确提交免签构建与既有 SDK / DB 用例，不将源策略当 Swift 编译证明。
2. 小屏、标准屏、横屏、大字：三个标签、发起聊天、搜索键盘、长昵称、未读 99+、空列表与无匹配跳转。
3. 浅深色与 VoiceOver：按钮名称、CLAW 号复制、发送标记、我页高度和资料未加载、帮助入口。
4. 检查 pod install 后打包许可。继承 Acknowledgements.plist 含 XML 不允许的控制字符，Python plist 解析失败；Podfile 第 63 行会复制 Pods 实际依赖清单。本批不改资源、不宣称当前清单可解析，UI 保留明确失败反馈。
5. 真机、APNs、正式签名、auth live 均未执行。本批未发布、推送或远程触发 CI。
