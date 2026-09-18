# VLC 原生行为取证计划（实施前冻结）

基线 06553a0df3574db0468cfff27223f660be3d4e4d；生产保持 e6e07aff。仅测试/CI接线，不实现播放修复。Podfile 实际 TinodiosUITests 已调用 app_pods，其中已有 MobileVLCKit；因此不需要改 Podfile，实际代码边界缩为新 VLCPlaybackProbeTests.swift、project.pbxproj、verify_publish_outcomes_macos.sh 三文件，报告另计。

## 4 个方法与判断

1. 实际 URL/解码基线：真实 Tinode.addAuthQueryParams，本机 HTTP，真实 VLC 输出视频；必须有 decoded/displayed frames、videoSize64、time 至少150ms，并从 VLC 自身 snapshot 读取颜色像素。两片由 AVAssetWriter 自生成，不下载素材。
2. 重定向观测：302 同源无 query、302 异端口无 query、307 异端口无 query、302 异端口显式合成 query，最多4例。首请求确证、有限等待，记录是否触达目标/携带 query、Referer、Cookie/解码。未跳转不强求播放成功；环境与 fixture 无效必须 fail。
3. 退役观测：服务收到原请求后暂不发送body；实际 Tinode.logout 并确认真实 context 失效后放行，再观察读取/帧/时间。随后显式 stop 对照。不是实际 VideoPreview 页面路由，不复制生产 guard。
4. 重开缓存观测：同一完整 URL先播 A 片；停止后服务切 B 片再用新默认 VLC player，分别 cacheable 和 no-store。记录新请求与帧色，另观察合成 Cookie。再测试服务403时是否仍返回旧可解码帧。一次内存缓冲不叫磁盘缓存，测试结果不外推所有协议。

fixture断言（可生成/监听/收到首请求/基线实际解码/受控停止）与安全观察分开。观测到redirect或退休后继续读取/播放写为 CONFIRMED_GAP；仅测量成功不能叫播放安全，未观察到写 NOT_OBSERVED_THIS_FIXTURE。不得修改期望把实证危险行为变成安全PASS。

## 资源上限

仅127.0.0.1、动态端口；Location只可指本轮两个已注册本机端口，不连接真实服务/公网，不发真实凭据，不使用 URLProtocol 或假 VLC。每HTTP服务最多32连接、每请求header最多16KiB、body最多2MiB，连接超时12秒；监听启动最多5秒。fixture生成/finish各最多10秒，正常播放测量最多8秒，VLC快照最多3秒，stop观察最多5秒，redirect/403判定各最多5秒。单方法整体执行预算120秒，4方法合计上限8分钟；不循环重试或新建模拟器。

每个播放器在主线程持有独立64×64以上 drawable，停止后验证实际state，再隐藏/释放窗口；服务取消全部连接。stop失败保留失败与对象到进程结束防异步释放断言，不能宣称已完成清理。合成数据库与原生迁移既有fixture一样不unlink活连接；其他文件只清本轮UUID临时目录。

## 接线与证据

沿现有同sim_id/storage.xcresult，仅增加 VLCPlaybackProbeTests selector，不改196旧原生方法/断言和导航3。合成测量4方法单列，不计生产播放验收。实际Pods安装后验证3.6.0 podspec，获取simulator slice的VLCMedia/VLCMediaPlayer/VLCLibrary头SHA，以 TEST_RUNNER_ 环境变量传入原生测试并 attach；运行时附library version/changeset/框架版本，缺证失败。使用公开头真实statistics和snapshot，不用网上新版本API替代实际头。

输出仅固定场景名、安全布尔/数值、实际PNG及JSON附件，均进已有storage.xcresult；不记录请求完整URL/query值、用户数据、系统进程列表。不输出测试凭据；这些值仅内存匹配。保留任何失败，待总控精确Mac CI。不在Windows宣称Swift通过。
