//
//  AppDelegate.swift
//  ios
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import Firebase
import PushKit
import Network
import UIKit
import UserNotifications
import TinodeSDK
import TinodiosDB

enum ClawNotificationPolicy {
    private static let defaults = SharedUtils.kAppDefaults

    static func isGroupTopic(_ topicName: String) -> Bool {
        return topicName.hasPrefix("grp")
    }

    static func allowsMessage(topicName: String) -> Bool {
        let key = isGroupTopic(topicName)
            ? SharedUtils.kClawPrefGroupMessageNotifications
            : SharedUtils.kClawPrefPrivateMessageNotifications
        return defaults.bool(forKey: key)
    }

    static var allowsCalls: Bool {
        return defaults.bool(forKey: SharedUtils.kClawPrefCallNotifications)
    }

    static var showsPreview: Bool {
        return defaults.bool(forKey: SharedUtils.kClawPrefMessagePreview)
    }

    static var vibratesInApp: Bool {
        return defaults.bool(forKey: SharedUtils.kClawPrefInAppVibration)
    }

    static func previewBody(_ body: String?, fallback: String) -> String {
        guard showsPreview, let value = body?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }
}

enum ClawNotificationDiagnostics {
    static func redactedToken(_ token: String) -> String {
        guard token.count > 8 else { return "<redacted:\(token.count)>" }
        return "\(token.prefix(4))…\(token.suffix(4))"
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundSessionCompletionHandler: (() -> Void)?
    // Network reachability.
    var nwReachability: Any!
    var pushNotificationsConfigured = false
    var appIsStarting: Bool = false
    // Video call event listener.
    var callListener = CallEventListener()

    var voipRegistry: PKPushRegistry!

    // Video call event listener (responsible for displaying and dismissing Call UI).
    class CallEventListener: TinodeEventListener {
        func onInfoMessage(info: MsgServerInfo?) {
            guard let info = info, info.what == "call", let seq = info.seq, let topic = info.src else { return }
            switch info.event {
            case  "accept":
                // We have just accepted this call in another client.
                if !Cache.callManager.currentCallIsOutgoing {
                    Cache.callManager.dismissIncomingCall(onTopic: topic, withSeqId: seq)
                }
            case "hang-up":
                Cache.callManager.dismissIncomingCall(onTopic: topic, withSeqId: seq)
            default:
                break
            }
        }
        func onDataMessage(data: MsgServerData?) {
            let tinode = Cache.tinode
            guard let data = data, !tinode.isMe(uid: data.from), let topicName = data.topic else { return }

            guard let callState = data.webrtcCallState else {
                guard ClawNotificationPolicy.allowsMessage(topicName: topicName) else { return }
                DispatchQueue.main.async {
                    (UIApplication.shared.delegate as? AppDelegate)?.presentSocketMessage(data, topicName: topicName)
                }
                return
            }

            // The remaining events are WebRTC call state changes.
            guard let seqId = data.replacesSeq ?? data.seq, let originator = data.from,
                  let topic = tinode.getTopic(topicName: topicName) else { return }

            // Check if we have a later version of the message (which means this call state is outdated).
            guard let msg = topic.getMessage(byEffectiveSeq: seqId) as? StoredMessage,
                  msg.webrtcCallState == callState else { return }

            let isAudioOnly = data.isAudioOnlyCall
            Cache.log.info("Call (topic: %@, seq: %d): processing event %@", topicName, seqId, String(reflecting: callState))
            switch callState {
            case .kStarted:
                guard ClawNotificationPolicy.allowsCalls else { return }
                // It is a legit incoming call. Start it.
                let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                DispatchQueue.main.async {
                    Cache.callManager.displayIncomingCall(uuid: UUID(), onTopic: topic.name, originatingFrom: originator, withSeqId: seqId, audioOnly: isAudioOnly) { err in
                        if let err = err {
                            Cache.log.error("Unable to take the call: %@", err.localizedDescription)
                        }
                        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                    }
                }
            case .kAccepted, .kBusy, .kDeclined, .kMissed, .kDisconnected:
                if !Cache.callManager.currentCallIsOutgoing {
                    Cache.log.info("Dismissing incoming call: topic=%@, seq=%d", topic.name, seqId)
                    Cache.callManager.dismissIncomingCall(onTopic: topic.name, withSeqId: seqId)
                }
            default:
                break
            }
        }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ClawTheme.applyGlobalAppearance()
        Cache.log.info("App launched with options: %@", launchOptions ?? [:])
        if SharedUtils.isFirstLaunch {
            Cache.log.info("First time launch. Setting up...")
            SharedUtils.isFirstLaunch = false
            SharedUtils.identifyAndConfigureBranding()
        }
        SharedUtils.registerUserDefaults()

        let baseDb = BaseDb.sharedInstance
        if baseDb.isReady {
            // When the app launch after user tap on notification (originally was not running / not in background), except incoming calls which are handled separately.
            if let opts = launchOptions, let userInfo = opts[.remoteNotification] as? [String: Any],
                userInfo["webrtc"] == nil, let topicName = userInfo["topic"] as? String, !topicName.isEmpty {
                UiUtils.routeToMessageVC(forTopic: topicName)
            } else {
                UiUtils.routeToChatListVC()
            }
        }

        registerForVoip()

        // Try to connect and login in the background.
        DispatchQueue.global(qos: .userInitiated).async {
            if !SharedUtils.connectAndLoginSync(using: Cache.tinode, inBackground: false) {
                UiUtils.logoutAndRouteToLoginVC()
            }
        }
        Cache.tinode.addListener(self.callListener)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .seconds(10)) {
            let reachability = NWPathMonitor()
            reachability.start(queue: DispatchQueue.global(qos: .background))
            reachability.pathUpdateHandler = { path in
                let tinode = Cache.tinode
                if path.status == .satisfied, !tinode.isConnected {
                    Cache.log.info("NWPathMonitor: network available - reconnecting")
                    tinode.reconnectNow(interactively: false, reset: false)
                }
            }
            self.nwReachability = reachability
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
        // Instantiate large file helper.
        _ = Cache.getLargeFileHelper(withIdentifier: identifier)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        self.appIsStarting = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.appIsStarting = false
        refreshUnreadIndicators()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.appIsStarting = true
        SharedUtils.syncUserDefaults()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if let call = Cache.callManager.callInProgress, !UiUtils.isShowingCallVC(forTopic: call.topic) {
            // App just entered the foreground and there's a call in progress. Go to the CallVC.
            // Typically happens when the app wasn't running and screen was locked at the moment
            // the call was answered.
            Cache.log.info("Navigating to CallVC for topic=%@, seq=%d", call.topic, call.seq)
            UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
                guard let messageVC = messageVC else {
                    Cache.log.error("Unable to navigate to MessageVC for topic=%@.", call.topic)
                    return
                }
                messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
            }
        }
        self.appIsStarting = false
        refreshUnreadIndicators()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        refreshUnreadIndicators()
    }

    // Notification received. Process it.
    // Application woken up in the background (e.g. for data fetch).
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let state = application.applicationState
        let what = userInfo["what"] as? String
        Cache.log.info("Remote notification callback: state=%@ what=%@", String(describing: state), what ?? "msg")
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else {
            Cache.log.error("Remote notification callback rejected: missing topic")
            completionHandler(.failed)
            return
        }
        Cache.log.info("Remote notification payload accepted: topic=%@", topicName)
        defer { refreshUnreadIndicators() }
        if state == .background || (state == .inactive && !self.appIsStarting) {
            if what == nil || what == "msg" {
                // New message.
                guard let seq = Int(userInfo["seq"] as? String ?? ""), seq > 0 else {
                    completionHandler(.failed)
                    return
                }
                var keepConnection = false
                if userInfo["webrtc"] != nil {
                    // Video call. Fetch related messages.
                    keepConnection = true
                }
                // Fetch data in the background.
                completionHandler(SharedUtils.fetchData(using: Cache.tinode, for: topicName, seq: seq, keepConnection: keepConnection))
            } else if what == "sub" {
                // New subscription.
                completionHandler(SharedUtils.fetchDesc(using: Cache.tinode, for: topicName))
            } else if what == "read" {
                // Read notification.
                if let seq = Int(userInfo["seq"] as? String ?? ""), seq > 0 {
                    completionHandler(SharedUtils.updateRead(using: Cache.tinode, for: topicName, seq: seq))
                }
            } else {
                Cache.log.error("Invalid 'what' value ['%@'] in push notification for topic '%@'", what!, topicName)
                completionHandler(.failed)
            }
        } else if state == .inactive && self.appIsStarting {
            // User tapped notification.
            completionHandler(.newData)
        } else {
            // App is active.
            completionHandler(.noData)
        }
    }

    // Tapped on a web link. See if it's an app link.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return false
        }
        // TODO: support 3rd party urls.
        if components.host?.hasSuffix("veilping.app") ?? false {
            // Start the app.
            return true
        }
        return false
    }

    func registerForVoip() {
        self.voipRegistry = PKPushRegistry(queue: nil)
        self.voipRegistry.delegate = self
        self.voipRegistry.desiredPushTypes = [.voIP]
    }

    fileprivate func presentSocketMessage(_ data: MsgServerData, topicName: String) {
        guard ClawNotificationPolicy.allowsMessage(topicName: topicName),
              UIApplication.shared.applicationState == .active,
              let window = window else { return }
        if let messageVC = UiUtils.topViewController(rootViewController: window.rootViewController) as? MessageViewController,
           messageVC.topicName == topicName {
            refreshUnreadIndicators()
            return
        }

        let topic = Cache.tinode.getTopic(topicName: topicName) as? DefaultComTopic
        let notice = ClawMessageNotice(topic: topicName,
                                       title: topic?.pub?.fn,
                                       body: data.content?.txt,
                                       seq: data.seq)
        guard notice.canOpenTopic else { return }
        let safeTitle = !notice.title.isEmpty ? notice.title : NSLocalizedString("new_message", comment: "In-app message notice title")
        let safeBody = ClawNotificationPolicy.previewBody(
            notice.body,
            fallback: NSLocalizedString("new_message_hidden", comment: "In-app message notice fallback body"))
        let messageKey = notice.deliveryKey
        Cache.log.info("Presenting socket message notice: key=%@ topic=%@", messageKey, notice.topic)
        ClawInAppMessageBanner.present(in: window, title: safeTitle, body: safeBody,
                                       topicName: notice.topic, messageKey: messageKey)
        if ClawNotificationPolicy.vibratesInApp {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        refreshUnreadIndicators()
    }

    private func refreshUnreadIndicators() {
        let unread = Cache.totalUnreadCount()
        UIApplication.shared.applicationIconBadgeNumber = unread
        DispatchQueue.main.async { [weak self] in
            (self?.window?.rootViewController as? ClawMainTabBarController)?.refreshMessageBadge()
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Cache.log.info("APNs registration succeeded: token=%@ length=%d",
                       ClawNotificationDiagnostics.redactedToken(token), token.count)
        // Keep this explicit so FCM receives the APNs token even when Firebase
        // method swizzling is disabled by a host application.
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Cache.log.error("APNs registration failed: %@", error.localizedDescription)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    private static func notificationSeq(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    // Notification received. Process it.
    // Called when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let what = userInfo["what"] as? String
        // Only handling "msg" notifications. New subscriptions ("sub" notifications) in the foreground
        // will be handled automatically by Tinode SDK.
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty,
            what == nil || what == "msg", let seq = Self.notificationSeq(from: userInfo["seq"]) else {
            Cache.log.error("Foreground notification callback rejected: missing or invalid topic/seq")
            completionHandler([])
            return
        }

        Cache.log.info("Foreground notification callback: topic=%@ seq=%d", topicName, seq)

        guard ClawNotificationPolicy.allowsMessage(topicName: topicName) else {
            Cache.log.info("Foreground notification suppressed: message preference disabled for topic=%@", topicName)
            completionHandler([])
            return
        }

        if let messageVC = UiUtils.topViewController(rootViewController: (UIApplication.shared.delegate as! AppDelegate).window?.rootViewController) as? MessageViewController, messageVC.topicName == topicName {
            // We are already in the correct topic. Do not present the notification.
            Cache.log.info("Foreground notification suppressed: topic already visible=%@", topicName)
            completionHandler([])
        } else {
            DispatchQueue.global(qos: .background).async {
                SharedUtils.fetchData(using: Cache.tinode, for: topicName, seq: seq, keepConnection: false)
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = Cache.totalUnreadCount()
                    (self.window?.rootViewController as? ClawMainTabBarController)?.refreshMessageBadge()
                }
            }
            // If the push notification is either silent or a video call related, do not present the alert.
            let suppressNotification = userInfo["silent"] as? String == "true" || userInfo["webrtc"] != nil
            if suppressNotification {
                Cache.log.info("Foreground notification suppressed: silent or call payload for topic=%@", topicName)
                completionHandler([])
                return
            }

            Cache.log.info("Presenting foreground system notification: topic=%@ seq=%d", topicName, seq)
            completionHandler([.badge, .banner, .list, .sound])
        }
    }

    // User tapped on notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let topicName = userInfo["topic"] as? String ?? "<missing>"
        Cache.log.info("Notification response callback: action=%@ topic=%@",
                       response.actionIdentifier, topicName)
        defer { completionHandler() }
        guard topicName != "<missing>", !topicName.isEmpty else {
            Cache.log.error("Notification response rejected: missing topic")
            return
        }
        let tinode = Cache.tinode
        if tinode.isConnectionAuthenticated {
            UiUtils.routeToMessageVC(forTopic: topicName)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if !SharedUtils.connectAndLoginSync(using: tinode, inBackground: false) {
                DispatchQueue.main.async { UiUtils.showToast(message: "Failed to connect to server") }
            } else {
                UiUtils.routeToMessageVC(forTopic: topicName)
            }
        }
    }
}

private final class ClawInAppMessageBanner: UIControl {
    private static weak var visibleBanner: ClawInAppMessageBanner?
    private static var lastMessageKey: String?
    private static var lastPresentationTime: TimeInterval = 0

    private let topicName: String
    private var dismissWorkItem: DispatchWorkItem?

    static func present(in window: UIWindow, title: String, body: String,
                        topicName: String, messageKey: String) {
        let now = Date.timeIntervalSinceReferenceDate
        if lastMessageKey == messageKey && now - lastPresentationTime < 10 {
            return
        }
        lastMessageKey = messageKey
        lastPresentationTime = now
        visibleBanner?.dismiss(animated: false)
        let banner = ClawInAppMessageBanner(title: title, body: body, topicName: topicName)
        visibleBanner = banner
        window.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
        window.layoutIfNeeded()

        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: -20)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            banner.alpha = 1
            banner.transform = .identity
        }
        banner.scheduleDismissal()
    }

    private init(title: String, body: String, topicName: String) {
        self.topicName = topicName
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = ClawTheme.surface
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = ClawTheme.border.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
        accessibilityIdentifier = "claw.message.notice"
        accessibilityLabel = "\(title)，\(body)"
        accessibilityTraits = [.button]
        addTarget(self, action: #selector(openConversation), for: .touchUpInside)

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = ClawTheme.brandSoft
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        let icon = UIImageView(image: ClawTheme.symbol("message.fill", pointSize: 20, weight: .semibold))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = ClawTheme.primary
        icon.contentMode = .scaleAspectFit
        iconContainer.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = ClawTheme.ink
        titleLabel.numberOfLines = 1

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        bodyLabel.textColor = ClawTheme.muted
        bodyLabel.numberOfLines = 2
        bodyLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        ClawTheme.styleIconButton(closeButton, symbolName: "xmark", pointSize: 14, tintColor: ClawTheme.muted)
        closeButton.accessibilityLabel = NSLocalizedString("关闭", comment: "Close message notice")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 68),
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: ClawTheme.touchTarget),
            closeButton.heightAnchor.constraint(equalToConstant: ClawTheme.touchTarget)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func scheduleDismissal() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    @objc private func openConversation() {
        dismiss(animated: true)
        UiUtils.routeToMessageVC(forTopic: topicName)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard animated else {
            removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.16, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -12)
        }, completion: { _ in self.removeFromSuperview() })
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Update token. Send to the app server.
        guard let token = fcmToken, !token.isEmpty else {
            Cache.log.error("FCM registration callback returned no token")
            return
        }
        Cache.log.info("FCM registration succeeded: token=%@ length=%d",
                       ClawNotificationDiagnostics.redactedToken(token), token.count)
        Cache.tinode.setDeviceToken(token: token)
    }
}

extension AppDelegate: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        Cache.log.info("PK token received %@", credentials.debugDescription)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        Cache.log.info("PK must invalidate token")
    }

    // VoIP push notification recived.
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        Cache.log.info("PK push %s", payload.debugDescription)

        guard type == .voIP else {
            completion()
            return
        }

        // Cannot defer completion() because it's called from a closure.

        guard let data = payload.dictionaryPayload["data"] as? [String: Any], let topicName = data["topic"] as? String, let callState = data["webrtc"] as? String else {
            Cache.log.error("Missing payload data")
            completion()
            return
        }

        switch callState {
        case MsgServerData.WebRTC.kStarted.rawValue:
            guard ClawNotificationPolicy.allowsCalls else {
                completion()
                return
            }
            guard let callerUID = data["xfrom"] as? String, !Cache.tinode.isMe(uid: callerUID), let seq = Int(data["seq"] as? String ?? ""), seq > 0 else {
                completion()
                return
            }
            let audioOnly = (data["aonly"] as? Bool) ?? false
            // Report the call to CallKit, and let it display the call UI.
            Cache.callManager.displayIncomingCall(uuid: UUID(), onTopic: topicName, originatingFrom: callerUID, withSeqId: seq, audioOnly: audioOnly, completion: { err in
                // Tell PushKit that the notification is handled.
                completion()
            })
        case MsgServerData.WebRTC.kAccepted.rawValue, MsgServerData.WebRTC.kBusy.rawValue, MsgServerData.WebRTC.kMissed.rawValue, MsgServerData.WebRTC.kDeclined.rawValue, MsgServerData.WebRTC.kDisconnected.rawValue:
            // This should not happen: the server sends just the "started" push as voip.
            guard let origSeq = Int(data["replace"] as? String ?? ""), origSeq > 0 else { return }
            Cache.callManager.dismissIncomingCall(onTopic: topicName, withSeqId: origSeq)
            fallthrough
        default:
            completion()
            break
        }
    }
}
