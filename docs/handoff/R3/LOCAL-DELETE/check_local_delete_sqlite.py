"""Execute extracted production deletion SQL in actual SQLite; not Swift execution."""
from pathlib import Path
import json
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[4]
source = (ROOT / "TinodiosDB/BaseDb.swift").read_text(encoding="utf-8")
body = source[source.index("public func deleteUid("):source.index("public static func updateCounter")]
statements = re.findall(r'try database.run\("([^"]+)"', body)
assert len(statements) == 5
assert "database.changes == 1" in body
TABLES = ("accounts", "users", "topics", "subscriptions", "messages")
def snapshot(db):
    return {t: db.execute("SELECT * FROM " + t + " ORDER BY id").fetchall() for t in TABLES}
def cleanup(db):
    try:
        db.execute("BEGIN IMMEDIATE")
        row = db.execute("SELECT id FROM accounts WHERE uid=?", ("usrFixtureA",)).fetchone()
        if row:
            for statement in statements:
                args = (row[0], "usrFixtureA") if statement.count("?") == 2 else (row[0],)
                db.execute(statement, args)
            if db.execute("SELECT changes()").fetchone()[0] != 1:
                raise RuntimeError("incomplete")
        db.execute("COMMIT")
        return True
    except (sqlite3.Error, RuntimeError):
        if db.in_transaction:
            db.execute("ROLLBACK")
        return False
results = []
for kind in ["abort-" + t for t in TABLES] + ["commit", "ignore", "success", "empty", "repeat", "cross-account-fk"]:
    db = sqlite3.connect(":memory:", isolation_level=None)
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript((ROOT / "Scripts/ci/fixtures/ios113.sql").read_text(encoding="utf-8"))
    if kind == "cross-account-fk":
        db.execute("UPDATE messages SET user_id=1 WHERE id=7")
    if kind == "empty":
        for sql in statements[:-1]:
            db.execute(sql, (1,))
    before = snapshot(db)
    if kind.startswith("abort-"):
        table = kind[len("abort-"):]
        db.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON " + table +
                   " WHEN OLD.id=1 BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
    if kind == "ignore":
        db.execute("CREATE TRIGGER ignore_delete BEFORE DELETE ON accounts WHEN OLD.id=1 BEGIN SELECT RAISE(IGNORE); END")
    if kind == "commit":
        db.set_authorizer(lambda action, first, *_:
            sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_TRANSACTION and first == "COMMIT" else sqlite3.SQLITE_OK)
    actual = cleanup(db)
    db.set_authorizer(None)
    expected = kind in ("success", "empty", "repeat")
    assert actual == expected, kind
    if not actual:
        assert snapshot(db) == before, kind
    else:
        assert db.execute("SELECT COUNT(*) FROM accounts WHERE id=1").fetchone()[0] == 0
        if kind == "repeat":
            assert cleanup(db)
    assert db.execute("SELECT COUNT(*) FROM accounts WHERE id=2").fetchone()[0] == 1
    assert db.execute("SELECT COUNT(*) FROM messages WHERE id=7").fetchone()[0] == 1
    results.append({"case":kind, "pass":True, "cleanup":actual, "rollback_or_success_as_expected":True})
    db.close()
report = {"level":"actual SQLite, extracted production SQL/control adapter; NOT Swift",
          "sqlite":sqlite3.sqlite_version, "cases":results}
(Path(__file__).parent / "sqlite-green.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print("LOCAL-DELETE SQLite",len(results),"cases PASS")
