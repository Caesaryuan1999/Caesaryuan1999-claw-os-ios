# HELP-CLOSED01

基线 `1cb083b150717d48c6b515300db2a831414eabb0`，分支 `codex/r3-20260918-ios`。本次仅2生产文件、1既有测试文件与本端交接文档。CI42仍绑定原1cb；本后继未推送、未运行macOS。B02、生产网络、账号状态、协议/DB、诊断源、Storyboard、PBX、selector和workflow均不改。

## 实际页面与改动

- `AccountSettingsViewController.swift` 只有本入口显示文字“关于 CLAW OS”→“帮助与客服”。仍调用原 `openHelp` / `AccountSettings2Help` segue。
- `SettingsHelpViewController.swift` 原帮助行虽然无外部地址，仍安装3个tap手势并弹“未配置”提示，且行高只按单行计算。现标题“帮助与客服”，原客服行静态展示“客服服务暂未开通”和“客服将协助处理账号使用问题。服务开通前，暂不接收留言。”；条款/隐私保留未配置说明。去掉3个手势和旧动作，行不选择、不带箭头、不带button/link读屏语义；原诊断说明也移除Storyboard遗留link trait。没有留言输入框、提交按钮或假客服。
- 同一3行使用当前trait的UIFontMetrics字体、多行换行和当前可用宽度测高，字体/宽度变化重新布局；不压缩字体或固定单行高度。原品牌Logo、CLAW OS、版本、连接诊断、可选Powered By及开源许可保留；许可方法逐字未改。Powered By余量按实际行高重新统计，避免新说明增长仍使用旧高度。

## 检查层级

Windows执行3个既有源策略：`test_brand_ui_policy.py`、`test_premium_secondary_ui_policy.py`、`test_secondary_ui_policy.py`，均退出0；`git diff --check`通过。`source-checks.json`记录11项固定差异/原断言保留检查和源码SHA。辅助文本与修改源统一UTF-8/LF。

Core仍是原6个方法：前4个正文逐字相同；账号两方法保留原布局、账号、CLAW号、外观、滚动等断言，仅把旧“不存在帮助与客服”改成已授权入口存在，并追加真实入口target/action→原Storyboard帮助页检查。320pt标准浅色及最大AX深色检查说明完整、行内无裁剪、静态读屏/无tap/无输入控件；标准模式派发原开源许可按钮，检查真实本地许可页面/内容可达。保存原生PNG/几何附件。保留原3秒门限，没有增加测试方法、目标或模拟客服。

这些原生断言尚未执行；当前只有源码检查，不能称Swift编译、Dynamic Type布局、VoiceOver手势或许可导航已经通过。累计仍期望 **294原生+3导航**，CI42结果由总控独立收取，不能扩到本后继。

## 复验和回退

后继固定Mac候选沿现selector执行原Core6方法；人工可从我→帮助与客服，在浅/深色、较大字体及旋转后看完整关闭说明，确认静态三行不导航，开源许可仍打开本机资源。客服仍未开通，不承诺响应或时效。

本单元无数据迁移。需要源码回退时，在保全任何后续工作后仅对本提交执行 `git revert <本单元提交SHA>`，由总控审查后重建；不要reset/clean或覆盖当前资料。也可在独立工作树从基线1cb查看原页面。不能将源码回退等同已安装包替换，不覆盖既有CI包和原诊断失败证据。
