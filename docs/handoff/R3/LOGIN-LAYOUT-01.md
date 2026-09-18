# LOGIN-LAYOUT-01

CI10 d61855f screenshot cold-launch.png was visually read: the bottom 使用原账号登录 text is partially outside the initial viewport. This does not prove the action is unreachable.
Read-only route evidence: Utils1453–1487 creates a UIScrollView (scrolling enabled by default), bounds it to safeArea/keyboardLayoutGuide, binds the complete form to contentLayoutGuide and width to frameLayoutGuide; stack bottom32 completes content height. Existing storyboard views are hidden. No fixed footer covers the legacy button. Actual scroll gesture was not executed.

One production file change: LoginViewController.swift. Register/reset buttons are one equal-width horizontal row with16pt gap, retaining their existing minimum52pt button constraints and selectors. The explicitly approved display label becomes 注册账号. Logo, phone/email/country fields, legacy52pt action, AUTH flow, common form and low-frequency scrollable actions are unchanged.
This saves one52pt row plus16pt gap for the same content size. First-screen visibility remains to be assessed from the next real cold-launch screenshot; no screenshot result is fabricated from static layout reasoning.
No new native method for this low-impact layout. Cumulative181 expected after ACK/local cleanup, pending precise final Mac candidate.
