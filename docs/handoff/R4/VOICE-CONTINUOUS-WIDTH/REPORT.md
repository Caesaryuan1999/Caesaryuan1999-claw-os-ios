# R4 iOS AU 连续宽度：固定源码与待运行 renderer 回归

生产固定提交 `1fa8c6b4abd993fc10ced1acc7e153e9fba162d0`，父 `60d59976d42f03359d1db1ee4025b4d9b373df18`（该父仅文档；此前生产是限时 `cb296b0f6c0f0571fc0d70f590ef916365c0dd0d`）。本目录报告与测试是后继交付，不替换原限时、B02、CI43 或旧包。

## 范围与行为

仅三生产：`Tinodios/format/FormatNode.swift`、`Tinodios/format/MultiImageTextAttachment.swift`、`Tinodios/MessageViewController.swift`。真实 AU 输出给原 `audio/toggle-play` 附件附上可选毫秒布局值；实际 `calcContentSize` 读取此类型标记，再按现有内容内边距扣除/加回一次。普通 AU 当前左右共 28pt。自然正文宽度仍参与测量，混合正文、引用、多 AU 不被强制缩窄；已编辑项原最小宽规则保留。

完整主体宽为 `128 + 96 * (clamp(durationMs / 1000, 1, 60) - 1) / 59`。先在 Int 范围夹限，后转 CGFloat，因此极大/极小整数不溢出；1500ms不先舍入秒。小屏取原实际可用内容预算加原内边距，不再套第二次0.76或0.42。类型为 AU 即使 duration=nil 也有最短目标；其他默认nil的多图附件不受影响。

未知、0和负时长显示 `-:--`：这是本次明确的显示修订，不能说 formatter 文案逐字不变。旧120秒仍显示2:00，主体目标封顶224；没有更改协议实体、历史时长或文件。1秒只是展示测试边界，iOS既有最短发送3秒未改；与Android既有2秒差异仍需后继产品一致性决定。

原24pt图标bounds、glyph点击、entity key、附件delegate、网络/VLC、录音、发送、SQLite及C3保持。扩的是消息容器，不加透明点击层。完整48pt新语音视觉、声波、整条点击均未在本包完成。普通AU owner/VLC生命周期已知缺口仍OPEN，不能把宽度交付称为播放安全修复。

原通用 `maxContentWidth(availableWidth <= 0)` 返回360的fallback未改；本包的0/非有限预算只核宽度函数直接门禁，不宣称这个旧极窄容器路径已修。实际renderer小屏为320pt，正常390pt。普通极端窄屏与整页播放待独立验证。

## 真实消费者测试准备

复用已接线 `TinodiosUITests/VoiceLayoutTests.swift`、原App-hosted `TinodiosVoiceLayoutTests/VoiceLayoutTests` selector。PBX、selector、workflow、Pod与版本均无变化；既有8方法正文不变，增加恰3方法：

1. `testContinuousAudioWidthsReachRealFormatterAndMessageCells`：真实Drafty→FullFormatter→原MessageCell→原MessageViewLayout，在390pt按收/发两侧验证1000/1500/4000/10000/20000/30000/45000/59000/60000ms的实际container/content/layout attributes及28pt差值。
2. `testAudioAddressAndPlaybackFramesNeverChangeWidthOrExpandHitTarget`：inline、mid与合成服务ref地址相同时长同宽；原附件delegate切play/pause/reset只改frame；真实RichTextView glyph命中与扩宽空白不命中。没有调用VLC或网络。
3. `testAudioUnknownLegacySmallViewportAndMixedContentPreserveRealLayout`：320pt、标准/AX最大字号、浅/深，nil/0/负/1秒/60秒/120秒/Int极值；真实混合两AU、QuotedAttachment文本/图像、再复用为普通文字。未知短目标、旧时长、可用上限和自然内容测量同时检查。

原Controller的 `loadView`、消息数据源配置、实际MessageViewLayout、MessageCell和formatter均保留；测试子类仅不运行业务 `viewDidLoad/viewDidAppear`，不设topic、不伪造SDK登录，原初态检查要求匿名且host为127.0.0.1:9。收发方向是本地合成from/myUID，不代表认证。截图是实际UIKit `drawHierarchy` 的原页面渲染组件；不是完整已登录聊天、真实音频、真手势或跨端通信。原Quote本来是QuotedAttachment，测试检查其保存的真实attributedString/image，不错误把它当顶层纯文本。

新增方法共3；此前cb296累计318 native +3 navigation只是待运行预期，本候选累计 **321 native +3 navigation**。VoiceLayout由8→11；其余旧方法和限时/账号/权限断言保持。Windows没有执行Swift/UIKit；新截图/geometry附件只有后续Mac实际运行才会产生，不预置图片。

## 实际检查与原失败保全

- `source-policies.json`：首次44脚本为43PASS/1FAIL。唯一旧 `test_message_delete_policy.py:53` 要求formatter包含voiceWidth；它原来只做guard，已经移到实际测量层。
- 总控授权只替换这一几何结构断言。`source-policies-green.json`：44/44PASS；全部删除、确认、权限断言保持。新断言核formatter传布局值、实际calcContentSize消费者和padding补偿，没有加回死helper。
- `check-source.py` / `source-checks.json`：旧8方法全文一致、三生产与固定1fa8一致，额外源仅原测试与获批策略；网络/VLC/Bar/Recorder/Interactor/PBX/selector/Pod等不变。raw SHA与Git clean blob分别记录，避免行尾含义混同。
- `git diff --check`限定本单元通过。这些均是Windows源码检查，不是Swift编译或原生通过。

CI43两次均在锁定MobileVLCKit官方下载失败，原生未启动。没有为本包推送、触发CI、改Pod锁或冒用旧Mac结果。总控统一决定后继固定候选的CI时机。

## 回退与依赖

按提交依赖先有cb296，再1fa8，最后本测试/策略/报告后继。需要回退时在新安全副本依次revert本测试后继与1fa8，保留cb296限时，不reset旧工作树、不删除未跟踪资料；无数据库迁移和协议回退步骤。源包/CI33与旧报告原样保留。本端不自行push或覆盖总控公共资料。
