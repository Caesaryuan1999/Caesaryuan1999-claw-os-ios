# AUTH legacy transport independence

独立修复 backend / root 确证的P2：Coordinator在构造Flow前强制创建新HTTPS AUTH service；旧已配置局域网非TLS服务器因此使整个coordinator=nil，原账号入口无法启用。

2生产文件：ClawIdentityFlow.swift、Utils.swift。Flow HTTP service显式optional；共享makeHTTPService调用原ClawIdentityService严格构造器，不修改非loopbackHTTP拒绝规则。没有合法HTTP service时prepare返回unavailable并记录能力检查结束，旧basic仍可走原SDK桥。每个新HTTP动作（challenge/verify/register/reset/password-login）先检查service，不发请求、不伪造loopback来源。已有可解析legacy_basic=false仍是拒绝门禁。

Coordinator继续捕获实际host/TLS参数与SDK实例，legacy唯一真实路径为connectDefault→loginBasic，重新核对owner.hostURL == 原origin、session UID/鉴权后保存；不修改SDK连接策略、不扩大生产TLS验收。这里只保留用户已配置的旧明文局域网连接兼容，不代表该配置可以正式发布。

新增2个真实Foundation/Flow XCTest：严格service拒绝192.168.50.20 HTTP、共享工厂返回nil、prepare后legacy桥收到原密码字节并可完成；另验证nilHTTP时新登录/挑战/验证/设密均拒绝且不调用token桥、不遗留busy/pending。测试不冒充实际SDK网络或Mac执行。既有显式false/404/host世代测试不改。当前累计原生期望112 = SDK26 + DB49 + AUTH28 + Removal9，Windows NOT_RUN；34源码脚本绿，diff --check绿。

实际Mac CI3 ae88055仍是独立旧候选，不能把本提交算入它的结果。
