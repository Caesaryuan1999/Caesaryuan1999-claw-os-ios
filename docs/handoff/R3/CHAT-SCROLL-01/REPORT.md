# IOS-CHAT-SCROLL-01 · 源码候选与待运行验收

独占 `work/r3-20260918-ios`，分支 `codex/r3-20260918-ios`；起点 `0a54fcf1ecb35a6f3511815ed59c7750f692ea2d`（生产/CI 为 `1b20ec2971061dbc002d1748f0f252d87b69d0f7`）。起始 tracked clean，既有 artifacts、只读 CHAT-SCROLL-PLAN 和历史 WIP 均保留，不加入本提交。旧包 09631 与 CI31 报告不变。

当前只完成源码与 Windows 检查；本单元 Swift 编译、242 原生方法、导航 3 及模拟器页面均 NOT_RUN。既有 CI31 的 232+3、打包和冷启动通过属于旧 1b20，不能覆盖此变更。总控/后端审查固定提交后，由总控推送获授权验证分支；本端未 push、未运行 CI。

## 实现与边界

只改冻结九生产文件：MessageVC、DisplayLogic、Presenter、Interactor、SendMessageBarDelegate、File/Image/VideoPreview，以及 MessageCellDelegate 共同 `scrollToAndAnimate` 的一行交互失效。另为新 ChatScrollTests 增加 pbx 成员、既有 App-hosted class selector；旧 brand 策略一条图标契约按获批文字动作调整。无 SDK、DB、Recorder、Cache、LargeFileHelper、XIB、协议、Pod/目标/工作流/超时变化。

显示信封携带创建页面 UUID 和原 topic 对象身份；读库前固定来源，Presenter 投递主线程保留它，消费者在入队、开始与定位终态核对。页内交互与提交序号只用于 UI；不会进入 head、UploadDef 或数据库。文字/录音及三个预览确认入口先捕获不可变意图；文件通知 object 不变，只加 userInfo。视频同一值穿过缩略图和后台 Data 读取，晚到消息入库不会铸造新票据。预览允许原聊天暂时不可见，仍要求原页面在同导航栈且原预览在栈顶；无效意图只取消主动滚动，不阻止原发送。

新发/回复/转发的有效当次票据可消费一次定位最新；编辑在 pending 清除前确定保留阅读位置，后续 ACK/失败不重新读取 pending。非按钮旧调用默认被动。被动数据在原底部可跟随，在回看时按实际可见 msgId 与像素偏移恢复；原 topic 内正 seq 仅作备选。首锚点删除则用存活可见邻居，全失去则钳制原 offset。首次非空定位资格不会由清空再回填重置；空列表中的旧阅读意图也不会凭空取得底部资格。

两个 UIKit batch 阶段串行完整执行，后到快照排队；下一快照从实际已呈现数组重新 diff，不能在旧 refresh index 尚未使用时替换数组。队列只限 UI，不阻塞 SDK/Interactor 消息接收。终态检查原来源与交互代次，直接 layout/设置合法 offset；不调用内部另开异步 completion 的 MessageView.scrollToBottom。程序标记仅包同步布局调用，defer 复位；拖动开始、引用/置顶点击和无法归属的 offset 变化使旧票据失效。旋转/大字、置顶、整批与指定 seq 局部刷新也进入同一 UI 队列；上传进度值不创建意图。原发布、claim、上传成功 ref、存储/删除、Promise 和 read 行为不改变。

按钮可见文案与读屏统一“回到最新消息”，没有新消息数量。原主题/原右下位置，最小 44pt、标题内边距与安全区宽约束，大字允许换行且按标题测量最小高度，避开原输入 accessory；无 accessory 时额外尊重底部安全区。Figma 来源 239:2157/239:2203 与原型 241:1110→241:1152；此处不宣称 Present 或真机视觉通过。

## 原证据与本地检查

- `before.json`：原九文件固定 blob 与原字节 SHA；`RED.md` 保留无条件滚底、编辑回调、迟到附件、异步 helper、并发 refresh 等源码反例。Windows 无 UIKit 红测，不写成动态复现。
- `static-wip.json`：原 44 策略 43 通过，唯一旧 chevron.down 契约失败；总控批准改该一条为文字/读屏/触区/安全区/大字检查，其他 43 脚本保持。`static-final.json` 为 44/44 Windows 源码策略，不是 Swift 编译。
- `source-checks.json`：20 项限定源/接线核验、13 个代码文件原字节 SHA 与 Git blob、10 方法清单；`verify_source.py` 可复核。`git diff --check` 通过。
- `audio-adapter-checks.json`：实际现有 CI 源提取器在四个独立 Git 夹具上执行，正确分支通过，错 ref、重复分支、dirty 源均按原断言拒绝。原红 blob 保留。`extractor-scope.json` 区分生成范围：Audio 仅两段 audio 分支和完整 draftyAudio/relativize，未引入 ChatDisplay 类型；Reset 仅原 SendMessageBar 方法；Recorder/LocalDelete 直接编译的生产源未变。MessageInteractor 整文件只属 App target，新元数据与它同模块。不增加签名 stub，不修改旧提取器/hash/业务断言，不把 Python 生成视为 Drafty/Swift运行。

## 10 个新增原生方法（尚未执行）

既有 `TinodiosVoiceLayoutTests` App-hosted target，`ChatScrollTests` 唯一 selector。原 SDK 44 + UIrunner 175 + VLC 7 + Voice 6 =232 完整保留；新增10后总242，导航3另列。没有新 target/依赖/额外 CI 时限。

1. 大批新增回看保持与原底部大/小两批跟随。
2. 前插、实际 FlowLayout 高度变化、删首锚点保可见邻居。
3. 实际 UICollectionView 第一阶段未完成时投递第二快照，断言数组未被替换、最终 item 数与锚点。
4. 批次阶段间受控调用真实拖动 delegate/改变 offset，拒绝旧提交终态。
5. 真文字发送消费者接捕获端口（不 publish），新发/回复/转发；一次消费、迟 ACK/重复票据和无 pan 的 offset 变化。
6. 真 pending.edit 捕获、清 pending 后仍 preserve；置顶/局部/旋转消费者链。
7. 真 quote/pin 共同入口无目标/no-op 废票；Presenter 主线程迟投递/同名不同 topic/另一 page 拒绝。
8. 真 FilePreview 确认 handler 与真实 Notification，原 VC offscreen 的合法捕获；后继工作只复用此票据。文件预览布局为中性子类，不装 storyboard；interactor=nil，无发布。视频 thumbnail/Data 传递由固定源绑定核查，非完整视频按钮运行。
9. 首次非空真实 offset==max、清空回填不重置、零 seq 草稿按 dbID 区分。
10. 原 loadView 创建的文字按钮尺寸、安全区/大字与真实 action、旧恢复失效；PNG/geometry 附原 xcresult。

这些测试用真实 MessageVC 显示方法、原 MessageView/UICollectionView，但数据源是中性 cell、布局是 FlowLayout。**不等于生产 MessageViewLayout/消息气泡完整布局、真实手势、键盘聊天旅程、消息已读或认证服务通讯通过。** 附件元数据与原生测试仅含合成值。原始 UIKit 自动 offset 与 batch 动画可能使保守代次失效；测试保留实际底部/锚点断言，由真实 Mac 判定，不能用策略绿提前关闭。

## 安装与回退

这是源码候选，不是已验模拟器包或签名 IPA。待准确 SHA 的 macOS 构建、原232回归+新增10、导航/打包/冷启动完成后才沿现免签模拟器安装流程验收；真机、真实账号历史、跨端及完整键盘/媒体旅程仍另验。若回退此 UI 单元，回到固定父 `0a54fcf` 的完整代码/接线，保留本机原库与私有配置；本单元不迁移 DB，不执行 reset/clean。旧安全累计源包继续保留，待本轮验收后再由总控决定累计重封。
