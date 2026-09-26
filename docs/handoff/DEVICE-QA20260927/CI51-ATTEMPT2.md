# iOS CI51 attempt 2：原始结果与续接边界

记录时间：2026-09-27（Asia/Shanghai）。本报告只追加本次 CI 证据，不变更既封存源码、测试阈值、协议或原报告。

## 结论

一次获授权的原失败 job 重跑已完成，结论仍为 **failure**。MobileVLCKit 下载阻塞解除，已进入真正的 macOS / iOS Simulator 编译与原生测试。SDK 44/44 通过；App / SQLite 293 项中 288 通过、5 失败、0 跳过，合计原生 337 项中 332 通过、5 失败。当前不能宣布 iOS 验证通过。

本次运行固定旧候选 `0877d9a8411b0835a1076b426a92da64e0ab9468`，**不包含**本轮会话失效修补 `92208c6` 与 `3d94981`。本轮补丁只有 Windows 静态检查证据；预备的 Swift 精确函数 fixture 未运行。两类证据必须分开。

## 授权及来源

- 自有仓库：`Caesaryuan1999/Caesaryuan1999-claw-os-ios`。
- 分支：`codex/verify-r2-ios02-20260918`。
- 工作流：`.github/workflows/ios-smoke.yml`，workflow ID `310211684`，原事件 `workflow_dispatch`。
- 原 run：`35497878843`；本次 attempt：`2`；job：`108508510112`。
- [GitHub 原运行](https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios/actions/runs/35497878843/attempts/2)。
- 重跑前核对原 head SHA、分支、工作流、attempt 1 完成失败和失败步骤。2026-09-27 07:27:22 +08 调用一次 `rerun-failed-jobs`，HTTP 201。
- `CI51-RERUN-ONCE.json` 在 POST 前排他创建；脚本要求原 attempt 1，不能自动再次重跑。未推送代码、未签名、未发行、未连接真实用户服务。
- job 开始 `2026-09-26T23:27:37Z`，完成 `2026-09-26T23:46:17Z`，即北京时间 07:27:37–07:46:17，18 分 40 秒。

## 实测环境与结果层级

| 项目 | 本次实际结果 |
| --- | --- |
| 工具链 | Xcode 16.4 / 16F6；macOS 15.7.9 |
| 模拟器 | iPhone 16 Pro，iOS 18.5 / 22F77，arm64 |
| 模拟器标识 | `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9` |
| 依赖 | MobileVLCKit 3.6.0 安装成功；11 个 Podfile 依赖、23 个 Pods 完成安装 |
| 远端静态检查 | 44/44；当前本地新增第 45 项不在此 SHA |
| TinodeSDK 原生测试 | 44/44 通过，0 跳过 |
| App / SQLite 原生测试 | 288/293 通过，5 失败，0 跳过 |
| 独立导航测试 | NOT_RUN；未产生 navigation.xcresult |
| 模拟器 app 封包及冷启动 | 工作流步骤 skipped，不能计为成功 |
| 本轮会话修补的 Swift / iOS 编译 | NOT_RUN，不在 CI 输入中 |
| iPhone 真机、双设备、Android/iOS 联调 | NOT_RUN |
| 真实注册、短信、模型、推送、生产媒体链路 | 本次 CI 未验证 |

模拟器 test-host 已编译并执行测试不等于独立安装、冷启动或完整产品验收。本次没有新成功封包的 unsigned simulator app / 可发行 IPA。

## 五项失败及可支持的判断

| 测试 | 原断言 / 阶段 | 原始诊断附件 |
| --- | --- | --- |
| `ImageMessageLayoutTests/testActualRetryConsumerRechecksEntityPageBulkSelectionAndReuse()` | `Bounded image stage: retry available` | `46F6EFE3-784C-4383-9F14-558C011F7B73.json` |
| `ImageMessageLayoutTests/testOwnedAttachmentRetryKeepsCanvasAndRejectsCancelledAndRetiredCallbacks()` | `Bounded image stage: first failure` | `5D4D09FB-CE32-4146-B742-8CF514C8F64C.json` |
| `ImageMessageLayoutTests/testRealHTTPFailureRetryUsesOriginalOwnerAndShowsClearTextAction()` | `Bounded image stage: real HTTP 403` | `6808C4DE-6597-4384-96B3-CCC2F7B86AAE.json` |
| `VoiceLayoutTests/testOwnedAudioActualAACPlaybackPauseResumeAndFiniteSeek()` | 实际 AAC finish delegate 未在原 3 秒等待内完成 | `38E487D7-63BB-4B9C-8A72-D75D337080C1.json`（生产引擎）；`DAF2F21E-6205-4834-9BB9-14492366B4A9.json`（裸 AAC 对照） |
| `VoiceLayoutTests/testOwnedAudioIndependentPCMControlUsesRealFinishDelegate()` | 独立 PCM finish delegate 未在原 3 秒等待内完成 | `96604974-5B23-4757-AA1B-7C8725B27FD0.json` |

附件目录统一为 `CI51-attempt2-original/ios-01-a-20260926-232942/storage-attachments/`。失败断言来自 `storage-summary.json`，关联关系来自原始 `storage-attachments/manifest.json`。

### 图片：状态已改变，但改变时刻尚不能确认

三项失败的超时后快照均为：`state=failed`、`can_retry=true`、`owner_current=true`、`consumer_current=true`、`source_matches=true`；`predicate_evaluations=1`、`predicate_last=true`，主队列尾标记与主线程快照均为 true，而 waiter 返回 timedOut。实际 elapsed 为 3.004–3.009 秒。

受控路径各有 1 次请求、1 次完成回调；真实 HTTP 403 路径记录 1 次 HTTP 请求。当前原件不支持“未收到失败”“owner 已退役”这样的直接结论，也不证明谓词在原 3 秒期限内变成 true。

`ImageMessageLayoutTests.swift:325–356` 的 bounded helper 在 `XCTWaiter.wait` 返回后才采集诊断。谓词和完成回调缺少可与 deadline 对齐的单调时间，因此下一次窄排查应记录实际回调、谓词评估、fulfill 和 waiter 返回的时间及线程，辨别 XCTest 等待调度和实际状态延迟。**主线程调度问题只是待验证假设**。不要把阈值放宽、owner guard 移除或仅按最终快照改为通过。

6 项 ImageMessageLayoutTests 中现有 3 项通过：旧图片尺寸归一化、实际 MessageCell 长图双向/浅深/辅助字号几何、长图 TOP 与未知尺寸 FIT 像素。CI50 的两个几何断言失败未在本次重现。另 3 项重试链仍失败，图片模块整体验收仍未通过。

查看了实际测试导出的浅色普通字号与深色辅助字号长图 PNG；它们是合成纯色图在真实 MessageCell 中的渲染证据，能看到“长图”标记和气泡几何，不能用作真实用户聊天、上传下载或真机截图证据。失败重试阶段提前退出，未产生其后计划的恢复成功截图。

### 音频：PCM 对照同样未收到真实完成回调

生产 AAC、裸 AVAudioPlayer AAC、独立 PCM 在 deadline 前后均为 `successful_same_engine_finishes=0`，同引擎 delegate 已安装，loops 为 0。定时采样持续执行，`current_time` 到达 1 秒（duration 也是 1 秒）后仍 `is_playing=true`。生产 AAC owner scope 仍当前。

PCM 为 RIFF/WAVE、16-bit little endian 单声道、16000 Hz、16000 samples；输出 Speaker、2 声道、48000 Hz，AVAudioSession Playback / Default。PCM 的 `production_scope_current=false` 是独立对照不绑定生产 scope，不能当作账号失效。

PCM 也失败，因此不能将问题归因于 AAC 编码一个因素；目前也不能证明是 Simulator 平台缺陷。下一步需要在受控 Mac / iPhone 环境确认独立 PCM 真实 finish 正例，再与生产引擎比较。继续保留真实 delegate 和原阈值，不手动调用 finish、不把 currentTime==duration 当作完成回调通过。

本次未改音频生产实现、AVAudioSession、测试阈值或 CI 文件，未再触发运行。

## 原始证据、完整性和保存

- `CI51-attempt2-result.json`：run/job/attempt、步骤、下载来源元信息及 312 个选择性提取原件的 SHA-256。
- `CI51-attempt2-job.log`：7,090,354 字节，SHA-256 `ed283979b7f1166e2922f7a95b4439a5f9cecb9151054de583a622d383fd268c`。
- `CI51-attempt2-evidence.zip`：artifact ID `10917979519`，115,985,717 字节，SHA-256 `ff06a6e14a73f2ded31e7f2026997878df1d00ef99bf4fe054ff574cdca34fce`，匹配 GitHub digest。
- ZIP 保留完整 xcresult 和源附件；选择性提取仅用于复核，未改写图片或原 JSON。完整 ZIP、日志和 312 原件保留在本工作目录，未加入 Git 提交。
- `CI51-ATTEMPT2-DIAGNOSIS.json`：离线生成的计数、5 项失败、关键原始诊断摘要，明确原件路径和判断边界。
- `CI51-ATTEMPT2-SEAL.json`：本报告、脚本、紧凑元信息和上游原件 hash；源补丁仍由独立 `SOURCE-SEAL.json` 封存。
- `ci51_recovery.py` 仅用于记录这次一次性授权；`collect_ci51_attempt2.py` 只读取本次固定 CI 原件。认证凭据仅在内存使用，GitHub Authorization 未转发到下载站，报告不含凭据或签名下载 URL。

仅紧凑报告、索引和脚本提交到本地分支；未推送。不要删除原 ZIP 或将其与本轮源码 SHA 混淆。

## 可直接续接的工作单元

1. 总控按独立复核结论集成本轮 `92208c6` → `3d94981`；当前支持是 45/45 本地静态脚本、9/9 新 source policy 和同 owner 已 attached 分支的独立代码复核。先在有 Swift 的环境执行已准备的精确函数 fixture；不能拿旧 CI 的 337 项代替。
2. 图片仅排查 3 个 bounded stage 的回调/谓词/等待时间关系，保留失败原件和 3 秒阈值。没有可证根因前不扩大视觉改版。
3. 音频单独获取独立 PCM 的真实完成回调正例及可信设备环境；无设备条件时保持未关闭，避免反复无变化重跑 CI。
4. 待上述修补固定并获总控确认后，再安排对应验证分支的原生测试、独立导航、封包、冷启动。该步骤尚未执行。
5. Q01–Q40 路由与缺口继续使用 `IOS-PAGE-REVIEW.md`。无 Mac / iPhone 资源条件未改变，真机、跨端、试用与正式发行均未通过。
