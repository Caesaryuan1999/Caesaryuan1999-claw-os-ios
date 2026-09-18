# VLC 播放只读核查与最小真实探针提案

固定源码 e6e07aff8215ea003312a518d6f83e0c1da0ee84。只读 5 个本地源码/依赖文件，清单和字节 SHA 见 source-scope.json。未修改生产、测试或 CI，也未运行 VLC。CI17 的 196 原生 + 3 离线导航与冷启动通过，不覆盖视频播放。

## 已确认的链路和边界

| 位置（固定 e6 行号） | 源码事实 | 不能推出的结论 |
| --- | --- | --- |
| VideoPreviewController.swift:145–199 | 捕获 ClawOwnedImageContext；remote ref 经 resourceURL 解析，随后 captured owner.addAuthQueryParams，再 VLCMedia(url:)；VLCMediaPlayer 使用无 options 的默认初始化。播放不调用 startOwnedDownload。 | OwnedFileDownload 已通过的禁重定向、无 cookie/cache 和 URLSession 回调门禁不能算作 VLC 网络行为。 |
| Tinode.swift:648–674 | isTrustedURL 比较 scheme、host、port；仅 trusted URL 追加 apikey、auth、secret query，原 query 保留；外源不追加当前账号凭据。 | 未证明跨源 redirect 会转发 query、Referer 或 Cookie，不能把“跟随跳转”直接写成“凭据泄漏”。 |
| ClawSecondaryUIState.swift:132–143、269–274 | ref 先按捕获 serviceURL 解析成 absoluteURL；允许规范化同源或外部 HTTPS，拒 userinfo。不同主机的 scheme-relative ref 解析后不通过 Tinode 同源判定。 | 不能移植 Android 的 scheme-relative trusted 结论；首次 URL 校验不管 VLC 后续 URL。 |
| VideoPreviewController.swift:219–236、443–465、537–612 | 页面离开/内容替换会 invalidate、取消分享并 player.stop；按钮和 delegate 按原 owner/current source 拒绝。单独 owner 失效时 delegate guard 直接返回，不主动 stop/清 drawable；play 前 isCurrent 与 play 调用也不是一个锁内动作。 | 静态确认缺少“退役即终止播放器”的调用接线，但标准退出路由是否先令页面消失、退役后还读多少字节/帧，必须实际测。不能直接宣布 B 已看到 A 视频。 |
| VideoPreviewController.swift:467–520 | 分享保持原 context/source/attempt，单独 owned helper 下载，主线程 presentation 门禁；不依赖当前 VLC 网络缓冲作为导出来源。 | 分享安全不能自动修复直接播放。播放失败但原 ref 有效时可独立分享，是已批准行为。 |

另有可确定的兼容差别：ClawMediaFiles.origin 规范化默认端口，而 Tinode.isTrustedURL 使用 URL.port 原值比较；隐含默认端口与显式 :443 可导致允许访问但未追加 auth。它不是跨源凭据放开，本轮不修改，也不据此扩大审计。

## 固定依赖与本地头的实况

Podfile.lock:127 固定 MobileVLCKit 3.6.0；203 的 8fe98ae53b7464f32e4bdf527cc7d53053e4d3a5 是 podspec checksum，不是运行 libvlc 二进制的 SHA。独占树无 Pods，work 范围亦未找到相关本地头；不能声称本机已按实际 installed header 编译新测试。

[3.6.0 官方 podspec](https://raw.githubusercontent.com/CocoaPods/Specs/master/Specs/b/f/7/MobileVLCKit/3.6.0/MobileVLCKit.podspec.json) 固定下载 MobileVLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz，SHA256 1a5077beeb7bf943a3fbbb91523752e50a10d490a3046cb9808d906784ddbc36，并交付 xcframework。本轮未下载大体积二进制。

[对应 c73b779f 的 VLCMediaPlayer 源码](https://raw.githubusercontent.com/videolan/vlckit/c73b779f/Sources/VLCMediaPlayer.m) 的 init / initWithDrawable 路径使用 sharedLibrary；stop 转入 stop_async。它支持“默认不是账号独立库”“清理应等实际停止”，不证明 HTTP 持久缓存、磁盘内容缓存或跨账号复用。

[对应 VLCMedia 头](https://raw.githubusercontent.com/videolan/vlckit/c73b779f/Headers/Public/VLCMedia.h) 提供 URL/stream 初始化、media options、cookie 操作和 statistics；stream 默认可能不可 seek。[VLCMediaPlayer 头](https://raw.githubusercontent.com/videolan/vlckit/c73b779f/Headers/Public/VLCMediaPlayer.h) 的公开 delegate 是播放事件，并非 URLSession redirect delegate。本轮没有找到当前应用为 VLC 设置的逐跳校验、账号缓存 key、cookie 清理或媒体读取取消桥。没有把未知 option 名或“network-caching=0”当作安全方案：缓冲时长不是账号隔离的证明。

下一次获批的 Mac 探针须先从实际 Pods/MobileVLCKit 的 simulator slice 记录这两个头的 SHA、framework 版本及 player.libraryInstance.version/changeset；不要用网上最新头替代安装版本。不输出 library 的原始网络日志、URL、凭据或其他进程数据。

## 最小可运行的真实 VLC 探针

建议先做“真实依赖行为取证”，不替换播放器，也不再增加 14 个 URLSession 适配测试。拟 4 个测试/接线文件：

1. 新 TinodiosUITests/VLCPlaybackProbeTests.swift：真实 VLCMediaPlayer + VLCMedia、合成本机 HTTP 服务、AVAssetWriter 生成的短视频、真实 Tinode/ClawOwnedImageContext 与安全观测全部放此文件。
2. Tinodios.xcodeproj/project.pbxproj：测试源接入与必要 framework 链接。
3. Podfile：若当前 UI runner 无 MobileVLCKit target 链接，仅为现有 TinodiosUITests 显式继承/添加同一锁定 pod；不升级版本、改上传框架或产品配置。实施前需核其 target 作用域，本次 5 文件只读范围未再打开 Podfile。
4. Scripts/ci/verify_publish_outcomes_macos.sh：同 sim_id 增加这个 class 的实际选择，保留 196 与导航3，输出进入现有 storage.xcresult/log artifact。先按实际可编译的方法清单再冻结计数，本轮没有新增计数。

测试传输必须是实际 socket，不是 URLProtocol、假的 VLC 或替代的 redirect guard。服务只监听 127.0.0.1、OS 分配端口；两个端口用于同源/异源跳转目标，所有 Location 均严格落在本轮注册的本机端口，不能访问公共网络。绑定失败、生成/解码失败、缺事件、超时是失败或明确环境阻塞，不能 skip 后宣称安全。

合成视频用 AVAssetWriter + PixelBuffer 写两个 2–3 秒、64×64 的独立颜色标记 MP4，无音轨，无外链，生成和播放均有上限；不下载互联网媒体、不提交真实文件。服务支持明确 Content-Length、Range、节流和每轮独立路径。至少一次基线应证实实际 video output、时间进展与解码帧/statistics；截图/快照取得后校验颜色区域，不能只看到 .playing 就算已正确解码。

建议 4 个方法内的有界矩阵：

| 方法方向 | 实际观测与判定 |
| --- | --- |
| 正常解码 + URL 形成 | 用实际 Tinode.addAuthQueryParams 产生带合成凭据的本机地址；服务收到请求且 VLC 解码指定短片。先证实 fixture 可工作。请求只保存 route ID、query/header 名是否出现、是否等于本轮合成值的布尔和字节计数，不记录完整 query。 |
| redirect | 分别 302/307 同源与第二本机端口；Location 不带 query 和显式带合成 query 两类分开。记录是否触达目标、凭据/Referer/Cookie 是否存在以及是否解码。不能把响应中明确指定的 query 归因于 VLC 自行泄漏。安全期望与观测分列；若发生被禁止的跳转，应保留失败证据，不改 expected 让危险行为绿。 |
| owner 退役时的真实播放 | 在实际首个请求/首帧屏障处调用合成 Tinode.logout，确认 context.isCurrent=false，随后观察连接是否继续读、播放器时间/帧是否推进；再显式 stop 并等待 stopped/连接结束，作为退出上限和清理对照。此方法测真实 VLC 与原 owner 关系，不能冒充已实例化 VideoPreviewController 的实际退出路由；不在测试中写一个“guard 后 stop”的替代实现来宣布生产已安全。 |
| 重开旧 URL / 缓存与 Cookie | A 片播放后完整 stop，服务同一地址改为 B 片或 403，再用新的默认 player；记录服务是否收到新请求、验证/range header、是否仍解码 A 颜色。分别 cacheable 与 no-store、带/不带合成 Set-Cookie、旧 player 与新 player 的有限矩阵。另以实际不同合成 token 的完整 URL 验证 A/B，避免把路径相同误当整个缓存键相同。先出现 A 后 B 是测试内容标记，不是真实账号数据。 |

“退役后剩余已缓冲帧”“停止之后又发出请求”“重开后不请求直接显示旧内容”应分别记录。一个运行中的内存缓冲不能被称作磁盘缓存；一次没有旧片也不能证明所有协议/所有版本无缓存。不得用未知有效性的 VLC option 更改当前默认行为后，把结果当作当前 e6 的行为。

## 实际消费者测试的接线限制

project.pbxproj:724–743 显示 TinodiosUITests 是 ui-testing bundle；其 Sources 内有部分真实 helper，而 VideoPreviewController 只在 App Sources:1049。现有 runner 可实际调用 VLC，但不能凭新增一个 Swift 文件就声称执行了 App 内的 VideoPreviewController/Cache。

若要直接覆盖“原页面正在播放→原 owner 退役→真实页面停止”而非上面的依赖观测，需另批准：
- App-hosted unit test target 的 TEST_HOST/BUNDLE_LOADER 接线，以及可在隔离账户 fixture 中实例化实际 storyboard/controller 的入口；或
- 在生产 controller/既有 ClawSecondaryUIState 抽出极小的真实 playback ownership 入口，由生产和测试共同调用。

两者都必须避免重写 guard 的测试镜像，且不应借此开全App测试重构。本轮只提出约束；尚未允许改生产，故没有偷偷加入 DEBUG 登录、深链或假聊天入口。

## 复用安全下载后本地播放的可选方向（未实施）

可以考虑 remote ref 先经已存在 startOwnedDownload，收到完整文件且原 owner/source 仍有效后，VLC 只拿本地 URL。它可消除本轮顶层 HTTP 播放地址中的 auth query，复用已测的逐跳拒绝、匿名外 HTTPS、无 cookie/cache 与受控导出路径；但不是“把 url 换成 fileURL 就宣称全部安全”。

必须处理以下兼容和验收点：

- 等整文件下载后才开始；首帧延迟、临时磁盘空间、长视频、Range/seek 与当前边下边播不同。下载失败可重试原 owner，不能重新获取后来账号。未知长度继续由实际完成事件决定；不能靠声明 size 假装完整。
- 播放临时文件与分享导出不能互相提前删除。使用独立所有权/lease；停止是异步，需实际停止并释放 media 后再清理播放文件。分享 UI 仍有自己的完成/取消寿命。页面退出、源替换、owner 退役和晚到下载每条路径都要释放本次文件，不能删除其他导出。
- 临时文件当前是进程内 registered ownership；不自动承诺跨重启清理。全量离线缓存不是这次功能；同账号当前打开文件可本地播放，账号 B 不复用 A 的路径。
- 本地文件也可能是 playlist/manifest、含远程子资源的容器、外部数据引用或侧载字幕。扩展名、Content-Type 和一个“可播放”布尔都不是可信安全边界。需真实 VLC 对合成 M3U/PLS、绝对/相对外链及容器引用做出网观测，或先冻结受支持自包含容器并验证结构及网络拒绝机制；没有证明前不得声称本地 VLC 永不联网。
- inline bits 的 InputStream 路径也要算在容器/子资源范围；不能只修 ref 下载然后遗漏 inline manifest。可兼容性会因此收紧，须明确错误与恢复。
- local 用户所选待发送视频保留现有字幕/缩略图/发送行为，不能借安全下载单元改 C3、SDK wire、数据库或身份规则。

建议先批准上述真实依赖取证，获取 redirect、退役和重开行为；若决定改为本地播放，再冻结两生产文件左右的播放生命周期方案，连同实际消费者入口回归单独审查。当前只能确认播放路径绕过已测 owned 传输，以及没有原 owner 退役主动停止接线；尚未证实跨源凭据泄漏、跨账号持久缓存或实际用户视频泄漏。
