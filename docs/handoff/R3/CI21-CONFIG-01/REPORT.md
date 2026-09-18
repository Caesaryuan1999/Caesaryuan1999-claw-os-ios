# CI21-CONFIG-01

基线 4f052294bea06f41eccd0da85789fe2e14eea664；本次仅 Podfile、Podfile.lock 两个测试依赖配置文件，真实 Ruby 回归及证据在本端报告目录。VOICE 两次提交与本次独立。

## 原始失败与实证

CI21 run35336536015/job105572560596 在 post_install Podfile97 失败：attributes.fetch('OTHER_LDFLAGS') 抛 KeyError。所有 native NOT_RUN，没有新的 VLC 播放结果。原 artifact10542699460 SHA256 1ca0065af70e30319240effaeb52bce2f758becfb598672aaf8e9f7e0eec5c75 保留在根证据目录。

原日志可证实际 CocoaPods1.17.0、Ruby路径3.3.0、claide1.1.0；Podfile.lock 的 COCOAPODS1.15.2 是锁元数据，不能作为实际 runner 版本。旧报告对此推断不足，以本次勘误为准。CI21 没有记录 xcodeproj gem 版本，不猜测。

官方 [Xcodeproj1.28.1 Config](https://raw.githubusercontent.com/CocoaPods/Xcodeproj/1.28.1/lib/xcodeproj/config.rb) 将 OTHER_LDFLAGS 从 attributes 删除，解析到专用六分类；to_hash 重组 flags，且仅 inherited 时可能不输出该键。官方 [CocoaPods1.17.0 gemspec](https://raw.githubusercontent.com/CocoaPods/CocoaPods/1.17.0/cocoapods.gemspec) 要求 xcodeproj>=1.28.1,<2。实际本机真对象已复现 attributes={} / 原 fetch KeyError / to_hash 正确保留 MobileVLCKit；这次不是 Python 仿制 Config。

## 修改

仅两个 probe targets 的原 bounded hook：通过真实 Config#to_hash 取完整链接参数。若不存在该键，只允许真实 probe test Config、六分类都存在且没有除 inherited 外的任何 flag 时显式清空 override，阻断 App 的 project 继承；不是任意 nil 回退。host 仍必须完整四个自身 framework；缺配置、错误类型、外来 App 依赖、缺 target 继续失败。

保留序列化的 simple、frameworks、weak_frameworks、libraries、arg_files、force_load。真实 nested test 若有 host 动态框架，原样保留，不能先假定它为空。下轮 hook 打印 Ruby/CocoaPods/实际 loaded xcodeproj 版本以及 target/configuration 的 framework 名集合，便于准确追溯；不输出凭据、项目路径或其它 linker 参数。

Podfile.lock 仅 Podfile checksum，其他依赖/版本/spec checksum 字节不变。没有修改生产、VLC 默认参数、四方法及断言、selectors；累计仍 210 原生 + 单列导航3期望。

## 真 Ruby 回归

隔离环境 RubyInstaller3.3.12 x64，官方 GitHub asset digest 与下载实体 SHA256 一致；官方 RubyGems xcodeproj1.28.1 gem SHA256 与版本API一致，详 tool-provenance.json。不改系统 PATH/服务；未安装 MSYS2。最初完整 gem 依赖安装因 nkf 需要 MSYS2 终止，随后只安装官方 xcodeproj gem，直接 require 其真实 Config 源文件及 Ruby 标准库。未假称完整 CocoaPods 安装成功，亦不以本机1.28.1冒作CI21实际版本。

verify_real_config.rb 从当前 Podfile 唯一边界提取原 hook，直接 eval 原字节。只有 CocoaPods aggregate/user target/project 容器采用窄适配；Config 是真实类。15/15实际通过，包含原错误红复现、全部 linker 分类保留、非空 test、两种合法空 test、空/缺 host拒绝、缺配置、错误对象、Firebase/WebRTC拒绝、畸形分类、缺 target、具体 simple flag、两种 inherited 拼写。ruby -c Podfile：Syntax OK。Ruby结果记录实际 runtime、Config源SHA、hookSHA。

可重跑命令（进程级 GEM_HOME/GEM_PATH 指向隔离 gems，未改系统环境）：

    artifacts/tools/ruby-ci21/rubyinstaller-3.3.12-1-x64/bin/ruby.exe -I artifacts/tools/ruby-ci21/gems/gems/xcodeproj-1.28.1/lib docs/handoff/R3/CI21-CONFIG-01/verify_real_config.rb

Windows Ruby对象执行不是 Xcode/CocoaPods实际安装、dyld、Swift或VLC播放。须由下一精确Mac候选验证真实聚合配置、加载和原四探针。无自行push/CI。
