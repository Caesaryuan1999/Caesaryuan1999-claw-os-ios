# UX-DEL — explicit conversation/group removal

Parent: 9f591cc78eddea8f2ef3e97746def55939bdb185.
Three business production files: ChatListViewController.swift, ChatListInteractor.swift, TopicSecurityViewController.swift.
Two approved test-wiring files: project.pbxproj and existing Mac CI script.
Supporting files: ConversationRemovalTests.swift, updated old group-flow source policy, four report/evidence files. No SDK/DB/wire/C3 changes.

List swipe: only P2P has “删除会话”, with dangerous confirmation “将从你的账号中移除此会话，并同步到你的其他设备。” Full swipe never triggers the first action. Group rows retain archive; entry remains group→chat top information→existing management/security page. Confirmations capture the actual topic object, not a possibly moved indexPath.
The interactor rejects any non-P2P removal and invokes the same production actor/topic/action permit before dispatch.

Existing TopicSecurity page: non-owner group users see “退出群聊”; actual owners see “解散群组”. Both have separate consequences and confirmation. Confirmation execution checks captured account/topic object identity plus current type and ownership again; admin/manager is not owner.
Member exit routes to existing Topic.leave(unsub:true), while explicit owner dissolve routes to delete(hard:true). This distinction also prevents a late server-side ownership promotion from turning exit intent into dissolution: the server rejects owner unsubscribe. Offline/not-attached/rejected operations retain the page and explain retry after reconnect/reopening chat; no automatic attach or destructive retry is added.
Saved messages keep a separate typed action and cannot reuse that confirmation for a group.

Actual service semantics checked read-only in R3 backend: hub.go405–438/483–530 treats ordinary non-owner deletion as unsubscribe and notifies the user's other sessions; last remaining P2P subscription can cause complete topic cleanup (hub.go405/486–488). Therefore this is not a purely local hide and the product copy does not promise retaining remote history. topic.go replyLeaveUnsub rejects owner exit. Server permissions remain final authority.

The Foundation ClawConversationRemovalPermit lives in the production TopicSecurity source. App compiles the full file; the existing native UITests target compiles the same file with CLAW_DESTRUCTIVE_POLICY_TESTS, excluding only UIKit controller declarations. No replacement implementation is copied into tests.
Nine prepared native methods cover exact P2P/leave/dissolve/saved dispatch routes, old account, replaced topic object, promoted member, transferred owner, admin without ownership, and unknown type. Added selector preserves all R2 and AUTH tests. Expected prepared native total: 71 R2 + 26 AUTH + 9 removal = 106.

Windows: initial old source policy 32/33 due renamed stronger guard/API; updated that policy to require group+nonowner and actual unsubscribe route. Final 33/33; 15 source/wiring checks PASS; diff-check PASS. Nine Swift methods NOT_RUN on this worker; no UIKit gesture, actual SDK dispatch/server or device acceptance claimed.
Root R3 CI1 at 7f0b8a4 failed parsing generated license XML before Swift; it is not evidence for this batch. License source repair is next, independently committed.
