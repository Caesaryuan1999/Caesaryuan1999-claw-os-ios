# R3 AUTH1 — AUTH-A1 identity pages and native test wiring

- Owner: iOS; exclusive tree work/r3-20260918-ios; branch codex/r3-20260918-ios.
- Parent: 12c92452a72a8b501171228532172d059d802343 (UI02). This batch contains no SDK, DB, C3 queue, push, signing, private SharedUtils, or shared protocol changes.
- Contract: AUTH-A1-20260918 plus original-account login compatibility. Design: R3.D1.
- Status: SOURCE_READY_FOR_REVIEW; native Swift, App/UI, provider, device and Mac CI for this commit are NOT_RUN on this Windows worker.

## Exact production boundary (8)

1. Tinodios/ClawIdentityService.swift — ephemeral same-origin AUTH transport and strict input/response types.
2. Tinodios/ClawIdentityFlow.swift — request/receipt state, expiry, generation, pending mutation, HTTP→WS completion gate.
3. Tinodios/LoginViewController.swift — phone/email password login and secondary “使用原账号登录”.
4. Tinodios/SignupViewController.swift — existing storyboard route now starts OTP registration; no new username, invite or anonymous avatar upload.
5. Tinodios/ResetPasswordViewController.swift — existing storyboard route now starts reset-purpose OTP.
6. Tinodios/CredentialsViewController.swift — AUTH verification mode, resend/countdown, next-step navigation.
7. Tinodios/Utils.swift — UIKit form/entry/password screen and captured SDK/host coordinator, deployment legal-resource gate.
8. Tinodios.xcodeproj/project.pbxproj — both Foundation production files compiled into App and test bundle; IdentityFlowTests in existing UITests target.

Supporting changes: one new native test source, three updated source policies whose old requirements mandated retired invite/basic registration, and the existing local Mac verification script. Original R2 native test files and selectors are unchanged.

## Implemented behavior

- Login checks capabilities, posts normalized tel/email plus the original password bytes, then uses HTTP token only with the captured current Tinode instance at the captured host/TLS origin. HTTP UID must equal WS authenticated UID; only then save SDK token and enter messages. No successful HTTP response alone logs into the UI.
- New passwords require 12–64 ASCII printable non-space bytes. Existing login passwords are not trimmed, normalized, or checked against the new policy. Email rejects Unicode before lowercase (including Kelvin-sign folding), trims only ASCII edge whitespace, preserves plus/dot, and validates local/domain lengths. Phone uses an explicit editable +86 default or supplied E.164 input.
- Registration: capabilities/method/legal consent gate → challenge → verify → password → register → password-login → WS. Registered UID is retained in memory and checked at login. If login fails after registration, the page says “注册已完成，暂时无法登录” and has “返回登录”; it does not report the registration failed or silently create another UID.
- Reset uses purpose reset, reset-password endpoint and reauth_required; returns to password login. New proof is never passed to Tinode auth schemes.
- Transport-loss challenge retry is explicit and uses the identical request ID/body. Provider delivery_uncertain discards that pending submission, honors cooldown, and permits a fresh request ID only after waiting. No automatic provider retries.
- Lost verify response clears the consumed challenge because the original proof cannot be recovered; the page requires fresh verification. Proof expiry blocks a new mutation. A previously pending register/reset operation can replay the exact request after proof expiry; its fields stay frozen and UI says “重试确认结果”.
- Server retry_after is honored separately for challenge, login and password mutation. Generation and captured host/SDK checks discard late HTTP/WS callbacks; leaving a screen invalidates the flow and retires only its own started but uncommitted SDK session.
- Secondary original-account login retains existing username normalization and password bytes. It is enabled only by supported AUTH capabilities with legacy_basic. A 3xx credential-validation response shows an explicit administrator-recovery message and never opens stock OTP. The legacy Credentials controller branch remains as inherited code, but there is no production routeToCredentialsVC caller in the new UI. Servers without AUTH capabilities are unavailable here; optional old-server compatibility is not claimed.
- New identity values/proof/OTP/password are held in memory and request bodies; no new logs, UserDefaults, cookies, credential storage or URL query secrets. HTTP redirects are rejected even within the origin. Public HTTPS is required; only exact loopback HTTP is allowed. The current SDK default API path is /v0/auth.
- Legal resources are absent by default. Optional reviewed Info.plist keys CLAWTermsURL and CLAWPrivacyURL must both be HTTPS URLs; no fallback domain is installed and consent starts unchecked. Current registration is explicitly blocked pending verified resources. Native tests pass an explicit synthetic legal gate; they do not enable formal registration or prove provider delivery.
- Existing storyboard outlet/action identifiers and routes remain intact. Dynamic form controls have ≥44/52 pt targets, Dynamic Type, keyboard scrolling including iOS 14 fallback, secure-field visibility controls, and real failure/recovery actions. No device layout/accessibility claim is made.

## Validation and reproducible execution

- Windows source policies: initial 30/33; 3 failures were obsolete requirements for invite/basic registration and the removed layout. Updated only those specified contracts; final 33/33.
- Source/project wiring: 40/40 (scope-source-check.json), including all existing auth IBOutlet/IBAction names, both production-file target memberships, unchanged R2 test source/selectors, no SDK/DB diff, and CocoaPods license parsing.
- Git diff --check: PASS.
- Storyboard raw HEAD bytes differ from checkout because of LF/CRLF; canonical XML and Git source diff are equal. No storyboard edit is in this batch.
- 23 native IdentityFlowTests prepared (NOT_RUN here): input/old password bytes; origin/redirect; capabilities/method/legal gates; frozen challenge and register retries; cooldown/expiry; lost verify proof; proof_invalid restart; delivery_uncertain; login retry_after; expired token; registered/HTTP/WS UID mismatch; commit-time gate; host/leave generation; legacy 3xx; reset endpoint/reauth.
- Existing .github/workflows/ios-smoke.yml calls Scripts/ci/verify_publish_outcomes_macos.sh. That script now additionally selects TinodiosUITests/IdentityFlowTests while retaining SDK26 and DB45; expected cumulative native methods = 94, pending actual discovery/run.
- The same script still builds the whole App with signing disabled and now parses both generated and bundled CocoaPods Acknowledgements.plist, which catches the inherited invalid pre-pod resource if generation fails.
- No push, workflow dispatch, real provider request, real-account login, or private configuration was performed by this worker. Parent owns the reviewed remote CI path.

## Remaining boundaries

- Actual Mac compile/tests, UI navigation, minimum-width/Dynamic Type/VoiceOver/keyboard, TLS/App Transport Security behavior, real email/SMS, real accounts/devices, signing and APNs require separate evidence.
- AUTH3 password-change reauthentication and AUTH4 read-only credential settings are approved separate batches, not included here.
- Group/P2P destructive-action UX and later Contacts/My visual/public-alias integration are separately scoped.

