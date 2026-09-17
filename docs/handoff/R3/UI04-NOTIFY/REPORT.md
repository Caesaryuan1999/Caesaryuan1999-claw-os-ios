# UI04 NOTIFY
Two production files: SettingsNotificationsViewController.swift and ClawSecondaryUIState.swift. Native tests compile the exact shared production helper; project and existing CI selector explicitly include SecondaryUIStateTests without replacing earlier tests.
- Actual UNNotificationSettings snapshot feeds native authorization status plus alert/notification-center flags. Only notDetermined requests; denied and partial alert configurations open system settings. A usable preference toggle does not prompt again.
- Status action always re-reads system settings. Foreground/view appearance refresh, generation rejection, and pending-request disabling protect stale display/actions.
- Denied copy is distinct from authorized/provisional/ephemeral with partially disabled reminders. No claim that all channels are disabled or APNs delivery works. A primary 52pt button and ClawTheme follow Figma 85:1309 (read via design context).
- Added 5 native helper methods. New cumulative expectation: SDK30 + storage110 = 140. Windows source-policy evidence is separate; tests/system settings navigation/APNs/device behavior NOT_RUN here.
- No push, server, payload, preference storage semantics, authentication or DB changes. CI7 is immutable 003a1df and excludes this batch.
- Windows final run: 40/40 source-policy scripts PASS; git diff --check PASS. Prior exact old status-label policy was updated to verify the actual native-state helper and notDetermined gate; existing preference/notification routing assertions remain.
