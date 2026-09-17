//
//  NotificationService.swift
//  TinodiosNSExtension
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import UserNotifications
import TinodeSDK
import TinodiosDB

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        // C2/C3 push payloads have no verified recipient UID; xfrom is sender.
        // A same-name topic in the active account cannot prove ownership.
        // Do not log in, read private caches, or display the supplied body here.
        let safeContent = bestAttemptContent ?? UNMutableNotificationContent()
        safeContent.title = "CLAW OS"
        safeContent.subtitle = ""
        safeContent.body = "收到新消息，打开应用查看"
        safeContent.attachments = []
        safeContent.badge = nil
        self.bestAttemptContent = safeContent
        contentHandler(safeContent)
        self.contentHandler = nil
    }

    override func serviceExtensionTimeWillExpire() {
        // 30 seconds.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
