# iOS 自动失效与 Android2094 差距 — 窄范围修复

## 原因与范围

原基线 `79f015f47b15fd7124f81d52205de5c5508f370e`，本地提交 `92208c6a5078ab4d8c92e9e84d069a17ee20e19d` + 独立复核后继 `3d9498144a8ea95a5d581d777e6b78a246128ebc`。两生产文件：`Tinodios/UiUtils.swift`、`Tinodios/ChatListInteractor.swift`，合计+24/-11；另加一个源契约测试。不改变 Store/SDK/消息格式/数据库版本/主动退出或注销语义，不推送。

IOS-DQA-AUTH-01：UiUtils.attachToMeTopic 的 thenCatch 对401/403返回nil。真实 PromisedReply.swift:203–239明确把 failure handler 的nil作为恢复成功，因而 ChatListInteractor 的401/403/404失败分支接不到这些拒绝，反而执行成功呈现。重连登录被401拒绝后，ChatEventListener.onLogin 又尝试 me 订阅；此订阅失败被吞时，用户可能停留在无法继续通讯的页面。此结论是当前生产调用链与 Promise 实现的源码因果，不是本轮 iPhone 复现。

IOS-DQA-AUTH-02：同一 helper 的404调用无 owner 的 logoutAndRouteToLoginVC，502直接取新的 Cache.tinode。若原 Promise 已完成但消费者尚未注册，账号在这两个操作间替换，PromisedReply.then 会稍后同步执行原错误，旧请求就可能作用新账号。SDK 对未结束会话的 dispatch 锁不覆盖“已完成 Promise 后来注册消费者”的窗口。成功回调也未检查原 owner，可能更新新会话。

修复：helper接受调用方捕获的 owner；401/403/404只向该 owner 执行失效退登，502在 Cache.ifCurrent 原 owner门禁中重连；失败返回相同 Error 的 rejected Promise。ChatListInteractor 传原owner，成功呈现与失败退登均使用原owner。没有通过泛化为网络错误掩盖拒绝；没有更改消息成功/已读含义。

IOS-DQA-AUTH-03（独立复核）：92208c6传播原错误后，原SDK的me若已由MessageInteractor.onLogin附着，ChatList自身meTopic仍可能为空；带非空get再次调用Topic.subscribe:600–608会得到本地alreadySubscribed，ChatList就不能保存该me引用。3d949814在绑定listener之后检查attached并幂等返回成功，采用同一个me对象且不再订阅。静态新增项8/9红→9/9绿，见auth-attached-{red,green}-source.json。原401/403拒绝语义保持；不能单独集成92208c6而漏掉后继。

## 不应套用 Android 根因

当前 iOS 的 AppDelegate 启动失效、Cache.invalidate、Tinode.logout 到 SqlStore.logout 最终调用 BaseDb.logout。BaseDb.swift:167–185执行 `UPDATE accounts SET last_active=0,device_id=NULL WHERE id=? AND uid=?`，保留消息、会话、账号行、待发送与未知结果。BaseDb.deleteUid 的 DELETE 另由确认注销路径触发；SDK finishAccountDeletion 要求对应请求的200回复及原账号仍匹配。因此不能报告“iOS同样自动清库”，也不应为修复本问题重写数据库。

Cache.ifCurrent使用 SDK session 锁后取 Cache 锁，检查实例；invalidate退休旧SDK并增加generation。SDK sessionClosed 拦截旧 login/dispatch。这些已有保护保留。本批只补漏掉 owner 的订阅消费者。

与 Android2094 尚未对齐：iOS accounts 仍只按 uid 唯一，Keychain token没有持久 origin 绑定；SharedUtils.setConnectionSettings 能改变host，connectDefault读新的设置，没有 Android 新补丁同等的发送前原 host 校验。跨host配置/同UID缓存隔离应另开有迁移/兼容验收的单元；本批未修改，未在真实账号尝试。当前两文件修复不能关闭这一缺口。

## 实际检查与可复现命令

工作目录为本树根；所有命令遵从用户RTK前缀。

```powershell
rtk python -X utf8 Scripts/ci/test_me_subscription_owner_policy.py --source-ref 79f015f47b15fd7124f81d52205de5c5508f370e
rtk python -X utf8 Scripts/ci/test_me_subscription_owner_policy.py
rtk python -X utf8 -B Scripts/ci/run_static_policies.py --report <新输出文件.json>
rtk git diff 79f015f4 3d949814 --check
```

本轮第一条红源在修改前执行：8条中2过、6失败，exit1，`auth-red-source.json`。修补后8/8、exit0，`auth-green-source.json`。原有加新增源/SQLite策略脚本45/45、exit0，`static-after-auth.json`。这是源码接线和宿主SQLite检查，不是Swift编译、UIKit、模拟器或设备测试。

`run_me_subscription_fixture.py` 提取原函数原文及完整生产PromisedReply，不翻译其逻辑；`me_subscription_fixture.swift`控制Cache、网络/页面副作用，明确不覆盖真实锁/Keychain/数据库。最终17个确定性用例包含当前/旧owner 401/403/404、502重连、500保留拒绝、成功/失败呈现、同me引用/绑定listener/0额外subscribe/重复attach。已生成基线与修补候选输入及SHA，早期14例的`native-fixture-{red,green}-prepared/result.json`及最终`native-fixture-final-prepared/result.json`均 **NOT_RUN**：本机无swiftc。没有把准备用例数写成通过数。

在有Swift/Foundation的Mac上，从本树执行（输出目录须不存在）：

```bash
python3 docs/handoff/DEVICE-QA20260927/run_me_subscription_fixture.py --source-ref 79f015f47b15fd7124f81d52205de5c5508f370e --execute --output /tmp/claw-me-owner-red-unique
python3 docs/handoff/DEVICE-QA20260927/run_me_subscription_fixture.py --source-ref 3d9498144a8ea95a5d581d777e6b78a246128ebc --execute --output /tmp/claw-me-owner-green-unique
```

还需iOS完整编译和真实UIKit失效重登；同run CI51 attempt2固定0877，**不包含**本修补。关闭条件：独立源审、上述真实Swift红/绿、对应候选App编译、同账号历史/待发保留、旧回调不影响新会话、主动退出不回归。当前状态为源码修复完成、原生未验证，不能据此发版。

## 集成与回退

总控在已保全的iOS集成树依次审 `git show 92208c6a`、`git show 3d949814`，无冲突后按此顺序集成；本目录报告与CI原始结果另存。已有主树未改，无需覆盖定制。若该修补造成回归，在独立集成树审查后先revert 3d949814、再revert 92208c6a，保留历史证据；不 reset、clean 或撤销既有数据库保护。恢复后的旧认证吞错问题仍须标记开放。
