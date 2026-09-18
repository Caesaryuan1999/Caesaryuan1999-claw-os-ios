# R3-IOS-VIDEO-UI 实施报告

日期：2026-09-18。独占路径：C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios；分支 codex/r3-20260918-ios。
生产基线 74075fec5334a1e2325b2b194974828afdd6f2f3；本单元起始 HEAD 8ea07991ccb35dbe3f16378d5235a5f6f5124e4f（只读计划），dirty=0。总控已批准两生产文件及定向既有策略更新；本机不推送、不触发 CI。

## 完成与边界

- 生产恰 2 文件：Tinodios/VideoPreviewController.swift、Tinodios/Base.lproj/Main.storyboard。storyboard 只改 MGh-dV-dd1 / gfT-SI-43h 场景，场景之外逐字节归一比较一致；ShowVideoPreview 和主导航不改。
- 验证接线 1 文件：Scripts/ci/test_media_attachment_policy.py。另新增本目录报告、source-checks.json、static-policies.json。
- 没有新增原生方法、没有修改既有原生断言/选择。下一候选仍 SDK41 + storage155 =196；另真实 App 离线身份导航3。CI16 对740的 SDK41/storage155 实际已通过（总控通知），整轮尚待总控封证；不能算本 UI 候选已编译或已运行。

## 设计与可见功能

实际读取 Figma get_design_context 并核图：160:1886 暂停、160:1920 播放、158:1888 无效源恢复、166:1918 有效原文件仍可分享的播放失败。只复用设计布局/文案与现有 ClawTheme，无示例视频/文件名/时长/大小植入，无新字体/图标库。

- A 动态浅深背景、原生导航、24pt内容边距、20pt纵距、12pt圆角；视频画布保持黑底。UIScrollView 的 contentLayoutGuide/frameLayoutGuide 约束包住实际内容，横屏/短屏可滚动。
- 播放、暂停、重新播放、声音和分享为中文文字按钮，最小52pt。按钮高度随实际字体量测增长；小于350pt宽或无障碍字号改纵排，避免强制104pt固定宽。时间/错误/文件名可多行；UIFontMetrics字体随系统字号变化。
- 保留真实 seek slider；仅来源有效、原账号仍有效、对应播放状态就绪、duration>0且VLC isSeekable才启用。VoiceOver有动作标签、进度值/调整提示；避免时间标签逐帧重复读屏。
- 文件资料仅 frozenContent 的原文件名、真实duration与正数size；缺失名显示“视频附件”，时长未知不捏造，size为0/缺失不填示例。metadataStack仅在来源/原owner仍有效且非错误展示态显示。
- 独立显示 opening/buffering、playing/paused/ended/error。没有重建VLC或改其options/cache/网络。播放中的动作依据 player.isPlaying，声音依据 audio.isMuted；无audio明确不可用，不写死原型的“开启声音”。
- 有效远端来源播放失败：显示“视频暂时无法播放”“你可以返回聊天后重新打开，或分享原文件。”，提供返回与原安全分享。无效源/失效owner仅返回，不从新SDK借源；不画无效“重试播放”。VLC error后的stopped事件不立即抹去恢复状态。
- 正文分享UIButton通过原saveVideoButtonClicked动作进入740安全导出，明确检查sender为本页shareButton；isPreparingShare阻止重复提交。显示“正在准备分享…”，与播放器spinner分开；原owner/source/attempt门禁消费终态，错误显示既有安全文案、可恢复当前按钮。
- 系统分享呈现仍只调用740显式context overload，没有“已保存到相册”或“分享成功”假反馈。源有效仅表示可以尝试，HTTP403/网络/写入结果仍由原helper决定。
- 本地发送来源继续原 inputAccessoryView、字幕/回复/发送一次性代码和通知。为滚动内容追加基于实际 accessory/keyboard frame 的底部 inset；远端delegate为空，不取得键盘或加入字幕框。本地逻辑的实际设备兼容仍待验。

## 源检查与必要旧策略修正

旧 test_media_attachment_policy.py 的标题/docstring及断言把图片和视频都视作沉浸式预览，禁止名为fileNameLabel/sizeLabel的元数据控件；该脚本没有账号或机密门禁依据。总控本轮明确批准显示真实文件资料，因此只替换视频的旧外观规则，保留图片原禁止规则以及视频黑底、原分享动作、上传/消息相关原断言。没有通过换字段名规避旧测试。

新策略解析真实storyboard并检查23个outlet和控制器声明完全相符、5个action有实际方法、scene内constraint引用存在、按钮最小52pt、滚动guide及多行元数据；再核实际控制器原owner/冻结source/attempt/准备分享守卫和动态布局接线。这仍是源码/XML检查，不能作为Auto Layout运行或Swift编译证明。

Windows已执行：
- rtk python -B Scripts/ci/test_media_attachment_policy.py — PASS。
- rtk python -B Scripts/ci/test_video_media_policy.py — PASS。
- rtk python -B Scripts/ci/run_static_policies.py --report docs/handoff/R3/VIDEO-UI/static-policies.json — 44/44 PASS。
- rtk proxy git diff --check — PASS。
- source-checks.json 的10个边界检查通过：仅目标scene变化、全storyboard ID唯一/约束引用闭合；ThumbnailFetcher、inputAccessory/canBecomeFirstResponder、本地发送extension、owner/source gate、实际下载与inline导出分支保持；原helper三个文件及native测试未改。文件SHA附同JSON。

没有新增镜像原生测试。现有URLSession/文件导出真实原生回归保护下载核心；它们不覆盖这个新Storyboard或播放器UI。完整可审差异由本单元提交的两个生产文件及一个策略文件提供，不压入旧CI版本。

## 兼容、剩余验收与回退

C3、AUTH-A1、R3.D1、schema、服务配置、VLC依赖、旧background上传与新版ephemeral下载核心均未改；SharedUtils/私有资源未读写。账号所有权只沿原上下文，资料不取当前新账号或日志；错误信息不附URL、文件路径、token。

本机Windows：Swift/ibtool/完整App编译 NOT_RUN。下一准确SHA需总控Mac CI实编并保持196原生+3原导航选择。现有身份导航不能进入已登录聊天视频，不能当视频UI旅程验收。

仍需实际视频/设备证据：默认与最大动态字号、横屏/小屏、深浅色、VLC解码/seek/声音、VoiceOver、系统分享关闭/取消、本地caption键盘/回复/发送。VLC内部redirect/cache、真机与跨端仍不在本批已验范围。本轮代码不降低secure输入保护，不试图关闭已记录的密码截图视觉缺口。

安装/运行沿原授权免签模拟器流程，由总控操作。回退本视觉单元可使用父提交8ea0799（生产仍740）在独立验证树复现；无库迁移或数据清理，不在原用户dirty目录reset。
