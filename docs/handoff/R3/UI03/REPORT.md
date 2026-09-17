# R3 UI03 — 通讯录 / 我 / 个人资料

基于独立 PUBLIC 62ce847 与编译修正 ae88055。6 生产文件，2 个既有源码 UI 策略更新；无新 Swift 方法，累计 native 期望仍 110。Windows 未编译 Swift、未执行 UIKit。无 SDK、DB、AUTH 服务、C3、Main.storyboard、私有配置改动。

使用 figma-design-to-code 技能，已实际 get_design_context 并检查返回截图与代码：file CreMqit00K1MAJju69YoOv，通讯录43:91、我23:120、资料52:304。随后采纳总控补充邮箱78:1603：无箭头、无绑定编辑；CLAW号只复制。使用 D1 UIKit 动态色/系统字体，现有 SF chevron/search/navigation 图形与设计同含义轮廓，头像仍来自实际资料。未将 Figma 样本人名/电话号码写入 App。

| 文件 | 实际行为和设计映射 |
|---|---|
| FindViewController.swift | 替换旧活跃联系人横条；独立 添加联系人→真实 fnd 搜索、发起群聊→既有 NewGroup。联系人副标题优先公开 CLAW号；保留本机/远端结果、保存成功后进聊天、错误/空状态及文件助手。 |
| ContactViewCell.swift / xib | 48头像、16主文字/13副文字、D1卡片/间距、自适应联系人行；保留所有 outlet、选择 delegate、角色徽标。94最小行高与底边约束为750，兼容其余既有70高成员选择行，不触其他业务页面。 |
| AccountSettingsViewController.swift | 64头像/20昵称/编辑资料卡；真实通知、账号安全、关于帮助路由；CLAW号复制；隐藏旧Storyboard行且清空UID/邀请码文字。外观只读显示跟随系统；未伪造尚无功能的隐私设置入口。退出仍调用原账号会话门禁。 |
| AccountGeneralSettingsViewController.swift | 重用Storyboard真实输入、头像按钮和保存API，放进自适应表头；昵称、简介、头像保存，按钮防重复提交/失败恢复；公开CLAW号复制；实际tel/email分别显示已验证/未验证或未绑定，无虚拟号码。移除旧alias编辑检查；AUTH4只读和禁止删除保留，未新增bind API。 |
| Utils.swift | ClawProfileLayout统一只读资料行、Dynamic Type标签与表头自适应。PUBLIC解析和身份桥接独立提交语义保持。 |

路由边界：通讯录实际目录检索，主消息页仍是搜索会话；文件助手与完整通讯录保留。新头像/昵称/简介仍调用原API，未修改权限。导航大标题仅本页使用，离开恢复，避免影响聊天等页面。资料页不再打印输入文本。

验证：34/34 源策略通过；XIB XML可解析，ContactViewCell全部outlet/集合字节属性一致；资料5个IBOutlet和2个Storyboard action均有真实实现。初次32/34失败是旧脚本强制存在已批准替换的活跃横条/旧88头像，保留static-before-policy-update.json；两脚本改为检查新独立动作/真实路由/64头像，其余群聊、通话、R2和身份检查保留。未新增无意义镜像测试。

待Mac：完整App与依赖编译，现有110原生回归。待UI验收：小屏/大字/横屏的布局、VoiceOver、真实资料/联系人加载、搜索拒绝/离线恢复、头像权限、保存失败及页面返回。主题与源码接线不代表全页面视觉或真机验收完成。法律/短信/邮箱正式资源与真服务未由此批解决。
