# CI26 VLC 原始结果独立复核

- 复核对象：`4b5ab7398cf70e153eaaf08dd09cb79cefb20ece`；run `35348626059` / job `105611120727` / artifact `10549518207`。
- 本次只读原始证据和对应方法，新增本文及 `CI26-VLC-RESULT-REVIEW.json`；生产、测试、CI 均未修改。后继 `d45cbeacda88b0d7c9a371c95579e63d60153f82` 的组件测试不在本轮验收范围。
- 原 ZIP：`C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence.zip`，实读 38,991,032 字节，SHA-256 `9dda85090f5d4f205b79ecb986b7b1b6f76f818e15287e2505fe5310015487f6`。
- 原目录：`C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038`。下列 JSON/PNG 均位于其 `storage-attachments` 子目录，清单保存完整绝对路径。
- 三个原 summary 独立读取：SDK 44/44、storage 182/182（UIrunner 175 + VLC host 7）、navigation 3/3，均 0 failure / 0 skip。即 226 native + 3 navigation；打包及冷启动成功由总控另行验收，本文不重复扩大该层检查。
- 实际设备：iPhone 16 Pro / iOS Simulator 18.5 / arm64 / `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9`。真实依赖 MobileVLCKit 3.6.0，运行时 `3.0.21-49-gd1840ca85f`；双 lock/spec checksum 及 binary/header 哈希在原 JSON 内。没有把 spec checksum 当下载 archive 验证。

## 新增三个方法的实际结果

| 方法 / 原 JSON | 实际观察 | 有界结论 |
| --- | --- | --- |
| `testOwnedDownloadedFileProducesRealVLCFrameTimeAndSeek` / `72783A47-24CB-4AD2-AFCF-AF41BCD0CD2C.json` | 真实生产 owned download 获得与源片逐字节一致的本地文件；1 次 HTTP 200，6678 字节、header/body completed、同源 auth header，query 无凭据。VLC 本地读取后 decoded 217 / displayed 45 / 64×64 / time 2714ms；seekable、seekObserved 为 true，保存实际红帧 PNG。方法断言启动 VLC 前后 server 请求数相同。 | **CLOSED（该 MP4 / helper 验收）**：下载→本地 VLC 解码/显示/时间/seek 可用。没有测试任意媒体容器，也未实例化 VideoPreviewController。 |
| `testOwnedLeaseRetirementStopsRealPlayingAndPausedVLCBeforeFileRemoval` / `337E4C80-B440-4897-9793-280983B65DC2.json` | playing/paused 两例，退休前 decoded 均 112，displayed 24/26，time 907/911ms；实际调用生产 lease.checkOwner 后，两例 actualStopConfirmed、leaseCleaned、ownedFileRemoved、shareFilePreserved 均 true。 | **CLOSED（lease + 实际播放器验收）**：确认 stopped 后移除本次播放副本，独立分享副本保留。owner check 为测试直接调用；页面 250ms 轮询、退场 UI、主线程受阻及系统分享仍 **OPEN / NOT_RUN**。 |
| `testLocalPlaylistExternalReferenceRecordsRealVLCNetworkBehavior` / `4299144A-C328-4C95-BE8F-008062D8E29F.json` | 本地 M3U 92 字节、3 行、唯一引用为本方法 HTTP 127.0.0.1，无 userinfo/query。实际 VLC readBytes=92，state=0，decoded/displayed=0；完整 5,002,619µs 窗内 requests=[] / externalReferenceRequested=false。前置同源片本地 VLC 控制获得红帧，Apple 对照解码 90 帧/64×64。 | **OBSERVATION COMPLETE；安全问题仍 OPEN**：本轮未观察到 secondary networking，不能记录为已确认外连；也不能把“只读到 playlist、未产帧”解释为任意容器网络隔离已通过。没有证据说明未外连的内部原因。 |

生产 lease 的 stop/detach/cleanup 方法及真实 VLC 均执行；新方法没有替身安全播放器。播放启动由 probe player 完成，随后登记同一生产 lease；这与完整页面操作仍有层级区别。两个 retirement case 的 after metrics 为已停播放器的重置值，不用于估算 stop 延迟，更不证明 250ms 页面检测界限。

新 MP4 实际帧：
[C179 原图](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/C179AC9B-8048-45BE-9775-22E29A997D83.png)。
M3U [原字节](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/4D68816B-C5F4-4A43-AA2C-DA93D53ED677.m3u) 只作本轮有限夹具证据，不需重新生成或访问其现已结束的临时地址。

## 403 三阶段与缓存观察

原 JSON：[078A2546](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/078A2546-AA66-40A3-930C-0EA12CEB6A5E.json)，SHA-256 `f9aab3ea4addda920c1373eb029cbf04a71ea17543723177c9bf1a85f2125cb0`。

| 设置 | 第一阶段 | 第二阶段 | 第三阶段：独立真实 403 | 固定观察窗 |
| --- | --- | --- | --- | --- |
| cacheable=false | seq 1–2 / revision 0 / 206，红帧 A，decoded 108 / displayed 21 | seq 3–4 / revision 1 / 206，重新请求、蓝帧 B，decoded 108 / displayed 22 | seq 5–10 均 revision 2 / 403；header/body completed、responseWriteCompleted=true；thirdRequestSequenceAfter=4 | 5,002,965µs；1 段 timedOut、0 次补足；deadlineReached=true |
| cacheable=true | seq 1–2 / revision 0 / 206，红帧 A，decoded 110 / displayed 24 | seq 3–4 / revision 1 / 206，重新请求、蓝帧 B，decoded 108 / displayed 24 | seq 5–10 均 revision 2 / 403；header/body completed、responseWriteCompleted=true；thirdRequestSequenceAfter=4 | 5,003,492µs；1 段 timedOut、0 次补足；deadlineReached=true |

两种设置均保留前两阶段的请求和帧，第三阶段有独立请求号及新 revision，不能误认前两次请求。两例全窗 maxDecoded=maxDisplayed=0，thirdStoppedOrTerminal=true、cleanupCompleted=true，结论为 `NOT_OBSERVED_WITHIN_FIXED_WINDOW`。此处响应完成仅表示本机 NWConnection 接受了 header/body 写入，不独立证明 VLC 已解析 HTTP 语义。

**CLOSED（探针确定性/可解释性）**：本轮实际达完整 5 秒，不能将初始 stopped/0 request 当通过；原 CI25 4999ms 失败保留，没有降阈值。本次 0 次补足并不能证明真实机器已经走到提前返回补足分支；四受控边界案例与真实网络观察分列。

**OPEN（更广缓存结论）**：有限同 URL 红→蓝→403 没看到旧帧复用，不等于跨进程、持久缓存、跨账号或所有容器安全。第一阶段 seq2 的合成 cookie 为 true；后两阶段请求 cookie 为 false，不据此扩成全局 cookie 隔离承诺。

原 PNG：
- false：红 [EBACBC49](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/EBACBC49-8ADE-4642-BF31-38F966F3C52A.png) → 蓝 [3F76124C](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/3F76124C-DB79-488E-B63C-F99DD41C4C8C.png)。
- true：红 [4BED2CBF](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/4BED2CBF-2D34-433A-A544-1928EF7DAE05.png) → 蓝 [1F3BB024](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci26-evidence/ios-01-a-20260918-131038/storage-attachments/1F3BB024-62CB-407D-992D-D57C29770E9F.png)。

## 原依赖风险观察没有被“7 PASS”抹去

- 原 retirement JSON `9B16D1CB-DC50-4E92-B38E-D69B611DD8E5.json`：未绑定 lease 的旧直接远端播放，真实 Tinode owner 退休后 continuedRead/continuedDecode=true，readBytes 0→11401、decoded 0→108、displayed 20。这是依赖风险正例；新 lease 的真实关闭结果见上，不能据旧 probe 正例声称当前完整生产页面仍已复现泄露。
- redirect JSON `650521F7-15AD-4FB8-BACF-6EE96D815001.json`：302 同源/跨源、307 跨源及显式携 query 的 302 均到达目标；前 3 例目标无 query auth，只有 Location 显式带 query 的目标看到合成 query 凭据。保留旧直接网络入口依赖风险；不声称 VLC 自动把原 query 附给所有重定向。
- baseline JSON `8E995841-0B5E-4287-A6B5-D0CCB00EE7EB.json`：本地/HTTP 同源片控制实际红帧，decoded108/displayed25/64×64/time250ms。其职责为真实解码基线，非安全通过标志。
- **OPEN / NOT_RUN**：完整 VideoPreviewController 实例/真实页面、可见期 owner 轮询、用户手势、系统分享、真机，以及任意容器本地播放的外部引用策略。本次不新增白名单、不改播放参数或生产代码。

## 原始实体复核

1. manifest 对应 7 方法、27 原附件：7 JSON、10 PNG、9 MP4、1 M3U；所有附件重新计算 SHA-256，并与原 ZIP 对应 entry **逐字节相等**。manifest 与 3 summary 也核对 ZIP 字节。
2. 9 个 MP4 均在所属方法的 sourceFixtures 找到唯一匹配 SHA/字节数；每个 JSON 的实际 AVAssetReader 对照均 PASS、90 帧、64×64。这里只复核 CI 原始 Apple 解码证据，没有在 Windows 冒称重新解码或 Swift 运行。
3. 10 张原 PNG 均实际打开目视，全部 64×64：8 红、2 蓝；红图 SHA `5e918e6963765e80fe984807731382db94fad456e11cee9c7d2e16351c7d3bca`，蓝图 SHA `0a10269fac322d3ee282f2397d30b5c34e2af06bc70086a7420728efb632cef3`。这些是 VLC synthetic fixture 帧，不是完整 App/UI 截图；同颜色同哈希符合固定色原片，不据此宣称不同真实页面相同。
4. 检查直接读取原 JSON 的 cases/metrics/requests；没有依赖 root collector 的旧 `observed_gaps` 分类。完整原路径、方法映射、每实体 hash、限定判定写于同行 JSON。
5. 未覆盖/删除 CI23、CI25 失败证据；本次有界 CLOSED 不替代其历史原因或扩成生产安全承诺。CI27/d45 仍由总控独立验收。
