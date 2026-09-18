"""SQLite fault evidence mirroring the existing source call order; not Swift execution."""
from pathlib import Path
import json
import sqlite3

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "Scripts/ci/fixtures/ios113.sql"
TABLES = ("messages", "subscriptions", "topics", "users", "accounts")

def snapshot(db):
    return {table: db.execute("SELECT * FROM " + table + " ORDER BY id").fetchall() for table in TABLES}

def existing_delete_call_order(db):
    db.execute("SAVEPOINT fixture_delete")
    swallowed = []
    try:
        try:
            db.execute("DELETE FROM messages WHERE topic_id IN (SELECT id FROM topics WHERE account_id=?)", (1,))
            db.execute("DELETE FROM subscriptions WHERE topic_id IN (SELECT id FROM topics WHERE account_id=?)", (1,))
            db.execute("DELETE FROM topics WHERE account_id=?", (1,))
        except sqlite3.Error:
            swallowed.append("topicDeleteAllFalse")
        try:
            db.execute("DELETE FROM users WHERE account_id=?", (1,))
        except sqlite3.Error:
            swallowed.append("userDeleteFalse")
        try:
            db.execute("DELETE FROM accounts WHERE id=?", (1,))
        except sqlite3.Error:
            swallowed.append("accountDeleteFalse")
        db.execute("RELEASE fixture_delete")
        return True, swallowed
    except sqlite3.Error:
        db.execute("ROLLBACK TO fixture_delete")
        db.execute("RELEASE fixture_delete")
        return False, swallowed

def main():
    results = []
    for failure in ("subscriptions", "users", "accounts"):
        db = sqlite3.connect(":memory:", isolation_level=None)
        db.execute("PRAGMA foreign_keys=ON")
        db.executescript(FIXTURE.read_text(encoding="utf-8"))
        before = snapshot(db)
        db.execute("CREATE TRIGGER fixture_abort BEFORE DELETE ON " + failure +
                   " WHEN OLD.id=1 BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
        reported, swallowed = existing_delete_call_order(db)
        after = snapshot(db)
        assert reported and swallowed and before != after
        assert db.execute("SELECT COUNT(*) FROM accounts WHERE id=1").fetchone()[0] == 1
        assert db.execute("SELECT COUNT(*) FROM messages WHERE topic_id=2").fetchone()[0] == 1
        results.append({"fault_table":failure, "existing_reports_success":reported,
                        "partial_commit":before != after, "captured_account_remains":True,
                        "other_account_message_preserved":True, "swallowed_stages":swallowed})
        db.close()
    report = {"evidence_level":"real SQLite with source call-order adapter, NOT Swift BaseDb execution",
              "sqlite_version":sqlite3.sqlite_version, "cases":results}
    (Path(__file__).parent / "sqlite-red.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report))
if __name__ == "__main__":
    main()
