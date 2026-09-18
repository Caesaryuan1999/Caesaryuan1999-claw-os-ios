# CI39 测试夹具后继恢复包

唯一补丁路径是 `TinodiosUITests/AssistantStreamTests.swift`。准确基线 `b004af0d5c5d8ce2f7560fad04ed8711694c8e23`，源码目标 `34b675e7f1db76c90ca112e0f2588f1ddfb97696`。只将原连接 handler 移到 NWListener.start 前，生产代码、七个方法、断言、时限和测试选择均不变。

`test-only.patch` 为 Git 原始 binary/full-index diff，1335字节，SHA256 `05f48b74e0288cc3683c7f0f2afbf6ab6d0a3b37e4fed73fafd5e1de9c37e9bf`。不重写空白或行尾。准确 mode/blob/源码 SHA 见 `manifest.json`；包实体 hash 见 `bundle-hashes.json`。

## 应用顺序

在已保全的独立源码副本逐段恢复，不在原 dirty 树 reset/clean，也不覆盖私有配置：

1. 原 `AI-CLIENT-B01/unit.patch`：cf63be2 → 02e4ebc。
2. 原 `a-page-order.patch`：02e4ebc → 3cb5519。
3. 原 `b-successor.patch`：3cb5519 → e9eba40。
4. 原 `core-title.patch`：e9eba40 → b004af0。
5. 本包 `test-only.patch`：b004af0 → 34b675e 的唯一测试路径。

前四段原补丁、manifest 与 bundle 全部保留，本包不重封它们。前四段完成后必须先核本测试文件原 blob 为 `f4cda80ea203957c8a9d8f9ce5ffc2ed4e1008c7`，SHA256 `51b1a7b8e4c28a8f8808b9d36f8df4cf4459edca4b1f71eb9f0117a822c53b47`；不适用于未知源码或未合入前置修正的副本。

在准确副本中依次执行 `rtk git apply --check <本包test-only.patch绝对路径>`、`rtk git apply --binary <本包test-only.patch绝对路径>`。之后核目标文件 mode100644 / blob `279f5699f5c7b9d1fc095841469921add7ac2ff3` / SHA256 `944c08471fdd5889584b0f064a38c4a2bc05c3c4211ea9c2bb3a6c38af76e221`；文件仍20538字节。

## 实际正向恢复验证

已创建新的私有临时 `GIT_INDEX_FILE`，实际运行 `git read-tree b004完整SHA` → `git apply --cached --check --binary PATCH` → `git apply --cached --binary PATCH` → `git write-tree`，没有仅以 reverse-check 替代。

结果树 `596d683a0a53da5312018d8662976d9dddb9ba7c`，947条完整树记录逐项 mode/type/blob 等于“原 b004 树仅替换此测试文件”；553条全部非 docs 记录与34b目标一致；其余946条条目未变。34b中后加的交接 docs 不在本源码补丁内，所以不冒称完整树等于34b文档树。原工作树 index hash 在验证前后完全相同，原包 bundle hash 也未变化。

## CI 与交付边界

CI39 b004/run35402042528：SDK44通过、storage245通过/4失败，合计289通过/4失败/0跳过。四项均为监听器尚无 connection handler 导致 fixture 初始化失败，没有到达真实 HTTP/SSE/60秒测试。原日志与 ZIP/hash 见上一级 `REPORT.md` / `source-checks.json`，未覆盖原红。

总控已非强推34b并启动 CI40/run35403779991/job105789172452；封包时仍 **PENDING**，SDK44初步已通过，其他待验。293原生+3导航是期望，不是本包新增运行证据。这个恢复检查不是 Swift 编译、Mac原生、真实模型、设备或跨端验收；本窗口未推送/触发 CI，也未重复运行 native。

本包不是可安装 App，没有重打模拟器包。需要运行时由总控对34b准确候选执行既有免签 CI，并单独验收其产物；不能用旧安装包冒充此修正。本次无 DB/协议/权限/生产配置变化。若仅回退此测试修正，在保全副本核目标字节后使用本补丁 `--reverse --check` 再反向应用；这只恢复测试，不撤销或降级任何账号数据库。

B02仍未实施。后继提案已明确 user32000 / assistant262144 UTF-8 字节，生成/journal前置仍开放，不能因恢复包通过而启用生成 UI。
