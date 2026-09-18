# VIDEO-OWNED-02 累计安全源码候选

此包交付源码/必要测试/CI，**不是已通过新运行验收的 App 或 IPA**。

- 完整已保全起点：`34a8b3e5ad4df210117e2e03b308576796ba55b2`。
- 精确源码与测试目标：`49194cc56f5c1dfd894efd9a9be6877560e219d3`；最近生产提交76d0fe1062402a311a6e4e9378b7ee8d1639a3f1，491只修测试实际类归属。
- 累计 `CLAW-IOS-R3-source-test-ci.patch`：1,113,368 bytes，SHA256 `b5ee94f9adb90ecd32bbf1d1ccc0033d4fd0ec144e6c732d6c83a3b0dd93473d`。
- 99路径：69修改、30新增；完整95项非docs差异+4份已审核必要合成测试脚本。安全名单逐项在allowlist.json，排除项见scope-review.json。
- 单元 `../VIDEO-OWNED-02/unit.patch` 从abc23071b23671323d7bce89340ea6ffb513cb3b到491，恰5代码/测试/策略文件：52,307 bytes，SHA256 `275cde36f6ba7234533ac8ef0fae51eca7d5cc3a9125834241f9c769296c2fbf`。

当前独立单元两生产VideoPreviewController/ClawSecondaryUIState、两原测试OwnedImageTests/VLCPlaybackProbeTests、一必要方法数策略。累计还包含独立abc2307的VLCTime编译修正、758的403观测完善及此前已授权单元；没有混入私有配置。各批完整SHA见commits.tsv。原VOICE包、FINAL-E6、所有原失败证据不覆盖。

## 实际正向恢复证据

verify_forward_apply.py在独立临时GIT_INDEX_FILE中read-tree真实完整BASE，先apply --cached --check再实际apply --cached。99个目标mode/blob/Git字节SHA全部相同，所有未选择的基线条目原样保留，真实工作索引前后SHA相同。单元5文件另做同样验证；未checkout或读取任何私有blob，没有用空上游替代保全基线。

~~~powershell
rtk python -X utf8 -B docs/handoff/R3/VIDEO-OWNED-02-PACKAGE/verify_forward_apply.py
~~~

需BASE/TARGET对象都存在且当前安全路径与TARGET一致。补丁以Git blob原字节生成，manifest另列Windows工作树SHA；不把CRLF转换冒充原blob。若附件被Git工作树转换行尾，可在保全仓库运行验证器--generate恢复原字节后核同SHA。

## 范围与实际等级

排除SharedUtils私有源、真实GoogleService/push文件、签名/密钥、Pods/build/runtime、安装工具、数据库、PNG/视频/xcresult和旧补丁/报告。SharedUtils无delta只比较路径元数据，不读秘密。4个docs可执行脚本是纯合成CI runner/SQL红绿/Ruby Config回归，已沿既有清单审核。独立VLC空host只用于合成本机测试，不进正式发行Archive。

生成的.patch包含Git必需上下文空行前导空格及上下文制表符；将补丁自身当新增文本运行diff --check会报告这些协议字节，不可删改。实际源diff --check及正向apply检查均通过；文档检查排除这两份精确补丁实体。

本单元34/34源码检查、44/44源码策略通过，不是Swift执行。native-methods.json从**真实selector对应class及extension**提取226方法=SDK44+UIrunner175+VLC host7；真实App离线导航3另列。原12轮DB夹具不伪增方法数。

首个76提交的新增3方法曾误放URL extension，包装的实际类盘点失败。它未被推CI；491移入正确XCTestCase，方法正文保持，原32 file-wide检查局限及失败计数保留。此次包实际清单为44/175/7/3，不沿用文件全局计数。

CI23/0a7的SDK44+UIrunner167通过、VLC3PASS/1FAIL不提升为安全通过；CI24/758是SDK44通过、App编译失败，后续均NOT_RUN。CI25/abc2307实际SDK44+UIrunner167通过，VLC3PASS/1FAIL（第四403时间窗），其结果不覆盖VIDEO491。本包新增原生226/导航3、完整VideoPreview页面/真机/真实服务均等待对应精确版本证据。

本地fileURL不是任意容器网络隔离；新增M3U只有合成本机外链，观察结果留待Mac，出现次级请求必须报告缺口，不能凭绿测试宣称整体安全。250ms owner检查非即时承诺；停止未确认保留文件责任，未保证跨进程回收。整文件准备增加首帧等待，不承诺后台播放。

## 应用、安装、回退

1. 在完整BASE另建隔离树，核HEAD与目标路径clean，保全本机数据；不要reset/clean原目录。
2. 先核SHA，再 `rtk git apply --check --index <绝对补丁路径>`；通过才 `rtk git apply --index --whitespace=nowarn <绝对补丁路径>`。不匹配停止，不能强制覆盖私人配置。
3. 按manifest逐项核mode/blob，只提交明确名单，不能git add全目录。
4. root审核固定SHA后运行现授权Mac CI。只有准确SHA对应的未签名模拟器App ZIP可用于同平台续测；补丁不能直接安装iPhone，签名/推送/真实服务不在本包内。
5. 单元反向仅在精确491且5文件clean的隔离树先reverse --check再reverse apply；它会撤回视频owner/传输安全修正，仅供受控排查，不作为安全交付版本。整体降级应回已保全备份，不让旧binary直接打开未经兼容验证的新库。本包不撤销远端发送/注销，不承诺磁盘全擦除。
