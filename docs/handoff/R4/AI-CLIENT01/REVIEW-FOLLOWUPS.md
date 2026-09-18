# A 固定审查后继 — 当前源码6a0e858

最新源码 `6a0e8584ff9f135528f4832184eb92b3f0eeb9a3`。原初版f364及其unit.patch/13路径manifest不覆盖；此文覆盖README中的初版待修状态与19方法计数。三个修正是独立提交，仍未运行A的Swift/Mac测试。

1. **CORE夹具** `9a6f8153a6b7b7314a2abb1ee43749beabe6ad11`：只CoreListLayoutTests，以新的真实topic恢复9+，不回退SDK单调read；六方法/所有旧断言保留。真实CI35失败和两张浅色字形正证见`../UI-CORE01/CI35-FIXTURE.md`。该代码不属于A生产修改。
2. **401与序号上界** `f586434c8d8145db00c623c78028ff48a41a0603`：只有ClawAssistantService/Models/AssistantHistoryTests三路径。总控实审f364发现同源HTTP401被MIME抢先归为invalidResponse；现在先验证HTTP响应对应原URL，再优先将401送同一authorizationBlocked/清助手显示路径，不读取HTML/错误body决定身份、不普通logout。其他状态仍走原JSON严格解析、DELETE未知规则不变。序号/revision canonical十进制直接按字符串长度/字典序限制最大9223372036854775807，无浮点转换。
3. **历史行拒绝反馈** `6a0e8584ff9f135528f4832184eb92b3f0eeb9a3`：只有HistoryViewController/AssistantLayoutTests两路径。Android独立源审确证原模型.rejected在列表cell未展示；现按准确403/404错误显示“删除未完成。”及原因，原行/标题保留、读屏包含原因；pending/unknown文字与配色保持，不说已删除/网络失败。Android固定只读复核报告400e7207确认源码层P2关闭，非Mac执行结果。

新增原生现在 **15 History + 6 Layout = 21**（初版19个全部保留），原Core仍6。累计计划SDK44 + storage225 = **269原生 + 导航3**。401新增方法由真实URLSession delegate/URLProtocol分别提供text/html与缺MIME响应，验证同一History/Scope封闭而SDK和真实Store UID保持；原decimal方法追加最大值实际DTO成功、max+1拒绝且旧完整快照保留。列表拒绝新增方法由实际HTTP→History→原UITableViewCell，检查403/404原行与可见AX中文/读屏并存PNG。没有新增fake状态模型或削弱原方法断言。

限定本地证据：每个后继源码diffcheck PASS；真实源码比较保留原19方法/所有旧assertion行；CORE原六方法/断言保持；原SDK/DB/Pod/workflow/selector相对f364没有变化。第一次方法名比较命令写错了Python正则转义而失败，纠正检查表达式后按明确14→15、5→6计数通过；未改源码或断言来修检查器。Windows没有Swift，不能把检查结果称新增原生通过。原44策略绿色对应初版接线；这些窄修未改旧策略，不重复跑无关整套。

## 原包与三个独立后继

先从准确d21继承基线应用初版`unit.patch`得到f364的源码；再按下表顺序应用三个Git原字节后继。只在独立副本做`git apply --check`后应用，不reset/clean、不覆盖有WIP目录；回退按相反顺序逐包`-R --check`后反向应用。没有DB迁移或持久草稿格式变化。

| 补丁 | 路径/字节 | SHA256 |
|---|---:|---|
| successor-9a6f815.patch | 1 / 1133 | 203bf174f50db3d328fbcd8064fd6d4ef75a06b35e5cbf2e4f0a1caf3897a227 |
| successor-f586434.patch | 3 / 6452 | 54c186e1e4495d51764292fa8e64d7a211ea1ae51136f7c00dbe88903611cd82 |
| successor-6a0e858.patch | 2 / 4718 | 50abe0f392a55338ea22c05a97515b8e8320f48c689697c4a11f44d8e020b260 |

`seal_followups.py`实际在新的私有index以f364read-tree，逐一check+apply三补丁；全部6路径mode/blob等于6a目标，所有未选路径等于原f364，原index摘要不变。源码overlay tree `6f4f5aff79a45c15b9f84fc79717e3969bd98dd9`；它刻意不含途中纯文档提交，不能称6a全提交tree。原patch上下文空白原样保留，文档diffcheck排除patch实体，源码delta本身全部diffcheck通过。

封存后仅总控可决定精确Mac候选与CI。既有A限制仍在：无POST/run/SSE/provider/客服，合成HTTP与真实页面组件测试不是真实账号联机/完整聊天/人工确认点击，完整跨设备/签名发行没有通过。
