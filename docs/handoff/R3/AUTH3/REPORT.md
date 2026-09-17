# AUTH3 — password change requires reauthentication

Parent: 7f0b8a49966efd8d61a6e84151b3e2429266f586.
Production boundary: SettingsSecurityViewController.swift only.

The previous success callback merely showed “密码已更新” and kept the old authenticated page/token even though the AUTH-enabled backend changes the credential epoch and invalidates old sessions.
The page now captures its current authenticated SDK before dispatch, validates the new 12–64 ASCII non-space password, and on a successful ACK retires that same SDK through the existing logout route, showing “密码已更新，请重新登录”.
Malformed/absent ACK or ambiguous transport failure also leaves the old session and explains that the result is unknown, with new-password login or recovery as the next action. It does not automatically repeat updateAccountBasic. Definite pre-send failures/explicit 4xx (except 408/401) retain the local page and allow a fresh manual attempt; new passwords are not repopulated on server failure.
Callbacks check their captured owner before routing or feedback. No SDK, DB, wire, token format, C3, or private config changes.

Windows: 4 source assertions red before / green after; unchanged 33 source policies PASS; diff-check PASS.
These are source checks, not executing UIKit/Swift/real server. Mac compile and device ACK/close/timeout behavior NOT_RUN here.
AUTH1 prepared 26 native Foundation tests and all R2 71 remain unchanged in this commit.
Production SHA256: a5188aca57de2cf4c0100dd0834ece2c464f2413f1da0ba689be562ce84ff4a0
