# LOGOUT-01：退出确认与账号删除回调绑定原会话

- 前置61fd4ae482a65cbb465c455805fc792b8de350a1；2生产文件：AccountSettingsViewController.swift、SettingsSecurityViewController.swift。SDK/Store/账号hard删除范围不变。
- 两处确认框捕获页面现有SDK owner、UID与Cache.sessionGeneration；点击确认复核三者，仅调用UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)。不重新取Cache.tinode，也不要求在线鉴权，离线可退出。
- 两入口统一：标题/按钮“退出登录”，危险动作样式；提示“退出后需重新登录。本机待发送和发送结果待确认的消息将保留。”。Account退出后成功提示还需新退出世代匹配，旧确认无新账号提示。
- 删除账号确认同样绑定原owner/UID/世代；只派发owner.delCurrentUser(hard:true)。SDK成功已退休原owner，成功回调主队列只按Cache slot身份调用ifCurrent:owner，不使用active-only门禁阻断正确清理。旧owner无法清除新slot；失败提示也必须仍属原owner/UID/世代。
- 新确切调用接线检查9项，固定旧61fd4ae为0/9，新树9/9；36源策略全通过。旧auth_ui_policy的不可达Cache.tinode!=nil错误文案断言改成真实原owner门禁断言，其余保留。
- 没有新增UIKit运行时测试；沿用R2已运行的SDK/存储owner退出隔离证据，本文新增证据仅源码接线。当前累积原生期望仍128，不增加或伪称UIKit旅程通过。Mac累计CI由总控执行，未推送。
