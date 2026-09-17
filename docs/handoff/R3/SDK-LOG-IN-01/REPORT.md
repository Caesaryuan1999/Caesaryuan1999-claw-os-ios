# SDK-LOG-IN-01：固定入站包日志

- 前置a02c61c7ef033fe17fbb4f3b95b0db6afad5cbf2。1生产文件、1生产行：Tinode.TinodeConnectionListener.onMessage的原始message日志改为固定packet_in。
- 该日志不再插值message/body/token/UID/params；解码派发try tinode.dispatch(message)、异常处理、监听器及状态逻辑未改。全生产文件规范化行尾后比较确认仅该表达式变化。
- 精确入口源码负测：旧a02c61c失败，当前通过；diff --check通过。未截获运行时日志，不作全App零敏感日志承诺。
- 原生期望仍130，未增加原生方法。Windows未运行Swift；总控下一最终Mac候选验证。CI4固定fd7d0c不含此提交，未推送或替换该证据。
