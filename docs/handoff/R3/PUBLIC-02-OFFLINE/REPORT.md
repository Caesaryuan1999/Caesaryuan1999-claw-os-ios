# PUBLIC-02-OFFLINE：离线原账号本地联系人保留

- 前置80d17a0f50e6cfe67e772d5970de58b7dbe0eb5e。2生产文件 FindInteractor.swift、Utils.swift，1原生测试文件、1策略接线更新。
- 已确认回归：PUBLIC02本地fetch错误要求isConnectionAuthenticated；正常断连SDK清该状态、保留本地账号，随后页面刷新清空联系人。本次仅改本地读取；对Find源码扣除fetchLocalContacts区段后直接文本比较完全相同，远程查询/保存鉴权、排序、分页与展示流程未改。
- Find在原Cache.ifCurrent(owner)原子门禁中实际调用ClawLocalContactRead；helper不看网络状态，读取前后都要求页面active、SDK未退休、slot身份当前，以及owner.myUid==owner.store.myUid。账号切换期间取得的结果不能返回给旧owner。保持原ContactsManager读取和过滤，不添加批量载入。
- 新增2原生方法使用既有非空113夹具、真实BaseDb/SqlStore/UserDb与Tinode。用真实TinodeConnectionListener.onDisconnect通知SDK断连，观察authenticated=false但账号仍A，再调用同生产helper读取真实A联系人；store.logout后不调用records。
- 第二方法真实切到B，检查旧A/替换slot/页面inactive拒绝、B离线只读B、SDK退出后拒绝；在records回调中注入真实账号切换，验证读取后的第二次门禁丢弃原结果。没有手写联系人数组替代DB结果。
- 测试仅以可控slot身份闭包替代Cache单例；生产仍在真实Cache.ifCurrent锁内，未宣称UIKit或实际Cache对象已在本测试运行。原生方法尚未Mac执行。
- Windows36源策略通过；diff --check通过；本地fetch以外Find字节文本等价。累积原生期望130（SDK26/DB53/AUTH29/Removal9/PUBLIC13）。没有自行push；CI4 fd7d0c不含本批且不作本批证据。
