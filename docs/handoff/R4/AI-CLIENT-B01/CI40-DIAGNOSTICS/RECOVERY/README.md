# 第六段：CI40 诊断候选测试恢复包

基线 `34b675e7f1db76c90ca112e0f2588f1ddfb97696`，目标源码 `6d36bd8450ad61dabf5872c7e7709238c3cb85f6`。唯一补丁路径 `TinodiosUITests/AssistantStreamTests.swift`；生产、原7方法数量、7组响应字节、全部原断言、5秒与60秒期限保持。本包只恢复已审诊断记录，不宣称修复原超时。

`test-only.patch` 是未经空白/行尾重写的原 Git binary/full-index diff：8379字节，SHA256 `2ae09bd4348360ca9ee6f6a16d2f9bf55d52b8ab66003ec2b11af64c2fcf6b42`。源文件 mode/blob/SHA、正向恢复和既有包保全值在 `manifest.json`；本包实体 hash 在 `bundle-hashes.json`。不含 docs 源差异、runtime、凭据、签名、私有配置、Pods、build 或大体积CI原件。

## 准确恢复链

以下路径均以 `docs/handoff/R4/AI-CLIENT-B01` 为前缀，必须先具备各段要求的保全源，不在原 dirty 工作树 reset/clean：

1. `unit.patch`：cf63be2 → 02e4ebc。
2. `a-page-order.patch`：02e4ebc → 3cb5519。
3. `b-successor.patch`：3cb5519 → e9eba40。
4. `core-title.patch`：e9eba40 → b004af0。
5. `CI39-FIXTURE/RECOVERY/test-only.patch`：b004af0 → 34b675e 的测试源码。
6. 本目录 `CI40-DIAGNOSTICS/RECOVERY/test-only.patch`：34b675e → 6d36bd8 的测试源码。

前五段及旧 bundle 原字节保留，不在本次重新生成。docs 提交不是额外源码依赖；逐段还原须使全部非 docs 源条目一致，无须为了套补丁覆盖本地文档或私有文件。

在准确的独立副本先核原测试文件 mode100644 / blob `279f5699f5c7b9d1fc095841469921add7ac2ff3` / SHA256 `944c08471fdd5889584b0f064a38c4a2bc05c3c4211ea9c2bb3a6c38af76e221`（20538字节）。执行 `rtk git apply --check <本包test-only.patch绝对路径>`，再执行 `rtk git apply --binary <本包test-only.patch绝对路径>`。目标 mode100644 / blob `917eb56a0677f42e697131b39851450e756bcf30` / SHA256 `33d5b1a20dcbbcf8ba00c0e85a44058a8b1ea5eb096edbc2636c27a859246bfb`（24664字节）。

## 已实际执行的恢复验证

新临时私有 `GIT_INDEX_FILE` 内真实 `read-tree 34b完整SHA` → `apply --cached --check --binary` → `apply --cached --binary` → `write-tree`，得到树 `cfc5202cf0c8a68897b965a7bcb99b2baa4e88b3`。975条完整树记录等于基线仅替换这个测试文件，974条未选条目原样；553条全部非 docs 的 mode/type/blob 与6d36一致。基线文档保留，所以不把该树冒称6d36包含后继文档的完整提交树。原工作树 index 在此验证前后 hash 一致。

这是真实正向应用，不是只做反向检查；没有编译、运行 native 或创建可安装 App。本次不改数据库/协议/权限。若回退此诊断，在保全副本核目标字节后按本补丁 `--reverse --check` 再反向应用，仅恢复测试文件，不进行账号或数据库降级。

## 原失败与候选验证

CI40 固定34b，run35403779991/job105789172452：292通过/1失败/0跳过。真实60秒等方法已执行，但拒绝响应方法原记录缺少具体case与运输阶段，根因仍 **OPEN**。原ZIP SHA `dc40962c88da1604ae6d7361e2e80980226e13a91e5cb91bd687b72c9dac1b07` 保留；导航、打包、冷启动未运行。

总控已非强推6d36并派 CI41/run35413624631/job105817886283，封包时 **PENDING**，293原生+3导航仍为期望。新增阶段附件也待实际Mac执行与独立解读；即使后继绿，也不能仅凭诊断变更宣布原运输根因已解决。本窗口未推送或触发CI，不重复native；后继准确安装包与平台验收由总控单独封证。
