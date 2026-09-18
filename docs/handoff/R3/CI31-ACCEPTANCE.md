# CI31 独立验收 · 2026-09-19

结论：精确 `1b20ec2971061dbc002d1748f0f252d87b69d0f7` 的 CI31 原生 232 方法、真实离线 App 导航 3 方法、未签名模拟器打包及独立冷启动均有实际通过证据。发送按钮的文字态和清空恢复态原始 JSON/PNG 相符。本次只读核验已下载原件，未执行新的 CI、构建、模拟器或设备操作。

## 版本、来源与完整性

- 自有仓库 `Caesaryuan1999/Caesaryuan1999-claw-os-ios`，获授权验证分支 `codex/verify-r2-ios02-20260918`。
- [CI31 run35364243217](https://github.com/Caesaryuan1999/Caesaryuan1999-claw-os-ios/actions/runs/35364243217)，job105662685988，来源状态为 completed/success，run、artifact、包与冷启 manifest 均对应上述完整源码 SHA。
- artifact10555953810：**49,718,962 bytes**，SHA256 `a2407c6b100a70d52ab5c995ffe2ab5d2f0184dafd8305c806be3135e03fbe25`；已独立计算，与总控取得的来源元数据相同。
- 根目录原件：`artifacts/integration/20260918/R3-ios-ci31-evidence.zip`；已提取子目录 `R3-ios-ci31-evidence/ios-01-a-20260918-154446`。
- 总控 root-review 列出的 **46 实体全部核对大小/SHA及原 ZIP 内字节相等**，包含 38 个真实 Voice 组件 JSON/PNG。另核 App ZIP 与原 artifact 内实体字节相等，并读取包内 Info.plist 的标识、版本、平台字段及可执行文件哈希。
- 本端开始时 HEAD `09631feea099b5c86eeadc69235d09623015d552`、分支 `codex/r3-20260918-ios`、tracked dirty=0，原五组 untracked 保留。此次只新增本报告和 CI31-ACCEPTANCE.json。

机器核对记录见 [CI31-ACCEPTANCE.json](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/work/r3-20260918-ios/docs/handoff/R3/CI31-ACCEPTANCE.json)，SHA256 `321455c578a30fb01033717f11070b60ee570ff13cfbf0d2beb569bf4029ffbc`；包含 46 实体清单、同模拟器信息、两种按钮状态原值和已保全包哈希。本报告不复制原图或修改原 manifest 的 PENDING_HUMAN 字段。

## 分层结果

| 范围 | 实际结果及边界 |
|---|---|
| SDK | 44 PASS / 0 FAIL / 0 SKIP |
| storage/App 三目标合计 | 188 PASS / 0 FAIL / 0 SKIP；固定 selector 对应 UIrunner175 + VLC host7 + Voice组件host6 |
| VLC/Voice 原日志 | storage.log 明确 VLCPlaybackProbeTests 7/0、VoiceLayoutTests 6/0；分别 74.632、14.694 秒。VLC 观察通过不等于所有格式网络隔离或完整视频页面通过 |
| 原生总计 | 232 PASS；方法数量不把 DB 同方法内12轮重复扩增 |
| 真实 App 离线导航 | 另计 3 PASS / 0 FAIL / 0 SKIP，不提交真实登录、注册或 OTP |
| 未签名模拟器包 | PASS；App ZIP **37,450,312 bytes**，SHA256 `66f1445024428df8fe53f1f651888086f59a243602eeaa077adb1424690dc656` |
| 独立冷启动 | PASS_COLD_LAUNCH_ONLY：同 UUID 完成就绪、安装、启动与精确进程核对，保存原 PNG |

三份 summary 均为同一 `DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9`、iPhone 16 Pro / iOS Simulator 18.5 / arm64。SDK 与 storage、navigation 的 action 时间分别为 148.059、357.397、291.946 秒；这是结果记录的 action 时间，不冒充各测试方法耗时之和。

App 包内 `CFBundleIdentifier=app.veilping.clawoschat`，版本1.22.12/build1736，`CFBundleSupportedPlatforms=[iPhoneSimulator]`，MinimumOSVersion14.0；manifest 明确未签名、不能安装 iPhone、push 为 disabled placeholder、backend 为127.0.0.1:9。包内 Tinodios 可执行文件 SHA `9a426e841b940cfe1eaf261f0cafacda059fec4a4a83fea6731f8bda5b061135` 与冷启核对值相同；不单凭该主可执行文件哈希推定整个 App bundle 相同，完整包使用上面的 ZIP 哈希。

## 冷启动原始证据与目视

同 UUID 初态 Shutdown，boot 返回0；`bootstatus -b` 返回0、耗时 **40.712513秒**，未放宽45秒门槛。原输出为 “Device already booted, nothing to do.”，随后独立 list 复核 Booted。安装返回0、安装目录属于该 UUID且二进制哈希匹配；启动前精确路径进程枚举为空，满足真正冷启动前置。

随后 launch 返回 PID **46774**；截图前后两次 process_status 均返回0，最终 state=Rs、可执行名 Tinodios，libproc 路径落在同 UUID 的已安装 Tinodios.app 内。该窗口中匹配此启动 PID 的 crash_reports 为空；这只描述本次观察窗口，不声明应用永不崩溃。

原 [冷启动 PNG](C:/Users/12287/Documents/Codex/2026-07-08/tinode-app/artifacts/integration/20260918/R3-ios-ci31-evidence/ios-01-a-20260918-154446/launch-smoke/cold-launch.png) 为1206×2622，SHA256 `6475f1d68f2d0994b2cc47512203c98f2efc77a1db4446c21ed577bc9a620dfb`。已独立查看：原 Logo、登录标题、手机号/邮箱切换、国家码/手机号/密码、登录、注册账号、找回密码与“使用原账号登录”显示；原账号入口完整可见。连接设置在首屏下缘部分露出，本次没有点击或滚动它，不由该图宣称此低频入口全程可达。

## 原 XIB 发送按钮两状态

原件位于上述 evidence 的 storage-attachments，均来自 `VoiceLayoutTests/testOriginalNibLoadsAndResetsWithoutRecording()`。

| 状态 | 原 JSON / PNG | 实际观察 |
|---|---|---|
| 文字态 | CD03E063-42F6-40C8-AC65-A051F1546DB6.json / E6E3A64C-F3B6-47A1-87E6-A24248D8FA9B.png | 本次 inputBeginEvents=1、firstResponder=true、actualInputLength=6；按钮64×48、title=发送、titleLines=1、currentImage=false。缓存 UIImageView 仍有 image，但 `hidden=true`、层级动画为空、settled=true。原图为单行“发送”，无麦克风残影或文字折行。 |
| 清空恢复 | EB3518C9-3120-4517-AA8D-C6953D642A83.json / F01FB3B0-3D83-4DEE-871F-236D31353E68.png | actualInputLength=0、按钮48×48、title空、currentImage=true；UIImageView hidden=false、settled=true。原图恢复麦克风，无残留“发送”。 |

两状态均有实际 window，delegateActions为空；测试未发送文本/录音。键盘 JSON frame 高400，但两张 PNG 是实际 UIKit 组件的裁剪图，不是整个软件键盘画面。六组件方法仍限真实 SendMessageBar/XIB 的中性 inputAccessory 容器、布局、输入、按钮 target/action 和受控 handler，不等于真实手势录音/权限弹窗、上传、发送、账号切换或完整聊天验收。

四个原实体 SHA：文字 JSON `702cbe6288f0cd072773b1877c30c7c757d183968a16b8e0b0820f098583dd08`；文字 PNG `9e6e96f19c3d53e11635e2602c5fc9ffde059119e776252d0662a655354fb56c`；清空 JSON `3ca756f9e48ca3e4dd021d3344dbd685876b821a5f7f0acfb5120b4f3b38f3cd`；清空 PNG `8d8c1d697bf221c454793e7d0d511b37c5bfdb158c032c68533fd66e2f01df6c`。

## 保留项与交付关系

CI30 整体 FAIL 和 bootstatus45秒超时原件保留，具体内部原因仍未知；CI31 同 SHA 唯一次环境复跑成功，不能倒写为 CI30 通过。CI28/29 原组件失败也保留，本轮真实文字态证据用于验收修正后的固定源码。

09631 的 FINAL-1B20EC2 包 **不重封、不修改**：其 bundle SHA仍为 `594982b21474b2092aa2470614042f5dc26b2fe1479c89a20f32977cf52a0144`，14个实体再次全部匹配。包中的 CI31 PENDING 是首次封包时点，后续实际结果由本独立验收报告补充。既有累计 patch SHA `448633865dec72f1c178dce9ff0f4690b14bdc7eed039c38b1fe91259d85580f` 不变。

仍未验真实 iPhone、Android↔iOS/多设备、正式服务、SMS/SMTP/APNs、真实用户旧库升级和完整媒体/语音旅程。不得用本次原生数量或三个导航方法推定这些验收完成。历史滚动八文件方案仍只读，未实施。
