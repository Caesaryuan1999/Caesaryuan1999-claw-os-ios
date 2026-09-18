//
//  TinodeSDKTests.swift
//  TinodeSDKTests
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import XCTest
@testable import TinodeSDK

// TODO: add tests for Tinode here.
class TinodeSDKTests: XCTestCase {

    func testLogoutRetiresLocalSessionWithoutNetworkAndClearsCredentials() throws {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        sdk.myUid = "usrA"
        sdk.authToken = "synthetic-token"
        sdk.authTokenExpires = Date().addingTimeInterval(60)
        sdk.deviceToken = "synthetic-device"
        sdk.isConnectionAuthenticated = true
        sdk.setAutoLoginWithToken(token: "synthetic-token")
        let topic = DefaultComTopic(tinode: sdk, name: "grpA")
        sdk.startTrackingTopic(topic: topic)
        sdk.logout()
        XCTAssertFalse(sdk.isSessionActive)
        XCTAssertFalse(sdk.isConnectionAuthenticated)
        XCTAssertNil(sdk.myUid)
        XCTAssertNil(sdk.authToken)
        XCTAssertNil(sdk.authTokenExpires)
        XCTAssertNil(sdk.deviceToken)
        XCTAssertNil(sdk.getTopic(topicName: "grpA"))
        XCTAssertFalse(sdk.reconnectNow(interactively: true, reset: true))
        XCTAssertThrowsError(try sdk.connect(to: "127.0.0.1:9", useTLS: false, inBackground: false))
        XCTAssertThrowsError(try sdk.loginToken(token: "synthetic", creds: nil).getResult())
        XCTAssertThrowsError(try sdk.setDeviceToken(token: "late-device").getResult())
        var oldCallbackRan = false
        sdk.withActiveSession { oldCallbackRan = true }
        XCTAssertFalse(oldCallbackRan)
        sdk.logout() // Repeated stale logout is inert.
    }

    func testSessionGateSerializesInFlightCallbackBeforeLogout() {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let completed = expectation(description: "guarded callback ends")
        DispatchQueue.global().async {
            sdk.withActiveSession {
                entered.signal()
                _ = release.wait(timeout: .now() + 3)
                sdk.authToken = "synthetic-before-logout"
            }
            completed.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 3), .success)
        release.signal()
        sdk.logout()
        wait(for: [completed], timeout: 3)
        XCTAssertNil(sdk.authToken)
        XCTAssertNil(sdk.withActiveSession { "stale" })
    }

    func testQueuedConsumerCallbackIsSuppressedAfterSessionRetirement() {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        let queue = DispatchQueue(label: "fixture.consumer")
        queue.suspend()
        let stale = expectation(description: "stale callback cannot run")
        stale.isInverted = true
        sdk.dispatchIfActive(on: queue) { stale.fulfill() }
        sdk.logout()
        queue.resume()
        wait(for: [stale], timeout: 0.1)
    }

    func testConsumerCallbackRunsOnMainWithoutHoldingSDKSessionLock() {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        let complete = expectation(description: "consumer and concurrent logout finish")
        sdk.dispatchIfActive {
            XCTAssertTrue(Thread.isMainThread)
            let loggedOut = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { sdk.logout(); loggedOut.signal() }
            // Would deadlock/time out if the callback still owned the SDK lock.
            XCTAssertEqual(loggedOut.wait(timeout: .now() + 2), .success)
            complete.fulfill()
        }
        wait(for: [complete], timeout: 3)
    }

    func testCleanupBoundaryRemainsAvailableForRetiredSession() {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        sdk.logout()
        var cleaned = false
        sdk.withSessionLock { cleaned = true }
        XCTAssertTrue(cleaned)
        XCTAssertNil(sdk.withActiveSession { true })
    }

    func testPublishTimeoutNeverReturnsToAutomaticQueue() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.requestOutcomeUnknown("reply timed out")), .unconfirmed)
    }

    func testPublishDisconnectAfterDispatchNeverReturnsToAutomaticQueue() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.requestOutcomeUnknown("connection closed")), .unconfirmed)
    }

    func testPublishOfflineBeforeDispatchCanRemainQueued() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.notConnected("connection is not open")), .queued)
    }

    func testDraftOrSubscriptionFailureDoesNotClaimAnUnknownServerOutcome() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.requestNotSent("draft could not be saved")), .queued)
    }

    func testExplicitPermissionRejectionIsFailedAndNotQueued() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.serverResponseError(403, "permission denied", nil)), .failed)
    }

    func testGatewayFailureAndUnexpectedFailureRemainUnconfirmed() {
        XCTAssertEqual(PublishFailureDisposition.forError(
            TinodeError.serverResponseError(504, "gateway timeout", nil)), .unconfirmed)
        XCTAssertEqual(PublishFailureDisposition.forError(
            NSError(domain: "test.transport", code: 1)), .unconfirmed)
    }

    func testPublishConfirmationRejectsMissingOrNonPositiveSequence() throws {
        for json in [
            "{\"ctrl\":{\"id\":\"1\",\"code\":200,\"text\":\"ok\",\"ts\":\"2026-09-17T12:00:00Z\"}}",
            "{\"ctrl\":{\"id\":\"1\",\"code\":200,\"text\":\"ok\",\"ts\":\"2026-09-17T12:00:00Z\",\"params\":{\"seq\":0}}}",
            "{\"ctrl\":{\"id\":\"1\",\"code\":403,\"text\":\"denied\",\"ts\":\"2026-09-17T12:00:00Z\",\"params\":{\"seq\":10}}}"
        ] {
            let packet = try Tinode.jsonDecoder.decode(ServerMessage.self, from: Data(json.utf8))
            XCTAssertThrowsError(try PublishConfirmation.sequence(from: packet.ctrl))
        }
        XCTAssertThrowsError(try PublishConfirmation.sequence(from: nil))
    }

    func testPublishConfirmationUsesServerSequence() throws {
        let json = "{\"ctrl\":{\"id\":\"7\",\"code\":202,\"text\":\"accepted\",\"ts\":\"2026-09-17T12:00:00Z\",\"params\":{\"seq\":42}}}"
        let packet = try Tinode.jsonDecoder.decode(ServerMessage.self, from: Data(json.utf8))
        XCTAssertEqual(try PublishConfirmation.sequence(from: packet.ctrl), 42)
    }

    func testC3UUIDIsFreshLowercaseV4AndOverridesForwardedIdentity() {
        let old: [String: JSONValue] = ["clientmsgid": .string("abcdefab-1111-4111-8111-abcdefabcdef"), "reply": .int(7)]
        let first = C3PublishPolicy.newHeaders(old, content: Drafty(plainText: "copy"))
        let second = C3PublishPolicy.newHeaders(old, content: Drafty(plainText: "copy"))
        XCTAssertNotNil(C3PublishPolicy.clientMessageId(in: first))
        XCTAssertNotEqual(C3PublishPolicy.clientMessageId(in: first), C3PublishPolicy.clientMessageId(in: old))
        XCTAssertNotEqual(C3PublishPolicy.clientMessageId(in: first), C3PublishPolicy.clientMessageId(in: second))
        XCTAssertEqual(first["reply"]?.asInt(), 7)
        XCTAssertNil(C3PublishPolicy.clientMessageId(in: ["clientmsgid": .string("ABCDEFAB-1111-4111-8111-ABCDEFABCDEF")]))
    }

    func testC3ConflictReasonDecodedFromWirePreservesOther409Context() throws {
        for reason in ["clientmsgid_conflict", "must_attach_first"] {
            let json = "{\"ctrl\":{\"id\":\"7\",\"code\":409,\"text\":\"must attach first\",\"ts\":\"2026-09-18T01:00:00Z\",\"params\":{\"reason\":\"\(reason)\",\"what\":\"pub\"}}}"
            let packet = try Tinode.jsonDecoder.decode(ServerMessage.self, from: Data(json.utf8))
            let ctrl = try XCTUnwrap(packet.ctrl)
            let error = TinodeError.serverResponseError(ctrl.code, C3PublishPolicy.rejectionText(ctrl), ctrl.getStringParam(for: "what"))
            XCTAssertEqual(PublishFailureDisposition.forError(error), .failed)
            if reason == "clientmsgid_conflict" { XCTAssertTrue(error.localizedDescription.contains("内容已变化")) }
            else { XCTAssertTrue(error.localizedDescription.contains("must attach first")) }
        }
    }

    func testC3DirectPublishWithoutCurrentCapabilityRejectsBeforeTransport() {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture", persistDataIn: nil)
        XCTAssertFalse(sdk.supportsDurablePublish)
        let result = sdk.publish(topic: "grpFixtureA", head: nil, content: Drafty(plainText: "keep local"), attachments: nil)
        XCTAssertTrue(result.isRejected)
    }

    func testLateFailureCannotChangeAResolvedRequest() throws {
        let reply = PromisedReply<Int>()
        try reply.resolve(result: 42)
        XCTAssertThrowsError(try reply.reject(error: TinodeError.requestOutcomeUnknown("late disconnect")))
        XCTAssertEqual(try reply.getResult(), 42)
    }


    private func deletionFixture() -> (Tinode, AccountDeletionStoreSpy) {
        let store = AccountDeletionStoreSpy()
        let sdk = Tinode(for: "delete-fixture", authenticateWith: "fixture", persistDataIn: store)
        sdk.authToken = "synthetic-token"
        return (sdk, store)
    }

    private func deletionPacket(code: Int, id: String = "delete-fixture") throws -> ServerMessage {
        let payload: [String: Any] = ["ctrl": ["id": id, "code": code, "text": "fixture"]]
        return try Tinode.jsonDecoder.decode(ServerMessage.self,
            from: JSONSerialization.data(withJSONObject: payload))
    }

    private func assertDeletionUnknown(code: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let (sdk, store) = deletionFixture()
        let outcome = sdk.finishAccountDeletion(packet: try deletionPacket(code: code),
            requestId: "delete-fixture", ownerUid: "usrDeleteA")
        XCTAssertThrowsError(try XCTUnwrap(outcome).getResult(), file: file, line: line) { error in
            guard case TinodeError.requestOutcomeUnknown = error else {
                XCTFail("Expected uncertain deletion outcome", file: file, line: line); return
            }
        }
        XCTAssertTrue(store.deleted.isEmpty, file: file, line: line)
        XCTAssertEqual(store.logoutCalls, 0, file: file, line: line)
        XCTAssertTrue(sdk.isSessionActive, file: file, line: line)
        XCTAssertEqual(sdk.authToken, "synthetic-token", file: file, line: line)
    }

    func testAccountDeletion300CannotDeleteOrLogout() throws {
        try assertDeletionUnknown(code: 300)
    }

    func testAccountDeletion205CannotDeleteOrLogout() throws {
        try assertDeletionUnknown(code: 205)
    }

    func testAccountDeletion200ForExactRequestDeletesOnlyCapturedAccountAndRetires() throws {
        let (sdk, store) = deletionFixture()
        XCTAssertNil(sdk.finishAccountDeletion(packet: try deletionPacket(code: 200),
            requestId: "delete-fixture", ownerUid: "usrDeleteA"))
        XCTAssertEqual(store.deleted, ["usrDeleteA"])
        XCTAssertFalse(sdk.isSessionActive)
        XCTAssertNil(sdk.myUid)
        XCTAssertNil(sdk.authToken)
    }

    func testAccountDeletionMissingControlOrWrongRequestCannotCleanup() throws {
        for packet in [nil, ServerMessage(), try deletionPacket(code: 200, id: "other-request")] {
            let (sdk, store) = deletionFixture()
            let outcome = sdk.finishAccountDeletion(packet: packet,
                requestId: "delete-fixture", ownerUid: "usrDeleteA")
            XCTAssertThrowsError(try XCTUnwrap(outcome).getResult())
            XCTAssertTrue(store.deleted.isEmpty)
            XCTAssertEqual(store.logoutCalls, 0)
            XCTAssertTrue(sdk.isSessionActive)
        }
        XCTAssertThrowsError(try Tinode.jsonDecoder.decode(ServerMessage.self, from: Data("{".utf8)))
    }

    func testAccountDeletion403CannotCleanupEvenIfPassedToCompletion() throws {
        // Public dispatch rejects 403 before this helper; source policy preserves that branch.
        try assertDeletionUnknown(code: 403)
    }

    func testAccountDeletionRetiredOwnerIgnoresLate200() throws {
        let (sdk, store) = deletionFixture()
        sdk.logout()
        store.myUid = "usrDeleteB"
        let priorLogoutCount = store.logoutCalls
        let outcome = sdk.finishAccountDeletion(packet: try deletionPacket(code: 200),
            requestId: "delete-fixture", ownerUid: "usrDeleteA")
        XCTAssertThrowsError(try XCTUnwrap(outcome).getResult())
        XCTAssertTrue(store.deleted.isEmpty)
        XCTAssertEqual(store.myUid, "usrDeleteB")
        XCTAssertEqual(store.logoutCalls, priorLogoutCount)
    }

    func testAccountDeletionStoreAccountChangeRejectsLate200() throws {
        let (sdk, store) = deletionFixture()
        store.myUid = "usrDeleteB"
        let outcome = sdk.finishAccountDeletion(packet: try deletionPacket(code: 200),
            requestId: "delete-fixture", ownerUid: "usrDeleteA")
        XCTAssertThrowsError(try XCTUnwrap(outcome).getResult())
        XCTAssertTrue(store.deleted.isEmpty)
        XCTAssertEqual(store.myUid, "usrDeleteB")
        XCTAssertEqual(store.logoutCalls, 0)
        XCTAssertTrue(sdk.isSessionActive)
    }

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPushConfigurationAcceptsCompleteEnabledConfiguration() {
        XCTAssertTrue(PushConfigurationPolicy.isUsable(validPushConfiguration()))
    }

    func testPushConfigurationRejectsDisabledConfiguration() {
        var configuration = validPushConfiguration()
        configuration["IS_GCM_ENABLED"] = false

        XCTAssertFalse(PushConfigurationPolicy.isUsable(configuration))
    }

    func testPushConfigurationRejectsPlaceholderConfiguration() {
        var configuration = validPushConfiguration()
        configuration["PROJECT_ID"] = "claw-os-placeholder"

        XCTAssertFalse(PushConfigurationPolicy.isUsable(configuration))
    }

    func testPushConfigurationRejectsMissingRequiredValue() {
        var configuration = validPushConfiguration()
        configuration.removeValue(forKey: "GOOGLE_APP_ID")

        XCTAssertFalse(PushConfigurationPolicy.isUsable(configuration))
    }

    func testPushConfigurationRejectsZeroSenderId() {
        var configuration = validPushConfiguration()
        configuration["GCM_SENDER_ID"] = "000000000000"

        XCTAssertFalse(PushConfigurationPolicy.isUsable(configuration))
    }

    func testSubscriptionIndexDeduplicatesUsersAndKeepsNewestRecord() {
        let older = DefaultSubscription()
        older.user = "usrDuplicate"
        older.updated = Date(timeIntervalSince1970: 100)
        older.read = 1

        let newer = DefaultSubscription()
        newer.user = "usrDuplicate"
        newer.updated = Date(timeIntervalSince1970: 200)
        newer.read = 4

        let indexed = DefaultTopic.indexSubscriptions([older, newer])

        XCTAssertEqual(indexed.count, 1)
        XCTAssertTrue(indexed["usrDuplicate"] === newer)
        XCTAssertEqual(indexed["usrDuplicate"]?.getRead, 4)
    }

    func testSubscriptionIndexSkipsMalformedCachedRows() {
        let missingUser = DefaultSubscription()
        let incompatibleType = FndSubscription()
        incompatibleType.user = "usrWrongType"

        let valid = DefaultSubscription()
        valid.user = "usrValid"

        let indexed = DefaultTopic.indexSubscriptions([missingUser, incompatibleType, valid])

        XCTAssertEqual(Array(indexed.keys), ["usrValid"])
        XCTAssertTrue(indexed["usrValid"] === valid)
    }

    func testPrivateCommentFirstValueEncodesOnlyCommentDelta() throws {
        let delta = try XCTUnwrap(PrivateType.commentDelta(from: nil, to: "我的备注"))
        XCTAssertEqual(Array(delta.keys), ["comment"])
        let meta = MsgSetMeta<TheCard, PrivateType>(desc: MetaSetDesc(pub: nil, priv: delta))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(meta)) as? [String: Any])
        let desc = try XCTUnwrap(payload["desc"] as? [String: Any])
        let priv = try XCTUnwrap(desc["private"] as? [String: String])
        XCTAssertEqual(priv, ["comment": "我的备注"])
        XCTAssertNil(desc["public"])
        XCTAssertNil(payload["tags"])
    }

    func testPrivateCommentACKMergePreservesOtherKeysPublicAndTags() throws {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        let topic = DefaultComTopic(tinode: sdk, name: "grpNote")
        topic.priv = ["comment": .string("旧备注"), "arch": .bool(true), "custom": .string("keep")]
        let delta = try XCTUnwrap(PrivateType.commentDelta(from: topic.comment, to: "新备注"))
        XCTAssertEqual(Array(delta.keys), ["comment"])
        let meta = MsgSetMeta<TheCard, PrivateType>(
            desc: MetaSetDesc(pub: TheCard(fn: "群名称"), priv: delta), tags: ["alias:group_note"])
        let ack = MsgServerCtrl(id: "synthetic", topic: topic.name, code: 200, text: "ok", ts: Date(), params: nil)
        topic.update(ctrl: ack, meta: meta)
        XCTAssertEqual(topic.comment, "新备注")
        XCTAssertEqual(topic.priv?["arch"]?.asBool(), true)
        XCTAssertEqual(topic.priv?["custom"]?.asString(), "keep")
        XCTAssertEqual(topic.pub?.fn, "群名称")
        XCTAssertEqual(topic.tags, ["alias:group_note"])
    }

    func testPrivateCommentClearUsesNullSentinelAndACKReadsEmpty() throws {
        let sdk = Tinode(for: "fixture", authenticateWith: "fixture")
        let topic = DefaultComTopic(tinode: sdk, name: "grpNote")
        topic.priv = ["comment": .string("旧备注"), "arch": .bool(true)]
        let delta = try XCTUnwrap(PrivateType.commentDelta(from: topic.comment, to: ""))
        XCTAssertEqual(delta["comment"]?.asString(), Tinode.kNullValue)
        let meta = MsgSetMeta<TheCard, PrivateType>(desc: MetaSetDesc(pub: nil, priv: delta))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(meta)) as? [String: Any])
        let desc = try XCTUnwrap(payload["desc"] as? [String: Any])
        XCTAssertEqual((desc["private"] as? [String: String])?["comment"], Tinode.kNullValue)
        topic.update(ctrl: MsgServerCtrl(id: "synthetic", topic: topic.name, code: 200,
            text: "ok", ts: Date(), params: nil), meta: meta)
        XCTAssertNil(topic.comment)
        XCTAssertEqual(topic.priv?["arch"]?.asBool(), true)
        XCTAssertNil(PrivateType.commentDelta(from: topic.comment, to: ""))
    }

    func testPrivateCommentNoChangeProducesNoPatchAndPreservesTextBytes() {
        XCTAssertNil(PrivateType.commentDelta(from: nil, to: nil))
        XCTAssertNil(PrivateType.commentDelta(from: nil, to: ""))
        XCTAssertNil(PrivateType.commentDelta(from: "", to: ""))
        XCTAssertNil(PrivateType.commentDelta(from: Tinode.kNullValue, to: ""))
        XCTAssertNil(PrivateType.commentDelta(from: "保留", to: "保留"))
        XCTAssertEqual(PrivateType.commentDelta(from: nil, to: "  原文  ")?.comment, "  原文  ")
    }

    private func validPushConfiguration() -> [String: Any] {
        [
            "API_KEY": "test-api-key",
            "BUNDLE_ID": "app.veilping.clawoschat",
            "GCM_SENDER_ID": "123456789012",
            "GOOGLE_APP_ID": "1:123456789012:ios:abcdef123456",
            "PROJECT_ID": "claw-os-production",
            "IS_GCM_ENABLED": true
        ]
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

// Only local persistence effects are observed; Tinode session and completion logic are production.
private final class AccountDeletionStoreSpy: Storage {
    var initializationError: String? { nil }
    var myUid: String? = "usrDeleteA"
    var deviceToken: String?
    var isReady: Bool { false }
    var deleted = [String]()
    var logoutCalls = 0
    func logout() { logoutCalls += 1; myUid = nil }
    func deleteAccount(_ uid: String) { deleted.append(uid) }
    func setMyUid(uid: String, credMethods: [String]?) { fatalError("Unexpected persistence operation in deletion fixture") }
    func setTimeAdjustment(adjustment: TimeInterval) { fatalError("Unexpected persistence operation in deletion fixture") }
    func topicGetAll(from tinode: Tinode?) -> [TopicProto]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func topicGet(from tinode: Tinode?, withName name: String?) -> TopicProto? { fatalError("Unexpected persistence operation in deletion fixture") }
    func topicAdd(topic: TopicProto) -> Int64 { fatalError("Unexpected persistence operation in deletion fixture") }
    func topicUpdate(topic: TopicProto) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func topicDelete(topic: TopicProto, hard: Bool) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func setRead(topic: TopicProto, read: Int) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func setRecv(topic: TopicProto, recv: Int) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func subAdd(topic: TopicProto, sub: SubscriptionProto) -> Int64 { fatalError("Unexpected persistence operation in deletion fixture") }
    func subUpdate(topic: TopicProto, sub: SubscriptionProto) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func subNew(topic: TopicProto, sub: SubscriptionProto) -> Int64 { fatalError("Unexpected persistence operation in deletion fixture") }
    func subDelete(topic: TopicProto, sub: SubscriptionProto) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func getSubscriptions(topic: TopicProto) -> [SubscriptionProto]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func userGet(uid: String) -> UserProto? { fatalError("Unexpected persistence operation in deletion fixture") }
    func userAdd(user: UserProto) -> Int64 { fatalError("Unexpected persistence operation in deletion fixture") }
    func userUpdate(user: UserProto) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgReceived(topic: TopicProto, sub: SubscriptionProto?, msg: MsgServerData?) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgSend(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDraft(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDraftUpdate(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgReady(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgSyncing(topic: TopicProto, dbMessageId: Int64, sync: Bool) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgClaim(topic: TopicProto, message: Message) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgFailed(topic: TopicProto, dbMessageId: Int64) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgRejected(topic: TopicProto, dbMessageId: Int64) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDiscardDraft(topic: TopicProto, dbMessageId: Int64) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgUnconfirmed(topic: TopicProto, dbMessageId: Int64) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgPruneFailed(topic: TopicProto) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDiscard(topic: TopicProto, dbMessageId: Int64) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDiscard(topic: TopicProto, seqId: Int) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDelivered(topic: TopicProto, dbMessageId: Int64, timestamp: Date, seq: Int) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgMarkToDelete(topic: TopicProto, from idLo: Int, to idHi: Int, markAsHard: Bool) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgMarkToDelete(topic: TopicProto, ranges: [MsgRange]?, markAsHard: Bool) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDelete(topic: TopicProto, delete id: Int, deleteFrom idLo: Int, deleteTo idHi: Int) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgDelete(topic: TopicProto, delete id: Int, deleteAllIn ranges: [MsgRange]?) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgRecvByRemote(sub: SubscriptionProto, recv: Int?) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgReadByRemote(sub: SubscriptionProto, read: Int?) -> Bool { fatalError("Unexpected persistence operation in deletion fixture") }
    func getCachedMessagesRange(topic: TopicProto) -> MsgRange? { fatalError("Unexpected persistence operation in deletion fixture") }
    func msgIsCached(topic: TopicProto, ranges: [MsgRange]) -> [MsgRange] { fatalError("Unexpected persistence operation in deletion fixture") }
    func getMissingRanges(topic: TopicProto, startFrom: Int, pageSize: Int, newer: Bool) -> [MsgRange] { fatalError("Unexpected persistence operation in deletion fixture") }
    func getMessageById(dbMessageId: Int64) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getMessagePreviewById(dbMessageId: Int64) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getQueuedMessages(topic: TopicProto) -> [Message]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getQueuedMessageDeletes(topic: TopicProto, hard: Bool) -> [MsgRange]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getLatestMessagePreviews() -> [Message]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getMessagePage(topic: TopicProto, from: Int, limit: Int, forward: Bool) -> [Message]? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getMessage(fromTopic topic: TopicProto, byEffectiveSeqId seqId: Int) -> Message? { fatalError("Unexpected persistence operation in deletion fixture") }
    func getAllMsgVersions(fromTopic topic: TopicProto, forSeq seqId: Int, limit: Int?) -> [Int]? { fatalError("Unexpected persistence operation in deletion fixture") }
}
