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
