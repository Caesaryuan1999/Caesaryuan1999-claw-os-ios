# CI38 A 页代次夹具后继

固定测试提交 `3cb55192054a12707a00cac6de8b8f21e3fc4521`，父 `02e4ebcb54e4aa7451224e7935b8bb78b840c8ba`。唯一代码文件 `TinodiosUITests/AssistantHistoryTests.swift`。

CI38 源 7f98f4f，run 35399197239 / job 105774965365。总控已核 268 pass / 1 fail，失败方法 `testAccountAndPageGenerationsRejectLateOldResponses`，原 failureText 只有共享 helper 的 “Bounded real consumer condition not reached”，约 3.614 秒；未记录能区分三个 until 的阶段。因此不能确定该次实际停在哪个 until。

源码确证的夹具问题：连续 loadConversations 创建独立 URLSession，不保证第二次请求的 startLoading 比第一次晚到；原测试却将 held[1] 固定当新请求。若开始顺序交换，生产正确丢弃旧代次，测试就可能等不到新页面处理。这是可证顺序假设缺口，不写成该次 Mac 已定位根因。

后继先发第一请求，真实等 held.count==1 且不回包，再发第二请求并等 count==2。两个请求仍同时未完成，仍严格新回包先于旧回包；oldConsumed、原账号/投影断言不变。四个等待通过 XCTContext 明确阶段，继续复用原 3 秒 helper，没有延长时限或添加固定 sleep。B 的未提交 WIP 没有混入本提交。

diff --check 通过，原生方法数不变。新夹具未在 Windows 运行 Swift，需准确后继 Mac CI。原 CI38 日志/ZIP/失败记录不覆盖。单路径补丁与独立正向 apply 证据见 `../AI-CLIENT-B01/a-page-order.patch` 和 `successor-manifests.json`。
