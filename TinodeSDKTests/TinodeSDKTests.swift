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
            TinodeError.requestNotSent("draft could not be saved")), .failed)
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
