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
