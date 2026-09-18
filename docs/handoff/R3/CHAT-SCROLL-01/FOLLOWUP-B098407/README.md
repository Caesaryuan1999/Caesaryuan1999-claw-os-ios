# CI32 后继 · 两路径源码补丁

精确起点：`fdedf825490ea9fa420b54033e8c48d65f8fc8aa`。
精确目标 / CI33 源码：`b0984075ca79ffef93658f702005dd19a773616b`。

本包只包含 `Tinodios/MessageViewController.swift` 和 `TinodiosUITests/ChatScrollTests.swift`，不是完整 App，也不能直接应用于旧 `1b20ec2` 或空上游。必须先具备 fdedf825 的准确源码：可使用已保全源码，或在 `0a54fcf1ecb35a6f3511815ed59c7750f692ea2d` 上应用先前 e30e7bc 交付的 13 路径单元包（该包 patch SHA256 `29cc92f25a9b21100c9fb38b29796460810d946f146a7d365a3b60cb2e48e9f3`），核完整原清单后再应用本后继。旧 e30 的 13 路径包、09631 累计包和 CI32 原失败均不修改。

行为与原件诊断见上级 `CI32-DIAGNOSIS.md`。生产只改变 capture 的当前布局几何枚举；测试改善三失败场景的几何与导航真实前置，仍 10 方法，原断言保留。CI33 `35375538413` / job `105699232079` 正在运行，封包时 **PENDING**。本次仅证明源码恢复；242 原生 + 导航 3 是候选方法清单，不是新运行结果。

## 真实正向恢复验证

`package_unit.py` 复用前包流程，用严格两路径白名单生成原始 `git diff --binary --full-index`，在独立临时 GIT_INDEX_FILE 读入完整 fdedf825。先执行 `git apply --cached --check`，再实际 `git apply --cached`；比较目标两文件 mode/blob/SHA256、所有未选起点条目，并核原工作索引不变。`unit-package.json` 保存结果树、条目计数、前置文件与目标文件的精确身份。

未读取私有配置内容、未改生产工作文件、未构建或触发 CI。patch 原上下文不做 whitespace 重写；新辅助文本为 UTF-8/LF，实体 SHA 与 Git 存储字节另核一致。`bundle-hashes.json` 列本目录其余文件的实际大小和 SHA。

## 应用与回退

在满足前置源码的独立 checkout 中，保留配置/数据库/未跟踪数据，先按 manifest 检查 `requiredBasePaths`，然后：

```powershell
rtk proxy git apply --check <absolute-path-to-this-unit.patch>
rtk proxy git apply <absolute-path-to-this-unit.patch>
```

完成后核 `paths` 的两项 mode/blob/SHA，并与旧 e30 清单中其余 11 项保持一致。由总控单独收 CI33 实际结果；后续 docs 提交不作为 CI 来源。

回退使用另一份保全的已验源码和原配置/数据库。若只撤此后继，fdedf825 的 CI32 三失败仍存在，不能把它当可用验收版本；完整已验旧基线仍是 CI31 / 1b20 的源包。没有 schema 变更，不 reset/clean 当前树、不删除数据库、不重新执行上传或发布。
