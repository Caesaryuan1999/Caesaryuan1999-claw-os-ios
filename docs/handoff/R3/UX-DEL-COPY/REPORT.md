# UX-DEL owner confirmation scope

只改 TopicSecurityViewController 中群主解散确认正文。已读取 Figma get_design_context 62:493 / 62:518，与总控要求一致：全体成员失去访问、服务端群历史删除、设备已保存文件/副本不随之删除、不可撤销。实际 actor/topic/owner permit、leave(unsub:true) 与 delete(hard:true) 派发语义完全不动。

git diff --check 通过；无新增原生方法，累计期望110。文案小批不重复跑源码镜像用例；既有9项删除意图原生回归仍由最终MacCI执行。本文案不宣称删除他人本机副本。
