//
//  CallManager.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import CallKit
import WebRTC

extension Notification.Name {
    static let clawCallHistoryDidChange = Notification.Name("clawCallHistoryDidChange")
}

struct ClawCallHistoryRecord: Codable, Equatable {
    let id: UUID
    let topic: String
    let startedAt: Date
    let duration: TimeInterval
    let outgoing: Bool
    let audioOnly: Bool
    let connected: Bool

    var missed: Bool {
        return !connected && !outgoing
    }
}

enum ClawCallHistoryStore {
    private static let keyPrefix = "claw.call.history."
    private static let maximumRecordCount = 100

    private static var storageKey: String {
        return keyPrefix + (Cache.tinode.myUid ?? "signed-out")
    }

    static func records(defaults: UserDefaults = .standard) -> [ClawCallHistoryRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClawCallHistoryRecord].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.startedAt > $1.startedAt }
    }

    static func filtered(_ records: [ClawCallHistoryRecord], missedOnly: Bool) -> [ClawCallHistoryRecord] {
        return missedOnly ? records.filter { $0.missed } : records
    }

    @discardableResult
    static func delete(id: UUID, defaults: UserDefaults = .standard) -> Bool {
        let current = records(defaults: defaults)
        let updated = current.filter { $0.id != id }
        guard updated.count != current.count else { return true }
        return persist(updated, defaults: defaults)
    }

    @discardableResult
    static func clear(defaults: UserDefaults = .standard) -> Bool {
        defaults.removeObject(forKey: storageKey)
        notifyChanged()
        return true
    }

    static func append(call: CallManager.Call, outgoing: Bool,
                       defaults: UserDefaults = .standard, now: Date = Date()) {
        let record = ClawCallHistoryRecord(
            id: call.uuid,
            topic: call.topic,
            startedAt: call.startedAt,
            duration: call.connected ? max(0, now.timeIntervalSince(call.startedAt)) : 0,
            outgoing: outgoing,
            audioOnly: call.audioOnly,
            connected: call.connected)
        var updated = records(defaults: defaults).filter { $0.id != record.id }
        updated.insert(record, at: 0)
        if updated.count > maximumRecordCount {
            updated.removeLast(updated.count - maximumRecordCount)
        }
        _ = persist(updated, defaults: defaults)
    }

    private static func persist(_ records: [ClawCallHistoryRecord],
                                defaults: UserDefaults) -> Bool {
        guard let data = try? JSONEncoder().encode(records) else { return false }
        defaults.set(data, forKey: storageKey)
        notifyChanged()
        return true
    }

    private static func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clawCallHistoryDidChange, object: nil)
        }
    }
}

class CallManager {
    private static let kCallTimeout = 30

    public struct Call {
        var uuid: UUID
        var topic: String
        var from: String
        var seq: Int
        var audioOnly: Bool
        var startedAt: Date
        var connected: Bool
    }

    enum CallError: Error {
        case busy(String)
    }

    var callDelegate: CallProviderDelegate!
    var callController: CXCallController!
    var callInProgress: Call?
    // Dismisses call UI after timeout.
    var timer: Timer?
    private var usesSystemCallUI = false

    // Returns true if the user originated the call.
    var currentCallIsOutgoing: Bool {
        guard let call = self.callInProgress else { return false }
        let tinode = Cache.tinode
        return tinode.isMe(uid: call.from)
    }

    init() {
        callDelegate = CallProviderDelegate(callManager: self)
        callController = CXCallController()
    }

    private func makeCallTimeoutTimer(withDeadline deadline: TimeInterval) -> Timer {
        let timer = Timer(timeInterval: deadline, repeats: false) { timer in
            timer.invalidate()
            self.timer = nil
            if let call = self.callInProgress {
                Cache.log.info("Call timed out: topic=%@, seq=%d", call.topic, call.seq)
                self.completeCallInProgress(
                    reportToSystem: self.usesSystemCallUI,
                    reportToPeer: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // Utility function to configure RTCAudioSession.
    public static func audioSessionChange(action: ((RTCAudioSession) throws -> Void)) {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try action(audioSession)
        } catch {
            Cache.log.error("WebRTCClient: error changing AVAudioSession: %@", error.localizedDescription)
        }
        audioSession.unlockForConfiguration()
    }

    public static func activateAudioSession(withSpeaker speaker: Bool) {
        self.audioSessionChange { audioSession in
            try audioSession.setCategory(AVAudioSession.Category(rawValue: AVAudioSession.Category.playAndRecord.rawValue))
            try audioSession.setMode(AVAudioSession.Mode(rawValue: AVAudioSession.Mode.voiceChat.rawValue))
            try audioSession.overrideOutputAudioPort(speaker ? .speaker : .none)
            try audioSession.setActive(true)
        }
    }

    public static func deactivateAudioSession() {
        // Clean up audio.
        self.audioSessionChange { audioSession in
            try audioSession.setActive(false)
        }
    }

    // Registers an outgoing call that's just been started.
    func registerOutgoingCall(onTopic topicName: String, isAudioOnly: Bool) -> Bool {
        guard self.callInProgress == nil else {
            // Another call is in progress. Quit.
            return false
        }
        let tinode = Cache.tinode
        guard let myUid = tinode.myUid, !myUid.isEmpty,
              ContactsManager.isDirectContactId(topicName) else {
            Cache.log.error("CallManager: cannot start a call without an authenticated user and topic")
            return false
        }
        self.callInProgress = Call(uuid: UUID(), topic: topicName, from: myUid, seq: -1,
                                   audioOnly: isAudioOnly, startedAt: Date(), connected: false)
        CallManager.activateAudioSession(withSpeaker: !isAudioOnly)
        Cache.log.info("Starting outgoing call (uuid: %@) on topic: %@", self.callInProgress!.uuid.uuidString, topicName)
        return true
    }

    // Sets seq id on the current call.
    func updateOutgoingCall(withNewSeqId seq: Int) {
        self.callInProgress?.seq = seq
    }

    // Report incoming call to the operating system (which displays incoming call UI).
    func displayIncomingCall(uuid: UUID, onTopic topicName: String, originatingFrom fromUid: String, withSeqId seq: Int, audioOnly: Bool, completion: ((Error?) -> Void)?) {
        guard ContactsManager.isDirectContactId(topicName), !fromUid.isEmpty, seq > 0 else {
            Cache.log.error("CallManager: rejected malformed incoming call topic=%@, from=%@, seq=%d", topicName, fromUid, seq)
            if ContactsManager.isDirectContactId(topicName), seq > 0 {
                Cache.tinode.videoCall(topic: topicName, seq: seq, event: "hang-up")
            }
            completion?(NSError(
                domain: "app.veilping.clawoschat.call",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "收到的通话请求无效",
                    comment: "Invalid incoming call request")]))
            return
        }
        guard self.callInProgress == nil else {
            if seq == self.callInProgress!.seq && self.callInProgress!.topic == topicName {
                // FIXME: this should not really happen. Find the source of duplicates and fix it.
                return
            }
            Cache.log.info("Hanging up: another call in progress")
            let tinode = Cache.tinode
            tinode.videoCall(topic: topicName, seq: seq, event: "hang-up")
            completion?(CallError.busy("Busy. Another call in progress"))
            return
        }

        self.callInProgress = Call(uuid: uuid, topic: topicName, from: fromUid, seq: seq,
                                   audioOnly: audioOnly, startedAt: Date(), connected: false)
        let tinode = Cache.tinode
        let user: DefaultUser? = tinode.getUser(with: fromUid)
        let senderName = user?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        callDelegate.reportIncomingCall(uuid: uuid, handle: senderName, audioOnly: audioOnly) { err in
            if err == nil {
                self.usesSystemCallUI = true
                Cache.log.info("Reporting incoming call (uuid: %@) on topic: %@, seq: %d", self.callInProgress?.uuid.uuidString ?? "missing", topicName, seq)
                CallManager.activateAudioSession(withSpeaker: !audioOnly)
                tinode.videoCall(topic: topicName, seq: seq, event: "ringing")
                let timeout = (tinode.getServerParam(for: "callTimeout")?.asInt() ?? CallManager.kCallTimeout) + 5
                self.timer = self.makeCallTimeoutTimer(withDeadline: TimeInterval(timeout))
            } else {
                self.usesSystemCallUI = false
                Cache.log.error("Incoming call (topic: %@, seq: %d) error: %@", topicName, seq, err!.localizedDescription)
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString(
                        "系统来电界面不可用，已切换到应用内接听",
                        comment: "Incoming call CallKit fallback notice"))
                    self.routeIncomingCallToApp(call: self.callInProgress)
                }
            }
            completion?(err)
        }
    }

    private func routeIncomingCallToApp(call: Call?) {
        guard let call = call else { return }
        CallManager.activateAudioSession(withSpeaker: !call.audioOnly)
        Cache.tinode.videoCall(topic: call.topic, seq: call.seq, event: "ringing")
        let timeout = (Cache.tinode.getServerParam(for: "callTimeout")?.asInt()
            ?? CallManager.kCallTimeout) + 5
        self.timer?.invalidate()
        self.timer = self.makeCallTimeoutTimer(withDeadline: TimeInterval(timeout))
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            guard let messageVC = messageVC else {
                self.completeCallInProgress(reportToSystem: false, reportToPeer: true)
                return
            }
            let user: DefaultUser? = Cache.tinode.getUser(with: call.from)
            let senderName = user?.pub?.fn ?? NSLocalizedString("未知联系人", comment: "Unknown caller")
            let callType = call.audioOnly
                ? NSLocalizedString("语音来电", comment: "Incoming audio call")
                : NSLocalizedString("视频来电", comment: "Incoming video call")
            let alert = UIAlertController(
                title: callType,
                message: String(format: NSLocalizedString("%@ 正在呼叫你", comment: "Incoming caller prompt"), senderName),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("拒绝", comment: "Decline incoming call"),
                style: .destructive) { _ in
                    self.completeCallInProgress(reportToSystem: false, reportToPeer: true)
                })
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("接听", comment: "Answer incoming call"),
                style: .default) { _ in
                    self.timer?.invalidate()
                    self.timer = nil
                    messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
                })
            messageVC.present(alert, animated: true)
        }
    }

    // Dismisses incoming call UI without displaying.
    func dismissIncomingCall(onTopic topic: String, withSeqId seq: Int) {
        guard let call = self.callInProgress, call.topic == topic, call.seq == seq else {
            return
        }
        self.completeCallInProgress(reportToSystem: self.usesSystemCallUI, reportToPeer: false)
    }
}

extension CallManager: CallManagerImpl {
    func markCurrentCallConnected() {
        guard var call = self.callInProgress, !call.connected else { return }
        call.connected = true
        self.callInProgress = call
    }

    func acceptPendingCall() -> Bool {
        guard let call = self.callInProgress else { return false }

        Cache.log.info("Accepting call: topic=%@, seq=%d", call.topic, call.seq)
        self.timer?.invalidate()
        self.timer = nil
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            guard let messageVC = messageVC else {
                self.completeCallInProgress(
                    reportToSystem: self.usesSystemCallUI,
                    reportToPeer: true)
                return
            }
            Cache.log.info("Seguing from MessageVC to CallVC, topic=%@ -> %@", call.topic, messageVC)
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
        }
        return true
    }

    func completeCallInProgress(reportToSystem: Bool, reportToPeer: Bool) {
        guard let call = self.callInProgress else { return }
        Cache.log.info("Completing call: topic=%@, seq=%d", call.topic, call.seq)
        ClawCallHistoryStore.append(call: call, outgoing: Cache.tinode.isMe(uid: call.from))
        self.callInProgress = nil
        self.usesSystemCallUI = false
        self.timer?.invalidate()
        self.timer = nil
        CallManager.deactivateAudioSession()

        if reportToPeer {
            // Tell the peer the call is over/declined.
            Cache.tinode.videoCall(topic: call.topic, seq: call.seq, event: "hang-up")
        }
        if reportToSystem {
            // Tell the OS that the call is over/declined.
            let endCallAction = CXEndCallAction(call: call.uuid)
            let transaction = CXTransaction(action: endCallAction)

            Cache.log.info("Ending call (uuid: %@) on topic: %@, seq: %d", call.uuid.uuidString, call.topic, call.seq)
            self.callController.request(transaction) { error in
                if let error = error {
                    Cache.log.error("CallManager - EndCallAction transaction request failed: %@", error.localizedDescription)
                    return
                }
            }
        }
    }

    func completeActiveCallFromApp(reportToPeer: Bool) {
        completeCallInProgress(reportToSystem: usesSystemCallUI, reportToPeer: reportToPeer)
    }
}
