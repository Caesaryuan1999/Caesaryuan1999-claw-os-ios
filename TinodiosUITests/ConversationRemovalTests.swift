import XCTest
import Foundation

// Runs the same production ticket compiled from TopicSecurityViewController.swift.
// UIKit/SDK network delivery and actual server permissions still need separate acceptance.
final class ConversationRemovalTests: XCTestCase {
    private func dispatch(_ permit: ClawConversationRemovalPermit, actor: NSObject?, topic: NSObject?,
                          kind: ClawConversationRemovalPermit.Kind, owner: Bool) -> [ClawConversationRemovalPermit.Route] {
        var routes: [ClawConversationRemovalPermit.Route] = []
        let allowed = permit.perform(currentActor: actor, currentTopic: topic, kind: kind, isOwner: owner) { routes.append($0) }
        XCTAssertEqual(allowed, !routes.isEmpty)
        return routes
    }
    func testP2PDeleteTicketRoutesOnlyP2P() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .removeConversation, actor: actor, topic: topic)
        XCTAssertEqual(dispatch(permit, actor: actor, topic: topic, kind: .p2p, owner: false), [.deleteTopic])
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: true).isEmpty)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .saved, owner: true).isEmpty)
    }
    func testOldAccountConfirmationCannotDispatchInNewAccount() {
        let actor = NSObject(), other = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .removeConversation, actor: actor, topic: topic)
        XCTAssertTrue(dispatch(permit, actor: other, topic: topic, kind: .p2p, owner: false).isEmpty)
        XCTAssertTrue(dispatch(permit, actor: nil, topic: topic, kind: .p2p, owner: false).isEmpty)
    }
    func testReplacementTopicObjectDoesNotReuseOldConfirmation() {
        let actor = NSObject(), topic = NSObject(), replacement = NSObject()
        let permit = ClawConversationRemovalPermit(action: .removeConversation, actor: actor, topic: topic)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: replacement, kind: .p2p, owner: false).isEmpty)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: nil, kind: .p2p, owner: false).isEmpty)
    }
    func testMemberExitUsesExplicitUnsubscribeNotDeleteTopic() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .leaveGroup, actor: actor, topic: topic)
        XCTAssertEqual(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: false), [.leaveUnsubscribe])
    }
    func testPromotedOwnerCannotReuseMemberExitConfirmation() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .leaveGroup, actor: actor, topic: topic)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: true).isEmpty)
    }
    func testDissolveRequiresActualOwnerAndRejectsAdminWithoutOwnership() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .dissolveGroup, actor: actor, topic: topic)
        // Admin/manager privileges do not provide isOwner.
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: false).isEmpty)
        XCTAssertEqual(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: true), [.deleteTopic])
    }
    func testTransferredOwnerCannotReuseDissolveConfirmation() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .dissolveGroup, actor: actor, topic: topic)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: false).isEmpty)
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .p2p, owner: true).isEmpty)
    }
    func testSavedMessagesConfirmationCannotDissolveGroup() {
        let actor = NSObject(), topic = NSObject()
        let permit = ClawConversationRemovalPermit(action: .deleteSavedMessages, actor: actor, topic: topic)
        XCTAssertEqual(dispatch(permit, actor: actor, topic: topic, kind: .saved, owner: true), [.deleteTopic])
        XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .group, owner: true).isEmpty)
    }
    func testUnknownTopicKindDoesNotDispatchAnyDestructiveAction() {
        let actor = NSObject(), topic = NSObject()
        let actions: [ClawConversationRemovalPermit.Action] = [.removeConversation, .leaveGroup, .dissolveGroup, .deleteSavedMessages]
        for action in actions {
            let permit = ClawConversationRemovalPermit(action: action, actor: actor, topic: topic)
            XCTAssertTrue(dispatch(permit, actor: actor, topic: topic, kind: .other, owner: true).isEmpty)
        }
    }
}

