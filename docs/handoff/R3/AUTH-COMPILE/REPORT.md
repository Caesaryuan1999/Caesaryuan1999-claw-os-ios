# R3 AUTH compile correction

Parent CI2 run 35276151918 at b056526 reached Swift after license preparation passed (25 entries, 9 forbidden FF removed), then failed: Utils.swift:1140:66 missing argument for parameter creds. Native tests did not execute; no 106 PASS claim.

SDK Tinode.loginToken(token:creds:) has no default for its second argument. AUTH-A1 already verified the credential at HTTP and must not invoke legacy OTP, so the bridge now explicitly passes creds: nil. Checked the new Foundation services/flow/coordinator call sites: this was the only new loginToken call; loginBasic(uname:password:) matches its actual two-argument signature. Token/session/UID guards and requests otherwise unchanged. One source policy string updated to require the real call signature.

UI03 working changes remain unstaged; only the compile hunk in Utils is staged in this commit. PUBLIC remains separately committed. Cumulative native expectation 110 after PUBLIC; actual next Swift build/test pending parent CI. Windows source checks retained separately.
