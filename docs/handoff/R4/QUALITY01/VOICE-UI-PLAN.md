# QUALITY01 — iOS 紧凑语音视觉：只读方案，待总控冻结

基线 `600be3abd889fe2a2957e48129759e933fc407d6`；普通 AU 生产 `01d34caba9f73353e9fc60e350ae3484e7f5bbdd`。CI44 正在对该不可变基线运行，方案未修改生产或测试。录制 60 秒、连续宽度、owned Data 播放器均继承；不改传输、权限、数据库、录音或播放器格式策略。

## 已核来源和差距

- 唯一规范 `docs/design/r2/DESIGN_SPEC.md` 顶部 v4：真实 ms 连续宽度，主体 128→224，48 最小高、16 号时长、16×20 声波、8 圆角、尾角不计主体宽。浅深 A 主题。
- 已实际读取 Figma `CreMqit00K1MAJju69YoOv / 338:1670` design_context，10 个收发/状态变体及原图。组件本体是 48 高；读取时子 variant 遗留描述为 54。总控随后已修 10 个描述至 48，几何/宽度/原型未变（root quality01-voice-description-fix.json），本方案按当前规范。
- `format/FormatNode.swift:362–402` 当前仅 24pt 扬声器图片 + `m:ss` 文字；`MultiImageTextAttachment` 只有帧 index。`MessageCell.swift:229–249` 内容空白与气泡边缘不播放。
- `MessageBubbleDecorator.swift:21` 仍为所有普通消息的无尾 18 圆角，不能为语音把其他文字消息一并改外观。
- `MessageViewController.swift:1561–1627` 已真实接线连续宽度/28pt 水平 padding；不得再次乘 0.76 或重做限时。
- `MessageViewController+MessageCellDelegate.swift:269` 的 `didChangeAudio` 已持原 owner/attempt/entity 门禁，但只调用旧附件 play/pause/reset。真实 `ClawAudioPlayback.position` 可供 UI 绘制；不得用装饰波形或定时器虚增进度。

## 精确生产白名单：7 实体，3 Swift + 4 原图资源

| 仓库相对路径 | 限定职责 |
|---|---|
| `Tinodios/MessageCell.swift` | 同文件增加私有 UIKit 语音控件，真实 UILabel/UIImageView/细进度条；cell 绑定、复用重置、整主体触控、VoiceOver；不另建 target 或页面 |
| `Tinodios/MessageViewController.swift` | 纯单 AU 资格和测量/配置；复用原 duration 宽度；48 最小高与 AX 自然增长；仅纯单 AU 去旧 mask 并配置 8 圆角/独立尾角，其他消息原 decorator 保持 |
| `Tinodios/MessageViewController+MessageCellDelegate.swift` | 整主体动作仍进入 `ordinaryAudio(in:key)`；受控真实状态/position 更新同一 cell；复用现有错误与下载原文件动作，不增加下载入口能力 |
| `Tinodios/Supporting Files/Assets.xcassets/claw-voice-wave.imageset/Contents.json` | exact Figma 声波资源 catalog，template/矢量配置 |
| `Tinodios/Supporting Files/Assets.xcassets/claw-voice-wave.imageset/voice-wave.pdf` | 从当前 Figma 声波节点原样导出 PDF，左右镜像复用，不手绘相似图标 |
| `Tinodios/Supporting Files/Assets.xcassets/claw-voice-tail.imageset/Contents.json` | exact Figma 尾角资源 catalog，template/矢量配置 |
| `Tinodios/Supporting Files/Assets.xcassets/claw-voice-tail.imageset/voice-tail.pdf` | 从当前 Figma 尾角原样导出 PDF，按主题 tint/收发镜像；独立于主体宽度 |

现有 asset catalog 自动编译新增 imageset；不需 PBX/Pod/selector/workflow 修改。播放/准备/暂停/失败图标采用已存在 UIKit 控件或确切同形系统图标，常态声波使用原图。若导出不能产生合法原生 PDF，先报告具体资源依赖，不擅造资源替代。

## 资格、测量与回退

仅非删除、非上传草稿的**完整内容恰为一个 AU 实体及其占位空白**启用整泡控件。不得从“包含 AU”推断整条消息可播放；引用、可见文本、链接、多个 AU、未知样式或其他附件保持原 RichTextView/实体点击路径。资格由实际 Drafty 内容和实体 key 核对，不看文件后缀、不猜昵称/UID。整泡只改变同一 AU 已有可调用入口，不扩大下载或播放权限。

纯单 AU 控件替代该 cell 的可见 RichTextView 内容，但保留原缓存/Drafty 对象供原 owner/entity 消费者使用；复用、变成普通文本、删除或选择态时必须撤销控件绑定并恢复原内容。引用和混排不声称已实现整消息点击。

主体宽仍取原 `MessageBubbleLayoutPolicy.voiceWidth(durationMs:maxWidth:)`，先满足真实时长/图标/AX 内容需要，再限可用宽。无二次固定缩放；padding 只计一次。纯 AU 主体高度 `max(48, 实际字体行高 + 垂直留白)`；时间/回执仍在原主体外，不算入 48 触区。尾角在主体外独立 5pt 左右空间，调整 cell 可用边距避免近屏边裁切，不能把尾角计入 128→224 的主体公式。

新可见时长使用已确认秒数样式（如 `4″`），保留现有毫秒转显示秒的向下取整含义；宽度仍用未取整 ms。未知/非正保持 `-:--`，不虚构 1 秒；历史 >60 显示真实累计秒数（例如 `61″`），仅宽度封顶；不使用 Float/Int32 换算造成极值溢出。

## 状态、交互与可访问性

- Ready/Ended：声波 + 单一总时长，触发原受控播放；Paused：真实暂停标识，点击原位置继续；Playing：真实 position 的细进度，不重复已播文字、不用播放位置改变宽度。
- Preparing：真实准备指示，无自动重复请求；Failed：失败标识，点击仍进入现有受控恢复和中文原因；不画“已下载”“已听”或未播放圆点。
- 回调必须先满足原 owner/page/cell/key/attempt 条件；这里只消费状态，不改 `ClawAudioPlayback` 引擎、250ms 检查或资源责任。
- 上传取消、批量选择、删除和长按原优先级必须高于播放。批量选择点击整泡只切选择，不启动音频；长按仍原菜单。其他气泡/头像点击不外扩到播放。
- VoiceOver 使用真实按钮语义、总时长和状态/下一动作；不把 Ready 标成“未听”。AX 使用 `ClawTheme`/UIFontMetrics 字体，内容不足先自然增宽/增高，不整体缩小字体；浅深/收发方向分别验证。
- 平台依据：[Apple 触控区域](https://developer.apple.com/design/tips/) 建议至少 44×44pt；本设计采取更大的 48pt 下限。[UIFontMetrics](https://developer.apple.com/documentation/uikit/uifontmetrics) 用于动态字体，不能用固定屏幕字体替代。

## 原生验证与图像

沿既有 `TinodiosUITests/VoiceLayoutTests.swift` 和 App-hosted `TinodiosVoiceLayoutTests` 接线，保留现 17 方法及原六 AU 可靠性断言；新增真实消费者方法数量待冻结测试清单，不凑数。至少覆盖：

1. 原 MessageViewLayout/MessageCell 的纯 AU、收/发、浅/深、1.5/4/30/60/>60/未知时长主体几何，48触区、尾角不裁切、显示文字和 128→224 原公式；320pt 与 AX 自然增长。
2. 真 cell 的整泡空白区、文字、图标 hit/原 toggle action，混排/引用/多 AU 回退，选择/长按/上传优先，复用到非 AU 后无残留点击能力。
3. 由真实 AVAudioPlayer/data 及现有 owned consumer 提供播放/暂停/结束/定位进度，状态不得伪造，不用独立 UI 模型代替原 player；权限/退役和晚回调沿旧六方法。

每个关键视觉场景保存原始 PNG 与同拍 geometry JSON（主体/尾角/文字/图标/状态/actual position，无账号秘密）；明确中性 fixture、真实组件、真实播放器与完整聊天/跨端/真机的不同层级。CI44 当前六方法没有新增 cell PNG，只有真实 AAC/playlist 与 JSON；其旧 VoiceLayout 截图和成功冷启动图可作为当前固定版本的有限证据，不冒称新增控件已运行。

本提案只是只读定位。CI44 失败优先处理具体红证据；未获本白名单冻结前不改生产。客服、未播放点、AI journal、跨进程政策继续未决，不夹带实现。
