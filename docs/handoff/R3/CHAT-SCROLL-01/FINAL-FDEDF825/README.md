# CHAT-SCROLL-01 · fdedf825 单元源码包

起点 `0a54fcf1ecb35a6f3511815ed59c7750f692ea2d`（生产/CI 基线仍为已通过 CI31 的 `1b20ec2971061dbc002d1748f0f252d87b69d0f7`）；目标 `fdedf825490ea9fa420b54033e8c48d65f8fc8aa`。先实施 `0a3c145d2f5c8d8d27b578617d206c17ddb1ef87`，后以 `fdedf825` 修正取消交互返回过早退休。旧候选及旧临时包均保留。

`unit.patch` 包含完整 13 路径：9 生产文件、1 个新 ChatScrollTests 文件、pbxproj 测试成员、既有 CI 脚本的一条 selector，以及品牌源策略的一条已批准文字按钮断言替换。`unit-package.json` 逐项列目标 Git mode/blob/原始 Git 字节 SHA256，不包含文档、私有配置、SharedUtils、签名/推送、Pods/build/runtime 或历史 WIP；不是从空上游重建。

`package_unit.py` 复用本单元既有流程：严格核非 docs 差异恰为这 13 项，以独立 GIT_INDEX_FILE 读入完整起点、先 `git apply --cached --check` 再真实应用，核所有目标 mode/blob 和其余起点条目不变，最后确认原工作索引未变。它不会改当前源码；重复执行会产生新的隔离临时索引。

`line-endings.json` 区分本地工作文件 SHA 与 Git 字节 SHA：0a3 原报告的 `sha256` 是 raw 工作文件，`gitBlob` 是 clean 后 blob，不应相互混用。原 13 个 blob ID 均匹配 0a3；后继没改的 11 个 raw SHA 仍精确匹配。FilePreview 实际含 156 个 CRLF 和 4 个裸 LF，规范 CRLF→LF 后逐字等固定 blob。当前 13 项全部经同样字节核对等于 fdedf825，两个后继修改项未冒称旧 raw SHA 相等；没有修改行尾来迎合报告。

Windows 证据：44/44 既有源策略、原 20 项源接线检查、后继 7 项限定绑定及实际索引正向应用；后继取消交互对照的 10 个 App-hosted 方法尚待 Mac。原 232 回归与导航 3 保留，下一候选期望为 **242 原生 + 导航 3**，本包不提升验证等级。CI31 的 232+3/打包/冷启动结果只属于旧 1b20，不覆盖本滚动单元。

总控于 2026-09-19 01:09:29 按既有授权推送精确 fdedf825 并派发 CI32（HTTP 204）。封包时 run 尚未登记、原生与打包/冷启动结果 PENDING；后继文档提交不是 CI 来源。`unit.patch` 的原始 Git diff 上下文可能含既有缩进空白，不能把补丁文件自身作为新增源码逐行 whitespace 检查并重写上下文；验证的是目标源 diff 与实际正向应用。

在另一个精确起点的独立 checkout 中，保留私有配置和现有数据后执行：

```powershell
rtk proxy git apply --check <absolute-path-to-unit.patch>
rtk proxy git apply <absolute-path-to-unit.patch>
```

应用后按清单核每一项 blob/mode，再由获授权总控执行 Mac CI。没有 schema 变更，不删除数据库。回退应使用保全起点/CI31 源包的独立 checkout 与原私有配置，不 reset/clean 本树，不以带取消返回反例的 0a3 作为运行验收版本。

运行和设备边界见上级 `REPORT.md` / `CANCELLED-POP.md`：测试采用真实 MessageVC 消费者与 UICollectionView、中性 cell/FlowLayout，受控取消回调不是系统手势；没有登录、发送、已读或完整消息气泡旅程验收。包中没有可安装 iPhone 发行产物。
