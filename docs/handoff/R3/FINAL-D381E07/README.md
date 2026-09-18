# CLAW OS iOS R3 累计安全交付候选

源码基线：34a8b3e5ad4df210117e2e03b308576796ba55b2
源码候选：d381e074fd1ede395f6c21a658f37020661acd78
本目录是之后的交接产物，不改变该源码SHA；不覆盖旧 FINAL-CANDIDATE 或历史失败证据。

## 可应用补丁
CLAW-IOS-R3-source-test-ci.patch：83文件，59修改、24新增。
SHA-256：6166b0cf7a6a9ce77f8e2286466d61cf9ab656e9982c45512e5de5481e5582a9
Git原生binary/full-index/no-renames，保留新增mode和原始Git字节。显式白名单仅生产源码、原生测试、工程、Podfile、CI及三个安全Python验证脚本（smoke、local SQL green、prior SQL red）。SharedUtils、私有配置、runtime、凭据、签名、pycache、报告与旧补丁产物不纳入；没有复制这些候选到临时目录。
已实际只重建83个涉及的安全基线文件及Git index，git apply --check --index 后执行 git apply --index，83/83应用后的SHA-256、mode、Git blob OID与候选一致。file-manifest.json逐文件保留Git字节/Windows工作文件字节/实际应用SHA，区分LF与CRLF。临时目录已校验位于本交付目录后清理；原工作目录和其它端未修改。

复现（不向当前生产树应用）：
~~~powershell
rtk python -X utf8 -B docs/handoff/R3/FINAL-D381E07/verify_forward_apply.py
~~~
另一个已授权干净基线副本可先确认HEAD为上述基线，再git apply --check --index及git apply --index该补丁。本说明不授权覆盖原树/私有配置。
commits.tsv列全部按时间顺序精确提交，不把UI、身份、发送保护、数据库诊断与删除修复混成单个实现提交。

## 准确原生方法清单
native-methods.json按实际CI的only-testing选择列181个方法及来源：
SDK41、Publish4、LocalMigration62、Identity29、ConversationRemoval9、PublicDirectory13、Secondary13、OwnedImage10。
双初始化压力仍是一个方法、12轮/24次开库，不把循环当作12个测试。Drafty等未选中的其它项目测试不计入本数字。
181是本候选待执行数量，不是已通过数量。相对于已测CI10，新增ACK7+local12=19。

## 已取得证据
Windows最终44源检查通过，见static-policies.json；smoke脚本14个受控Python边界测试通过（非Mac模拟器）；LOCAL-DELETE提取生产SQL的真实SQLite11例通过，旧三例部分提交反例保留，均不代替Swift。
CI9：7bacc0d/run35287660307/job105423474366，SDK30+storage122=152通过，包含12轮并发及4gate方法。打包成功，启动预检未记录设备状态即失败，未install/launch，不是App崩溃。旧zipSHA57b17ba973b6f244f6f4bdb26f5dbf67cc2f3f6722b648d835282bbbe302be14。
CI10：d61855fd1534cb864fb5f6848eec3fa1b7dcce4a/run35309485402/job105488355128，SDK30+storage132=162通过。相同测试模拟器Shutdown→boot/bootstatus→Booted后安装；PID31749、进程路径/二进制hash、截图、崩溃检查通过。
CI10免签模拟器zip SHA69c513be70d07f26bde3761cace243dcfda77809d2167ebb2e890654b8f1cb66，build1736。
CI10 PNG1206x2622，SHAe8576d09cf32120f60bdca0c4f15f8ebd470bfa1b87f4c49229cdacf7b24e36d。总控与本端均视觉核对真实登录页；旧首屏原账号按钮部分裁切，源码证明滚动布局但未实际手势验证。d381e07仅将注册/找回并排节约68pt，最终截图尚待CI11。
CI10不包含后续805dbf3 ACK、4da8391 COPY、6bf302b LOCAL及d381e07 LOGIN。下一精确Mac结果由总控追加；本封存不提前记绿。

## 保留的失败与边界
旧CI1许可XML、CI2签名参数编译、CI3断言/并发、CI4 UISearchBar编译、CI5 IOERR、CI6诊断测试错误、CI7并发IOERR_LOCK3850/errno9、CI8 ImageResource名称冲突、CI9启动前置失败均在旧报告/根证据保留。初始化gate是应用层同路径生命周期串行化规避；通过CI9/10不等于已证明Apple VFS closed-versus-readonly fd内部根因，不宣称跨进程、硬链接或动态symlink覆盖。
UIKit真实使用、完整Drafty缩略图渲染、通知系统权限跳转、真iPhone、正式签名/APNs/FCM设备、真实OTP服务及真实用户旧库升级未由这些测试完成。无IPA/正式上线证明。
LOCAL-DELETE只在远端本请求200后退休原会话；本地失败明确单列，仅本地重试不再次远端删除，账号B/新生命周期拒旧回调。没有跨重启自动清理队列；SQLite记录删除不代表Kingfisher缓存、导出文件、备份或磁盘全擦除。最终这19项新增原生仍待Mac。
