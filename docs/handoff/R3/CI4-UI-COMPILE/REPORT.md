# CI4-UI-COMPILE：UISearchBar 正式属性

- 前置1be51a5b6fcc846f825d22064e58130f763c7868。1生产文件1行：FindViewController.swift54，textField?改为searchTextField，保留placeholder与样式值。
- 真实CI4：run35280802910/job105402023476/fd7d0c52；SDK26通过，storage/App编译报UISearchBar没有textField，DB诊断和冷启动未运行。不能作为新的数据库失败。
- Apple官方searchTextField文档机器可读元数据确认iOS13.0引入；工程全部IPHONEOS_DEPLOYMENT_TARGET=14.0，故无需旧API回退或availability分支。[官方属性文档](https://developer.apple.com/documentation/uikit/uisearchbar/searchtextfield)
- 同项目已有searchTextField焦点/主题调用；不新增扩展或读取私有属性。全Find文件比较确认仅该表达式变化。
- 现有联系人布局策略补正式API与旧拼写禁止断言，其余保留。Windows源码检查及diffcheck通过，真实Swift重编译由总控CI5完成，当前未宣称通过。
- 累积原生期望130不变；未推送、未取消或覆盖CI4。
