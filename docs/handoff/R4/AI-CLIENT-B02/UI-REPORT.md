# B02 UIKit 固定候选

状态起点 `4c1fecbfc320e85d11e5eb81b8481ed4d1f7e1b2`（五状态文件与 13 方法保持）。本批仅三生产页、一个新增布局测试、原 PBX membership 与单行 selector。分支 `codex/r3-20260918-ios`，origin 为自有 `Caesaryuan1999-claw-os-ios`。提交前观测 tracked 5 / untracked 19792；新增测试和本报告按白名单显式加入，其他未跟踪资料不动。

## 实现范围

- `ClawAssistantViewController.swift` 中共享 Page：每页 UUID reader lease，实际导航 top/window/前后台门禁；离页取消读取而不 stop。旧页释放只带自身 lease。跨会话停止未知在改变 selected conversation 前显示原回答入口；401 仍只隐藏助手 scope，不注销账号。
- `ClawAssistantHistoryViewController.swift`：真实行入口调用上述门禁；保留原列表、删除和拒绝反馈。
- `ClawAssistantConversationViewController.swift`：复用真实 message ID 行；只向已有回答行叠加权威 Run 投影。停止等待、未知、真实终态、legacy 与分类错误各有实际状态；“查看原回答状态”和“再次停止回答”分开。新问题发送继续禁用且未接动作。
- 同一 UIScrollView 在正文增量、字号/宽度/键盘变化前后保存真实行 ID 与像素距离；原底部跟随及显式“回到最新”可定位底部。不新增未读数。52pt 动作、动态字体、A 浅深色及原平台导航保留。

设计来源为唯一 Figma `CreMqit00K1MAJju69YoOv` 的 `275:1355`、`278:1436`、`275:1384`，已调用 design context；以冻结 B02 业务限制裁剪未开放的生成/重试回答，不把设计节点视为运行结果。紧凑语音后继不在本批。

## 五个新增实际消费者方法

1. 320pt、AX 大字号与浅深：实际 Page/Run 控件、52pt/标题容纳、scroll 后真实 hitTest，generation=true 仍无 POST。
2. 真实导航离开、stop 超时未知、跨 cid 弹窗、返回原回答、只读恢复、显式再次 stop，200 completed 仍显示“回答已完成”。
3. 真实长正文行身份与像素锚点、增量、字号、“回到最新”、实际键盘 frame notification 与出现/收起；不以 input first responder 或原有底部 inset 单独证明键盘出现。
4. legacy 与 completed 历史不出现停止或重试生成控件。
5. 真实 HTTP 401 隐藏旧页、新 scope 读取、旧页受控 appearance 回调不释放新 lease。

测试复用原 `AssistantFixture` / `AssistantBFixture`，由 URLProtocol 控制传输；Session/History/Run、隔离 SDK/SQLite 与 UIKit 类实际执行。没有真实服务、模型、账号登录或聊天发送。UIKit 在中性 320pt 容器内挂真实导航/页面；跨 cid UIAlert 的真实呈现/文案可测，没有私有方式执行 UIAlertAction handler；随后通过真实历史行回原页。旧页 appearance 为受控回调，不冒称用户真实返回手势。slot gate 沿原 fixture 注入，不称真实 Cache 登录流程。每方法保留 keepAlways 原 PNG/几何 JSON，内容均合成。

## 检查和证据等级

`check-ui-source.py` 核六代码白名单、21 个继承 Swift 测试文件及五状态源的固定 Git blob 不变、单 selector 和既有 target membership；`ui-source-checks.json` 分列 raw/LF SHA 与 clean blob，避免把混合行尾当 Git 原字节。44 个现有源码策略通过，diff --check 通过。以上均为 Windows 源码检查，未运行 Swift 编译/原生测试。

累计候选预期为继承 295 + 状态 13 + UIKit 5 = **313 native + 3 navigation**。原 2e/CI43 两次均因官方 MobileVLCKit 下载失败而未启动原生；本窗口未推送、未派 CI。B02 集成与可用结论仍等待 B1 原生门禁、独立固定源审与总控精确候选 CI。不能将本报告算作界面、停止或真实服务通过。

## 依赖与回退

顺序依赖 `2e758c` → `2d0feec` → `4c1fecb` → 本 UIKit 提交；原包与红证据不重封。获批 Mac 环境使用原 `verify_publish_outcomes_macos.sh`，仅追加 `TinodiosVoiceLayoutTests/AssistantKnownRunLayoutTests`，原方法/断言/超时/其他 selector 不变。root 负责精确 SHA 推送与 CI。

若需撤回本 UI 批次，在独立分支对本提交作 revert，先保留现有工作；状态两提交可独立审查，不通过 reset/clean 丢弃资料。本批无 wire/schema/SDK/数据库/Keychain/Pods/workflow 变化，不需要数据迁移。跨进程 journal、真实生成、客服提交仍未开放。
