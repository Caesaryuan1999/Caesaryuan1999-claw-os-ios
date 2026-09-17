# PUBLIC-02 — 精确公开目录与过期结果门禁

前置提交：557d90092a52d02f89409b90396a788300528e61。合同：根 PROTOCOL_CONTRACT R3-PUBLIC-02。4 个生产文件，5 个测试/工程接线文件；无 DB/schema/SDK/C3/身份协议变更，未读取或提交私有配置。

## 实际行为
- Utils.AccountNames：边缘空白与单个 @ 规范化后转小写。只接受完整 ASCII 标识；逗号/冒号/内嵌空白/邮箱/电话加号等表达式拒绝。usr 前缀且符合已有 alias 格式的输入只生成 alias:值；普通完整值生成有效 alias 与历史 basic 词项，不附带裸值。
- 精确匹配只接受此次 query 对应的公开 tag。usr 外形只凭相同 alias；绝不将输入当 UID 建会话。实际持久化和跳转使用响应返回的 P2P user/topic；含互相矛盾 user/topic 的订阅拒绝。
- ClawPublicDirectoryLookup 同时绑定输入、SDK 对象与请求世代；AddByID、Find 响应接收与保存前实际调用 consume。输入改变、离页、新查询会使旧 ticket 失效，输入改回原文字也不能恢复旧请求。
- Find 只消费该 getMeta promise 的实际 meta.sub，不消费无 query 归属的 fnd 缓存事件。setMeta 完成且 ticket 有效才 getMeta。可见远端结果、点击与保存完成后路由再次核对同一 query/owner；保存仍需 P2P 订阅成功。
- Find 查询状态及点击消费由主队列串行；旧私有队列中跨队列未同步 searchQuery 被移除。本地昵称/公开号子串筛选保留。主队列现执行已有本地联系人读取，尚无大通讯录性能测量。
- AddByID 二维码/裸 UID 直连路径继续关闭。公开查找不修改内部受控批量查询。

## 验证
- 35/35 Windows 源码/SQL策略脚本通过，diff --check 通过。初始33/34失败报告保留：旧 group_flow_policy 依赖 topicUnwrapped 变量名与文本函数顺序，现检查真实新路径（订阅成功→主队列 finish→门禁→保存）；其余群角色/创建断言保留。
- 新增 PublicDirectoryTests 12 个原生方法，编译实际 Utils 的 AccountNames/ClawPublicDirectoryLookup，SDK FndSubscription 使用真实 JSONDecoder 解码；消费 action 观察保存副作用，非复制实现。
- 用例：UID外形alias/legacy basic/表达式拒绝/公开号显示/服务返回UID/无精确alias拒绝/非用户拒绝/键入即失效/同字新请求/跨SDK/非法新query/消费回调不持内部锁。
- pbxproj 仅 UITests 定义 CLAW_PUBLIC_DIRECTORY_TESTS，把同一生产 helper 编译到原生目标；App 继续编译整个 Utils。CI只追加 PublicDirectoryTests，既有选择项未删除。
- 本次累积原生期望 125 方法：SDK26、DB49、AUTH29、Removal9、PUBLIC12。Windows未运行Swift/App/模拟器；最终Mac CI与真实联系人联机待总控，未声称已通过。

## 剩余边界
原生12方法验证实际查询构造/消费门禁，尚非真实 UIKit 点击旅程；目录缓存SDK仍可持有别的查询结果，但本轮可见/保存路径不以其作证。消息、认证、数据库迁移保持原实现。
