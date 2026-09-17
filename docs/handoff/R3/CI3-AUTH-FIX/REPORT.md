# R3 CI3 AUTH 测试前置修正

- 前置 HEAD：e67e68fefc65f0886aaabcecec079e280a277825。
- 真实失败证据：CI3 35277235637 / ae88055，IdentityFlowTests.testDisabledCapabilitiesAndLegalGateDoNotSubmitChallenge 抛 ClawIdentityError；该方法先将 enabled=false 解码并保存在同一 flow，再调用 prepare() helper 假定更换 URLProtocol 响应会刷新能力。
- ClawIdentityFlow.prepare 对已解析能力返回缓存。为保留明确 legacy_basic=false，不能丢弃禁用能力；本次生产代码零修改。
- 原方法保留禁用拒绝，并加强再次 prepare 不发 HTTP、即使条款资源可用也不能发 challenge、零派发断言。新增独立方法在新 flow、有效 capability 前置下验证法律资源缺失仍不能发 challenge。
- Windows：源码前置/29 个 AUTH 方法检查通过；未执行 Swift。本次原生期望总数 113（SDK26 / DB49 / AUTH29 / Removal9）；既有方法未删除，生产禁用门禁未放宽。
- 数据库并发失败另案调查，未将本修正冒充其解决证据。
