#!/usr/bin/env python3
"""C3 production SQL on real synthetic SQLite. Python bridge, NOT Swift execution."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import uuid
from test_local_migration_sqlite import fixture, constant, schema_sql, connect

ROOT = Path(__file__).resolve().parents[2]
KEY = "abcdefab-1111-4111-8111-abcdefabcdef"
HEADER_TYPE = "Dictionary<String, JSONValue>"

def stored_headers(key):
    # Model Tinode.serializeObject's type prefix; the XCTest uses the Swift
    # serializer itself. This bridge remains SQL evidence, not Swift execution.
    return HEADER_TYPE + ";" + json.dumps({"clientmsgid": key})

def run(source, message_source):
    results = []
    def check(name, body):
        try:
            body()
            results.append({"name": name, "passed": True})
        except Exception as error:
            results.append({"name": name, "passed": False, "error": str(error)})
    def prepare(db, fail=False):
        db.execute("BEGIN IMMEDIATE")
        try:
            db.execute(constant(source, "migrationCreateSQL"))
            for prefix in ("migration", "c3Migration"):
                if prefix + "ReadSQL" not in source:
                    continue
                if db.execute(constant(source, prefix + "ReadSQL")).fetchone() is None:
                    db.execute(constant(source, prefix + "QuarantineSQL"))
                    db.execute(constant(source, prefix + "WriteSQL"))
            if fail:
                db.set_authorizer(lambda action,a,b,c,d: sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_TRANSACTION and a == "COMMIT" else sqlite3.SQLITE_OK)
            db.execute("COMMIT")
        except Exception:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise
    def claim(db, msg=2, topic=1, account=1, sender="usrFixtureA", capable=True, expected_status=None):
        if not capable:
            return False
        db.execute("BEGIN IMMEDIATE")
        try:
            row = db.execute("SELECT head,status FROM messages WHERE id=?", (msg,)).fetchone()
            expected_status = row[1] if expected_status is None else expected_status
            if expected_status not in (20,36):
                db.execute("COMMIT")
                return False
            tag, separator, payload = (row[0] or "").partition(";")
            if separator != ";" or tag != HEADER_TYPE:
                db.execute("COMMIT")
                return False
            key = json.loads(payload).get("clientmsgid")
            if not isinstance(key,str) or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", key):
                db.execute("COMMIT")
                return False
            changed = db.execute(constant(message_source, "claimC3SQL"),
                (msg,topic,sender,expected_status,row[0],account,sender,account,sender)).rowcount
            db.execute("COMMIT")
            return changed == 1
        except Exception:
            if db.in_transaction: db.execute("ROLLBACK")
            raise
    with tempfile.TemporaryDirectory(prefix="claw-ios-c3-") as folder:
        path = Path(folder) / "fixture.sqlite"
        fixture(path)
        with connect(path, isolation_level=None) as db:
            def boundary():
                db.execute(constant(source, "migrationCreateSQL"))
                db.execute(constant(source, "migrationWriteSQL"))
                db.execute("UPDATE messages SET head=? WHERE id IN (2,3,4,5)", (stored_headers(KEY),))
                db.execute("UPDATE messages SET status=31 WHERE id=4")
                db.execute("UPDATE messages SET status=36 WHERE id=5")
                before=db.execute("SELECT id,head,content FROM messages ORDER BY id").fetchall()
                prepare(db)
                assert db.execute("SELECT count(*) FROM messages WHERE id IN (2,3,4,5) AND status=35").fetchone()[0] == 4
                assert db.execute("SELECT count(*) FROM claw_local_migrations").fetchone()[0] == 2
                assert before == db.execute("SELECT id,head,content FROM messages ORDER BY id").fetchall()
            check("legacy-key-and-unmarked31-36-quarantined-with-payload-preserved", boundary)
            def repeat():
                db.execute("UPDATE messages SET status=20 WHERE id=2")
                db.execute("UPDATE messages SET status=31 WHERE id=3")
                prepare(db)
                assert db.execute("SELECT status FROM messages WHERE id IN (2,3) ORDER BY id").fetchall() == [(20,),(31,)]
            check("repeat-NSE-open-does-not-recover-live31", repeat)
            def recovery():
                db.execute("UPDATE messages SET status=30 WHERE id=4")
                db.execute("UPDATE messages SET status=35 WHERE id=5")
                db.execute("UPDATE messages SET status=35 WHERE status=30")
                db.execute(constant(message_source,"recoverC3SQL"))
                assert db.execute("SELECT status FROM messages WHERE id IN (3,4,5) ORDER BY id").fetchall() == [(36,),(35,),(35,)]
            check("main-recovery-distinguishes-C3-from-legacy", recovery)
            def no_cap():
                db.execute("UPDATE messages SET status=20 WHERE id=2")
                assert not claim(db, capable=False)
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone()[0] == 20
            check("no-capability-keeps-new-message-queued-bridge", no_cap)
            def scoped():
                assert not claim(db,topic=2)
                assert not claim(db,account=2,sender="usrFixtureB")
                assert claim(db)
                assert not claim(db)
            check("claim-checks-account-topic-sender-and-CAS", scoped)
            def stale_snapshot():
                db.execute("UPDATE messages SET status=20 WHERE id=2")
                assert claim(db, expected_status=20)
                db.execute("UPDATE messages SET status=36 WHERE id=2")
                assert not claim(db, expected_status=20)
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone()[0] == 36
                assert claim(db, expected_status=36)
            check("stale20-snapshot-cannot-claim-actual36", stale_snapshot)
            def unknown():
                db.execute("UPDATE messages SET status=35 WHERE id=2")
                assert not claim(db)
                db.execute("UPDATE messages SET status=36 WHERE id=2")
                before=db.execute("SELECT head,content FROM messages WHERE id=2").fetchone()
                assert claim(db)
                assert before == db.execute("SELECT head,content FROM messages WHERE id=2").fetchone()
            check("legacy35-denied-C3-36-retries-original-payload", unknown)
            def invalid_key():
                for value in ["old",KEY.upper(),None,str(uuid.uuid1())]:
                    db.execute("UPDATE messages SET status=20,head=? WHERE id=2",(stored_headers(value),))
                    assert not claim(db)
                db.execute("UPDATE messages SET head=? WHERE id=2",(stored_headers(KEY),))
            check("invalid-or-non-v4-key-does-not-claim-bridge", invalid_key)
            def wire_json_is_not_storage():
                db.execute("UPDATE messages SET status=20,head=? WHERE id=2", (json.dumps({"clientmsgid":KEY}),))
                assert not claim(db)
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone()[0] == 20
                db.execute("UPDATE messages SET head=? WHERE id=2", (stored_headers(KEY),))
            check("wire-JSON-is-not-typed-storage-header-bridge", wire_json_is_not_storage)
        def concurrent():
            def attempt(_):
                with connect(path, timeout=5, isolation_level=None) as db:
                    return claim(db)
            with ThreadPoolExecutor(2) as executor:
                assert sum(executor.map(attempt,range(2))) == 1
        check("two-real-connections-only-one-C3-claim", concurrent)
        def rollback():
            other=Path(folder)/"rollback.sqlite";fixture(other)
            with connect(other,isolation_level=None) as db:
                before=db.execute("SELECT id,status,head,content FROM messages ORDER BY id").fetchall()
                try: prepare(db,fail=True)
                except sqlite3.DatabaseError: pass
                else: raise AssertionError("expected injected commit failure")
                assert before==db.execute("SELECT id,status,head,content FROM messages ORDER BY id").fetchall()
                assert not db.execute("SELECT name FROM sqlite_master WHERE name='claw_local_migrations'").fetchall()
        check("commit-denial-rolls-back-both-markers-and-statuses", rollback)
        def fresh():
            with connect(":memory:",isolation_level=None) as db:
                db.executescript(schema_sql(source));prepare(db)
                assert db.execute("SELECT rule FROM claw_local_migrations ORDER BY rule").fetchall()==[("C2-L1-20260918",),("C3-20260918",)]
        check("new-empty-store-has-both-boundaries", fresh)
    return {"level":"real SQLite with production SQL and Python UUID/capability bridge; not Swift",
            "tests":results,"passed":sum(r["passed"] for r in results),"total":len(results)}

if __name__ == "__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--baseline");parser.add_argument("--report")
    args=parser.parse_args()
    def read(name):
        if args.baseline: return subprocess.check_output(["git","show",args.baseline+":"+name],cwd=ROOT).decode("utf-8")
        return (ROOT/name).read_text(encoding="utf-8")
    result=run(read("TinodiosDB/BaseDb.swift"),read("TinodiosDB/MessageDb.swift"))
    if args.report: Path(args.report).write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps(result,indent=2))
    raise SystemExit(result["passed"] != result["total"])
