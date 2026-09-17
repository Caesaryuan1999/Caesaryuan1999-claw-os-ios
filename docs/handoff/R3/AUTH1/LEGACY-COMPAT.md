# AUTH1 legacy compatibility correction

Parent: d077e02b1340cd5996196fcd6bd247fd43b28134.
Only two production files: ClawIdentityFlow.swift + LoginViewController.swift.
The existing same-origin/HTTPS/captured SDK/UID/persistence bridge is unchanged.

Root review found that the first AUTH1 commit incorrectly required a successful AUTH HTTP capability response even for original basic accounts.
The flow now records completion of the capabilities check separately from support. A missing endpoint (404), failed transport or unsupported AUTH does not block the explicit original-account path. Any parsed legacy_basic=false is retained before checking supported, so even enabled=false plus legacy_basic=false rejects basic.
Main phone/email login still requires supported AUTH. The secondary button and actual flow both apply this distinction. In original-account mode auth_invalid says “原账号名或密码不正确”.
Legacy 3xx still stops with administrator recovery; no stock OTP or new-proof reuse.

Added three native production state-machine tests: 404→basic invoked→commit; disabled AUTH with explicit legacy false→no bridge call; transport failure→basic available but phone/email blocked.
Total prepared AUTH XCTest methods: 26. Existing R2 SDK26/DB45 remain unchanged.
Windows: 33/33 source policies and diff-check PASS. Native Swift/SDK bridge/UI/Mac execution NOT_RUN on this worker.
