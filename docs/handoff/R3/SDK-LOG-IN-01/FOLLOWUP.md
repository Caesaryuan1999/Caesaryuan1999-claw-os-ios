# SDK-LOG-IN-01 接收失败日志补正

- 前置3f3d438d70dce742ea91bdf231c34699a18e26e4；此前1be51a5已固定正常入站事件。本补正仍仅Tinode.swift同一onMessage入口1行，将任意error.localizedDescription改为固定packet_in_failed。
- dispatch会抛JSONDecoder及Promise/业务错误；catch此前没有错误内容白名单。不假定任意错误文本都无输入数据。此处现在只输出固定失败事件，不输出错误字符串、包、token/UID/params。
- try tinode.dispatch(message)、catch结构及其余生产文件字节内容未变。精确入口源码检查在3f3d438失败、新树通过；这是源码负测而非运行时截获，不声称全App日志完整审计。
- 原生方法130不变，待总控最终Mac CI。未push/dispatch，CI4证据原样保留。
