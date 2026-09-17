import XCTest
import Foundation
import TinodeSDK

// Compile the actual AccountNames and ClawPublicDirectoryLookup production
// definitions from Utils.swift. The mutation closures below observe acceptance.
final class PublicDirectoryTests: XCTestCase {
    private func subscription(uid: String = "usrReturned", tags: [String]) throws -> FndSubscription {
        let json = try JSONSerialization.data(withJSONObject: ["user": uid, "private": tags])
        return try JSONDecoder().decode(FndSubscription.self, from: json)
    }

    func testUIDShapedPublicAliasUsesOnlyExactAliasTerm() {
        XCTAssertEqual(AccountNames.directorySearchQuery(" @UsrPublished_7 "), "alias:usrpublished_7")
        XCTAssertTrue(AccountNames.matchesPublicSearchName(tags: ["alias:usrpublished_7"], query: "UsrPublished_7"))
        XCTAssertFalse(AccountNames.matchesPublicSearchName(tags: ["basic:usrpublished_7", "usrpublished_7"], query: "UsrPublished_7"))
    }

    func testNormalNameKeepsPublicAliasAndLegacyBasicWithoutRawTerm() {
        XCTAssertEqual(AccountNames.directorySearchQuery("Alice"), "alias:alice,basic:alice")
        XCTAssertEqual(AccountNames.directorySearchQuery("claw_123"), "alias:claw_123")
        XCTAssertEqual(AccountNames.directorySearchQuery("abc"), "basic:abc")
        XCTAssertTrue(AccountNames.matchesPublicSearchName(tags: ["basic:alice"], query: "alice"))
        XCTAssertFalse(AccountNames.matchesPublicSearchName(tags: ["alice", "alias:alice2"], query: "alice"))
    }

    func testLegacyBasicAndAliasLengthsMatchPublicDirectoryContract() {
        for length in [1, 2, 3, 24, 25, 32, 33] {
            let value = String(repeating: "a", count: length)
            var terms: [String] = []
            if (4...24).contains(length) { terms.append("alias:" + value) }
            if (2...32).contains(length) { terms.append("basic:" + value) }
            XCTAssertEqual(AccountNames.directorySearchQuery(value), terms.isEmpty ? nil : terms.joined(separator: ","), "length=\(length)")
        }
        XCTAssertNil(AccountNames.directorySearchQuery("usr"))
        XCTAssertEqual(AccountNames.directorySearchQuery("usrx"), "alias:usrx")
        XCTAssertNil(AccountNames.directorySearchQuery("usr" + String(repeating: "a", count: 22)))
    }

    func testAdvancedExpressionsAndPrivateIdentitySyntaxCannotPassThrough() {
        for value in ["alice bob", "alice,bob", "alias:alice", "basic:alice", "a@example.com",
                      "+8613800138000", "alice\nbob", "@ alice", "用户abcd", "alice|bob"] {
            XCTAssertNil(AccountNames.directorySearchQuery(value), value)
        }
    }

    func testAliasDisplayIsAuthoritativeButNeverInventedFromUID() {
        XCTAssertEqual(AccountNames.fromTags(["alias:usrpublished_7"]), "usrpublished_7")
        XCTAssertNil(AccountNames.fromTags(["tel:+8613800138000", "email:a@example.com"]))
        XCTAssertEqual(AccountNames.contactDisplayName(displayName: nil, accountName: nil, userId: "usrPrivate"), "CLAW OS")
    }

    func testConsumerUsesServerReturnedUIDInsteadOfManualInput() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "usrpublished_7", owner: owner))
        let sub = try subscription(uid: "usrDifferentReturned", tags: ["alias:usrpublished_7"])
        var saved: [String] = []
        XCTAssertTrue(lookup.consume(ticket, owner: owner, input: "usrpublished_7", subscription: sub) { saved.append($0) })
        XCTAssertEqual(saved, ["usrDifferentReturned"])
    }

    func testUIDLookingResultWithoutExactAliasCannotBeConsumed() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "usrpublished_7", owner: owner))
        for tags in [["basic:usrpublished_7"], ["usrpublished_7"], ["alias:other_public"], []] {
            let sub = try subscription(tags: tags)
            XCTAssertFalse(lookup.consume(ticket, owner: owner, input: ticket.input, subscription: sub) { _ in XCTFail("Unproven result saved") })
        }
    }

    func testNonUserDirectoryResultCannotBeConsumed() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let sub = try subscription(uid: "grpOther", tags: ["alias:alice"])
        XCTAssertFalse(lookup.consume(ticket, owner: owner, input: "alice", subscription: sub) { _ in XCTFail("Group accepted") })
    }

    func testTypingNewInputRejectsVisibleOldSelectionBeforeDebounce() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let sub = try subscription(tags: ["alias:alice"])
        XCTAssertFalse(lookup.consume(ticket, owner: owner, input: "bob", subscription: sub) { _ in XCTFail("Old selection consumed") })
        lookup.invalidate()
        XCTAssertFalse(lookup.consume(ticket, owner: owner, input: "alice", subscription: sub) { _ in XCTFail("Invalidated response consumed") })
    }

    func testSameTextNewRequestRejectsOlderResponseAndClick() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let old = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let latest = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let sub = try subscription(tags: ["alias:alice"])
        XCTAssertFalse(lookup.consume(old, owner: owner, input: "alice", subscription: sub) { _ in XCTFail("Old request consumed") })
        XCTAssertTrue(lookup.consume(latest, owner: owner, input: "alice", subscription: sub) { _ in })
    }

    func testChangedSDKOwnerRejectsResponseAndSelection() throws {
        let owner = NSObject(), other = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let sub = try subscription(tags: ["alias:alice"])
        XCTAssertFalse(lookup.consume(ticket, owner: other, input: "alice", subscription: sub) { _ in XCTFail("Cross-owner result saved") })
    }

    func testInvalidNewQueryRetiresPreviousValidRequest() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        XCTAssertNil(lookup.begin(input: "alias:alice", owner: owner))
        let sub = try subscription(tags: ["alias:alice"])
        XCTAssertFalse(lookup.consume(ticket, owner: owner, input: "alice", subscription: sub) { _ in XCTFail("Retired request saved") })
    }

    func testConsumerActionRunsOutsideInternalLock() throws {
        let owner = NSObject(), lookup = ClawPublicDirectoryLookup()
        let ticket = try XCTUnwrap(lookup.begin(input: "alice", owner: owner))
        let sub = try subscription(tags: ["alias:alice"])
        XCTAssertTrue(lookup.consume(ticket, owner: owner, input: "alice", subscription: sub) { _ in lookup.invalidate() })
        XCTAssertFalse(lookup.isCurrent(ticket, owner: owner, input: "alice"))
    }
}
