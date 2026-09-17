# Profile credential loading distinction

独立一方法修正：me.creds 为 nil 时显示“暂未获取”；已获取数组无对应 method 才显示“未绑定”；真实 credential 继续显示其值与验证状态。没有凭据编辑/绑定写操作，没有PUBLIC或存储改动。源码三分支复核及diff --check通过；未新增native方法，期望仍110，真实加载/同步UI待Mac/设备验证。
