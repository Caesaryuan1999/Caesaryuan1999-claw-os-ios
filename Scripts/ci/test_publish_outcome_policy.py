#!/usr/bin/env python3
"""Windows source-policy guard, NOT Swift, WebSocket or device execution."""
from pathlib import Path
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(name):
    return (ROOT / name).read_text(encoding="utf-8")


class PublishOutcomeSourcePolicy(unittest.TestCase):
    def test_unknown_is_persisted_and_never_selected_for_automatic_replay(self):
        statuses = source("TinodiosDB/BaseDb.swift")
        self.assertIn("case unconfirmed = 35", statuses)
        messages = source("TinodiosDB/MessageDb.swift")
        self.assertIn("self.status == BaseDb.Status.queued.rawValue", messages)
        self.assertIn("recoverInterruptedPublishes", messages)
        self.assertIn("UPDATE messages SET status=35 WHERE status=30", messages)
        self.assertIn("UPDATE messages SET status=36 WHERE status=31", messages)
        # SQLite fixture verifies the selection rule for persisted states.
        # It deliberately does not claim to execute SQLite.swift.
        db = sqlite3.connect(":memory:")
        db.execute("CREATE TABLE messages (id INTEGER PRIMARY KEY, status INTEGER)")
        db.executemany("INSERT INTO messages VALUES (?, ?)", [(1, 20), (2, 30), (3, 35), (4, 40), (5, 50)])
        db.execute("UPDATE messages SET status=35 WHERE status=30")
        self.assertEqual(db.execute("SELECT id FROM messages WHERE status=20").fetchall(), [(1,)])
        self.assertEqual(db.execute("SELECT id FROM messages WHERE status=35 ORDER BY id").fetchall(), [(2,), (3,)])

    def test_publish_claims_a_durable_slot_before_transport(self):
        topic = source("TinodeSDK/Topic.swift")
        publish = topic.split("private func publishInternal", 1)[1].split("/// Publish content", 1)[0]
        claim = publish.find("msgClaim(")
        transport = publish.find(".publish(")
        self.assertTrue(0 <= claim < transport, "Publish must claim queued storage before handing content to transport")
        self.assertIn("PublishFailureDisposition.forError", publish)
        self.assertIn("msgUnconfirmed", publish)
        messages = source("TinodiosDB/MessageDb.swift")
        self.assertIn("status == from.rawValue", messages)
        self.assertIn("MessageDb.claimC3", source("TinodiosDB/SqlStore.swift"))
        self.assertIn("AND status=? AND head=?", messages)
        self.assertIn("expectedStatus == .queued || expectedStatus == .unconfirmedC3", messages)
        self.assertIn("supportsDurablePublish", publish[:claim])

    def test_transport_interruptions_are_distinct_from_pre_send_offline(self):
        tinode = source("TinodeSDK/Tinode.swift")
        expiry = tinode.split("@objc private func expireFutures", 1)[1].split("subscript(key:", 1)[0]
        disconnect = tinode.split("private func handleDisconnect", 1)[1].split("public class TinodeConnectionListener", 1)[0]
        self.assertIn("requestOutcomeUnknown", expiry)
        self.assertIn("requestOutcomeUnknown", disconnect)
        send = tinode.split("private func sendWithPromise", 1)[1].split("private func hello", 1)[0]
        self.assertLess(send.index("futures[id] = future"), send.index("try send(payload: msg)"))

    def test_failure_receipts_require_actual_server_confirmation(self):
        ui = source("Tinodios/UiUtils.swift").split("func deliveryMarkerIcon", 1)[1].split("// Returns a shortened", 1)[0]
        self.assertIn("message.isUnconfirmed", ui)
        self.assertIn("message.isFailed", ui)
        self.assertIn("!message.isSynced", ui)
        self.assertIn("消息可能已发送，请先查看最新聊天记录。", source("Tinodios/MessageInteractor.swift"))
        self.assertNotIn("self.interactor?.deleteFailedMessages()", source("Tinodios/MessageViewController.swift"))

    def test_automatic_sync_has_no_preclaim_that_bypasses_the_publish_guard(self):
        topic = source("TinodeSDK/Topic.swift")
        sync = topic.split("public func syncOne", 1)[1].split("public func setSeqAndFetch", 1)[0]
        self.assertNotIn("msgSyncing", sync)
        publish = topic.split("public func publish(content:", 1)[1].split("private func sendPendingDeletes", 1)[0]
        self.assertIn("requestNotSent", publish)
        self.assertLess(publish.find(".thenCatch"), publish.find(".thenApply"))
        self.assertNotIn("msgSyncing", publish, "An outer subscribe catch must not requeue a dispatched publish failure")

    def test_unknown_edits_cannot_delete_server_history_or_be_downgraded(self):
        delete = source("Tinodios/MessageInteractor.swift").split("func deleteMessage(_ message:", 1)[1].split("private func commitLocalDeletes", 1)[0]
        self.assertIn("message.isUnconfirmed", delete)
        self.assertIn("if message.isSynced, let replSeq", delete)
        self.assertLess(delete.index("message.isUnconfirmed"), delete.index("getAllMsgVersions"))
        failed = source("TinodiosDB/SqlStore.swift").split("public func msgFailed", 1)[1].split("public func msgPruneFailed", 1)[0]
        self.assertIn("markPendingFailed", failed)
        self.assertNotIn("updateStatusAndContent", failed)


if __name__ == "__main__":
    unittest.main()
