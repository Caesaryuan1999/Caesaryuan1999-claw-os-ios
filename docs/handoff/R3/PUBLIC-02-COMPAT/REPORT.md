# PUBLIC-02-COMPAT — 旧 basic 公开号长度边界

- 前置：fd7d0c52fffedde0e773c6a97521daa59181b91f。不改该不可变CI候选。
- 仅1生产文件 Utils.swift：普通 ASCII basic 词项从无长度界限改为 [a-z0-9]{2,32}；alias 继续SDK已有4–24格式；usr外形只在有效alias时查询alias，始终不加basic。
- 新增1原生方法覆盖长度1/2/3/24/25/32/33，以及usr/有效短usr alias/过长usr拒绝。普通abc与25–32历史号保留；不新增Unicode/dot。
- Windows生产接线策略通过；原生新方法未执行，累积期望128（SDK26/DB51/AUTH29/Removal9/PUBLIC13）。DB诊断原生仍待总控CI，本文不声称Mac通过。
