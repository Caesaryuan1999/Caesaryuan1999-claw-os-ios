# AUTH4 — login credentials are read-only

Parent: f93235f953b8cab2171c1ab6bb130ccf98a1b53b.
Exact two production files: AccountGeneralSettingsViewController.swift and CredentialsChangeViewController.swift.

The profile page previously allowed swipe deletion of a login credential, and the destination used legacy setMeta/confirmCred followed by deletion of the original credential. AUTH-A1 defines only registration/recovery, so the UI could lock out a new account or invoke an unsupported OTP path.

Profile credentials now show their verified/unverified state with no disclosure indicator, no swipe editing, no deletion callback and the explicit footer/tap explanation “更换手机号或邮箱暂未开放”. The old destination is independently read-only: existing current values may be viewed, inputs/actions for new credentials and verification are hidden/disabled, and both inherited IBActions only explain the limitation. No request is dispatched even if an old route/action is triggered.

Existing profile nickname/description and avatar mutation code is unchanged; no new bind wire fields, tag API, DB/SDK/auth state or public CLAW-number change.
Windows: 5 boundary source assertions red→green; 9 storyboard outlet/action + public-profile boundary checks PASS; existing 33 source policies PASS; diff-check PASS.
No UIKit/Swift/real-server execution on this worker. Mac full App compile and actual device navigation remain pending.
