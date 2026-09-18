# FINAL-56C4A7F 候选范围（尚未封包）

## 固定基线与证据门槛

- R3 基线：`34a8b3e5ad4df210117e2e03b308576796ba55b2`。
- 拟交付源码树：`56c4a7f609cd0103a9b26604fb404d319f97ed48`，不取本端后续文档 HEAD 作为代码版本。
- 生产源码仍等于 `d381e074fd1ede395f6c21a658f37020661acd78`；已核 TinodeSDK、Tinodios、TinodiosDB、Podfile/lock 在这两提交之间无差异。
- 总控报告 CI14 run `35316061181` / job `105507851181` success；artifact `10535962231`，36,775,227 字节，SHA-256 `c35c2b34777b97795aeb1dd05d2de9e0d17f6f470ff6cc5157d6b2951a44bbf4`。产物与截图仍待总控最终核验通知。
- 本文仅清单。尚未创建 FINAL-56C4A7F 目录、生成新补丁或执行正向恢复；不重复构建或运行无关检查。

## 范围核对

- 拟纳入 **84 文件：59 修改、25 新增，无删除**。
- 覆盖基线到56候选的 **全部81个非docs差异文件**，没有遗漏的非docs差异。
- 另明确纳入 docs 下3个安全可执行回归脚本；它们是验证代码，不能当普通报告排除。
- 相对 FINAL-D381E07 的83文件集合，仅新增 IdentityNavigationUITests.swift；不删除旧集合文件。
- 基线到56候选的143个其他docs差异为报告/证据/旧交付包，不混入源码补丁。
- SharedUtils.swift 在基线到56候选无差异，仅查询Git差异元数据，没有读取私有内容；仍明确排除。
- runtime、私有配置、GoogleService实际配置、签名/密钥、pycache、派生build/Pods、报告、截图、下载产物和旧补丁均不纳入。未变的基线依赖不复制为新差异。

## 相对 d381 需要更新的7个包内文件

- `579014c`：补齐SDK测试control fixture必需ts，未改生产解析和业务断言。
- `a06f49a`：新增3个真实App离线导航方法、工程与独立CI结果/上传接线。
- `56c4a7f`：冷启动进程前置确认、原始附件导出和受控runner回归。

| 包内增量文件 | 说明 |
| --- | --- |
| `.github/workflows/ios-smoke.yml` | 在旧包文件集合内更新 |
| `Scripts/ci/smoke_simulator_launch.py` | 在旧包文件集合内更新 |
| `Scripts/ci/verify_publish_outcomes_macos.sh` | 在旧包文件集合内更新 |
| `TinodeSDKTests/TinodeSDKTests.swift` | 在旧包文件集合内更新 |
| `Tinodios.xcodeproj/project.pbxproj` | 在旧包文件集合内更新 |
| `TinodiosUITests/IdentityNavigationUITests.swift` | 新增 |
| `docs/handoff/R3/CI-SMOKE/check_smoke_runner.py` | 在旧包文件集合内更新 |

## 完整候选白名单

| 操作 | 路径 |
| --- | --- |
| M | `.github/workflows/ios-smoke.yml` |
| M | `Podfile` |
| A | `Scripts/ci/prepare_license_plist.py` |
| A | `Scripts/ci/smoke_simulator_launch.py` |
| M | `Scripts/ci/test_active_contacts_layout_policy.py` |
| M | `Scripts/ci/test_auth_ui_policy.py` |
| M | `Scripts/ci/test_brand_ui_policy.py` |
| M | `Scripts/ci/test_chat_list_branding_policy.py` |
| M | `Scripts/ci/test_compact_message_layout_policy.py` |
| A | `Scripts/ci/test_db_initialization_gate_policy.py` |
| A | `Scripts/ci/test_db_live_diagnostics_policy.py` |
| A | `Scripts/ci/test_delete_account_ack_policy.py` |
| M | `Scripts/ci/test_figma_visual_contract_policy.py` |
| M | `Scripts/ci/test_group_flow_policy.py` |
| A | `Scripts/ci/test_group_note_policy.py` |
| A | `Scripts/ci/test_license_plist.py` |
| A | `Scripts/ci/test_local_account_delete_policy.py` |
| A | `Scripts/ci/test_logout_owner_policy.py` |
| M | `Scripts/ci/test_message_background_policy.py` |
| M | `Scripts/ci/test_notification_settings_policy.py` |
| A | `Scripts/ci/test_owned_image_policy.py` |
| M | `Scripts/ci/test_premium_secondary_ui_policy.py` |
| A | `Scripts/ci/test_public_directory_policy.py` |
| A | `Scripts/ci/test_sdk_inbound_log_policy.py` |
| A | `Scripts/ci/test_secondary_ui_policy.py` |
| M | `Scripts/ci/test_signup_registration_policy.py` |
| M | `Scripts/ci/test_topic_info_layout_policy.py` |
| M | `Scripts/ci/verify_publish_outcomes_macos.sh` |
| M | `TinodeSDK/Tinode.swift` |
| M | `TinodeSDK/model/Types.swift` |
| M | `TinodeSDKTests/TinodeSDKTests.swift` |
| M | `Tinodios.xcodeproj/project.pbxproj` |
| M | `Tinodios/AccountGeneralSettingsViewController.swift` |
| M | `Tinodios/AccountSettingsViewController.swift` |
| M | `Tinodios/AddByIDViewController.swift` |
| M | `Tinodios/Base.lproj/Main.storyboard` |
| M | `Tinodios/ChatListInteractor.swift` |
| M | `Tinodios/ChatListViewController.swift` |
| A | `Tinodios/ClawIdentityFlow.swift` |
| A | `Tinodios/ClawIdentityService.swift` |
| A | `Tinodios/ClawSecondaryUIState.swift` |
| M | `Tinodios/CredentialsChangeViewController.swift` |
| M | `Tinodios/CredentialsViewController.swift` |
| M | `Tinodios/FilePreviewController.swift` |
| M | `Tinodios/FindInteractor.swift` |
| M | `Tinodios/FindViewController.swift` |
| M | `Tinodios/ImagePreviewController.swift` |
| M | `Tinodios/LoginViewController.swift` |
| M | `Tinodios/MessageViewController+SendMessageBarDelegate.swift` |
| M | `Tinodios/MessageViewController.swift` |
| M | `Tinodios/NewChatTabController.swift` |
| M | `Tinodios/ResetPasswordViewController.swift` |
| M | `Tinodios/Settings.bundle/Acknowledgements.plist` |
| M | `Tinodios/SettingsHelpViewController.swift` |
| M | `Tinodios/SettingsNotificationsViewController.swift` |
| M | `Tinodios/SettingsSecurityViewController.swift` |
| M | `Tinodios/SignupViewController.swift` |
| M | `Tinodios/TopicGeneralViewController.swift` |
| M | `Tinodios/TopicInfoViewController.swift` |
| M | `Tinodios/TopicSecurityViewController.swift` |
| M | `Tinodios/Utils.swift` |
| M | `Tinodios/format/AsyncImageTextAttachment.swift` |
| M | `Tinodios/format/ThumbnailTransformer.swift` |
| M | `Tinodios/widgets/ChatListViewCell.swift` |
| M | `Tinodios/widgets/ChatListViewCell.xib` |
| M | `Tinodios/widgets/ContactViewCell.swift` |
| M | `Tinodios/widgets/ContactViewCell.xib` |
| M | `Tinodios/widgets/RoundImageView.swift` |
| M | `Tinodios/widgets/SendMessageBar.swift` |
| M | `Tinodios/widgets/SendMessageBar.xib` |
| M | `Tinodios/zh-Hans.lproj/Main.strings` |
| M | `TinodiosDB/BaseDb.swift` |
| M | `TinodiosDB/SqlStore.swift` |
| M | `TinodiosDB/UserDb.swift` |
| A | `TinodiosUITests/ConversationRemovalTests.swift` |
| A | `TinodiosUITests/IdentityFlowTests.swift` |
| A | `TinodiosUITests/IdentityNavigationUITests.swift` |
| A | `TinodiosUITests/OwnedImageTests.swift` |
| A | `TinodiosUITests/PublicDirectoryTests.swift` |
| A | `TinodiosUITests/SecondaryUIStateTests.swift` |
| M | `TinodiosUITests/TinodiosUITests.swift` |
| A | `docs/handoff/R3/CI-SMOKE/check_smoke_runner.py` |
| A | `docs/handoff/R3/LOCAL-DELETE-PLAN/reproduce_partial_delete.py` |
| A | `docs/handoff/R3/LOCAL-DELETE/check_local_delete_sqlite.py` |

## 总控核验后才执行的封存步骤

1. 从固定Git对象34a8b3e与56c4a7f生成上述84文件的binary/full-index补丁，保留真实新增文件元数据和原始字节行尾；不从当前文档HEAD或工作树推断代码版本。
2. 在独立临时目录，仅用白名单中的安全基线文件重建起点；执行正向git apply --check与实际apply，核对84文件Git目标字节SHA、mode和blob，不以reverse --check代替。
3. 保留旧FINAL-D381E07和更早包，新增FINAL-56C4A7F；逐文件manifest与包哈希明确记录固定source_commit。
4. 更新实际方法清单为181原生加3真实App导航，单列35受控Python与44源政策；CI14的export/PNG/进程事实仅以根已核证据写入。
5. 生产能力、模拟器、真实服务/OTP、推送、签名、真机以及全量UI旅程继续分别报告，不由CI成功外推。
