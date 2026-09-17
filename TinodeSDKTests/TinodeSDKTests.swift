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
