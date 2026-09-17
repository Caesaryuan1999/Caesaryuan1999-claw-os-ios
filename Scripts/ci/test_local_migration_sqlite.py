#!/usr/bin/env python3
"""Real SQLite with synthetic old-113 data and production SQL constants.

The Python bootstrap adapter is a portability harness, NOT execution of Swift.
Mac XCTest exercises BaseDb directly. Neither is a real user's upgrade result.
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "Scripts/ci/fixtures/ios113.sql"
TABLES = ("accounts", "users", "topics", "subscriptions", "messages")
RULE = "C2-L1-20260918"


@contextmanager
def connect(*args, **kwargs):
    db = sqlite3.connect(*args, **kwargs)
    try:
        with db:
            yield db
    finally:
        db.close()


def fixture(path):
    with connect(path) as db:
        db.executescript(FIXTURE.read_text(encoding="utf-8"))


def snapshot(db, statuses=True):
    result = {}
    for table in TABLES:
        columns = [r[1] for r in db.execute(f"PRAGMA table_info({table})")]
        assert columns, f"Existing table {table} was destroyed"
        if table == "messages" and not statuses:
            columns.remove("status")
        result[table] = db.execute(f"SELECT {','.join(columns)} FROM {table} ORDER BY id").fetchall()
    return result


def constant(source, name):
    match = re.search(r"static let " + name + r' = "([^"\n]+)"', source)
    assert match, f"Missing production SQL constant {name}"
    return match.group(1)


def schema_sql(source):
    match = re.search(r'static let schema113SQL = """\n(.*?)\n\s*"""', source, re.S)
    assert match, "Missing production fresh-schema SQL"
    return match.group(1)


def structural_check(db, source):
    objects = db.execute("SELECT name,type FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' AND type IN ('table','view','trigger')").fetchall()
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version == 0 and not objects:
        return True
    if version != 113:
        raise RuntimeError("unsupported-schema")
    tables = {name for name, kind in objects if kind == "table"}
    if any(kind != "table" for _, kind in objects) or not set(TABLES) <= tables or tables - set(TABLES) - {"claw_local_migrations"}:
        raise RuntimeError("unknown-structure")

    def columns(conn, table):
        return {row[1]: row[2:] for row in conn.execute(f'PRAGMA table_xinfo("{table}")')}

    def unique(conn, table):
        result = set()
        for _, name, is_unique, _, partial in conn.execute(f'PRAGMA index_list("{table}")'):
            if not is_unique:
                continue
            names = tuple(row[2] for row in conn.execute('PRAGMA index_info("' + name.replace('"','""') + '")'))
            if partial:
                sql = conn.execute("SELECT sql FROM sqlite_master WHERE name=?", (name,)).fetchone()[0]
                normalized = re.sub(r'[\s"()]', '', sql.lower())
                if not normalized.endswith("whereeffective_seqisnotnull"):
                    raise RuntimeError("wrong-partial-index")
            result.add((partial, names))
        return result

    with connect(":memory:") as expected:
        expected.executescript(schema_sql(source))
        for table in TABLES:
            if columns(db,table) != columns(expected,table):
                raise RuntimeError("wrong-columns:" + table)
            actual_fk = {row[2:] for row in db.execute(f'PRAGMA foreign_key_list("{table}")')}
            expected_fk = {row[2:] for row in expected.execute(f'PRAGMA foreign_key_list("{table}")')}
            if actual_fk != expected_fk or unique(db,table) != unique(expected,table):
                raise RuntimeError("wrong-relations:" + table)
        if "claw_local_migrations" in tables:
            expected.execute(constant(source,"migrationCreateSQL"))
            if columns(db,"claw_local_migrations") != columns(expected,"claw_local_migrations"):
                raise RuntimeError("wrong-marker-structure")
            rules = (RULE, "C3-20260918") if "c3MigrationReadSQL" in source else (RULE, RULE)
            if db.execute("SELECT count(*) FROM claw_local_migrations WHERE rule NOT IN (?,?) OR completed<>1",rules).fetchone()[0]:
                raise RuntimeError("wrong-marker-rule")
    if db.execute("PRAGMA foreign_key_check").fetchall():
        raise RuntimeError("broken-foreign-key-data")
    return False


def bootstrap(path, source, interrupt=False, reject_commit=False):
    with connect(path, timeout=5, isolation_level=None) as db:
        if RULE not in source:
            # Original BaseDb's actual rule: unequal version => drop all tables;
            # same-version outgoing rows are untouched. Only disposable fixtures.
            if db.execute("PRAGMA user_version").fetchone()[0] != 113:
                for table in reversed(TABLES):
                    db.execute(f"DROP TABLE {table}")
            return
        structural_check(db, source)
        db.execute("BEGIN IMMEDIATE")
        try:
            if structural_check(db, source):
                # execute(), not executescript(): the latter implicitly commits.
                for statement in schema_sql(source).split(";"):
                    if statement.strip():
                        db.execute(statement)
            db.execute(constant(source, "migrationCreateSQL"))
            done = db.execute(constant(source, "migrationReadSQL")).fetchone()
            if done is None:
                db.execute(constant(source, "migrationQuarantineSQL"))
                if interrupt:
                    raise RuntimeError("injected-before-marker")
                db.execute(constant(source, "migrationWriteSQL"))
            elif done != (1,):
                raise RuntimeError("invalid-marker")
            if "c3MigrationReadSQL" in source:
                done = db.execute(constant(source,"c3MigrationReadSQL")).fetchone()
                if done is None:
                    db.execute(constant(source,"c3MigrationQuarantineSQL"))
                    db.execute(constant(source,"c3MigrationWriteSQL"))
                elif done != (1,):
                    raise RuntimeError("invalid-c3-marker")
            if reject_commit:
                db.set_authorizer(lambda action,a,b,c,d: sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_TRANSACTION and a == "COMMIT" else sqlite3.SQLITE_OK)
            db.execute("COMMIT")
        except Exception:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise


def run(source):
    results = []
    with tempfile.TemporaryDirectory(prefix="claw-ios113-synthetic-") as folder:
        folder = Path(folder)

        def check(name, fn):
            path = folder / (name + ".sqlite")
            fixture(path)
            try:
                fn(path)
                results.append({"name": name, "status": "pass"})
            except Exception as error:
                results.append({"name": name, "status": "fail", "error": str(error)})

        def quarantine(path):
            bootstrap(path, source)
            with connect(path) as db:
                actual = dict(db.execute("SELECT id,status FROM messages"))
                assert actual == {1:10,2:35,3:35,4:35,5:40,6:50,7:35,8:35,9:80}, actual
                assert not db.execute("PRAGMA foreign_key_check").fetchall()
        check("old20and30-isolated-across-accounts", quarantine)

        def preserve(path):
            with connect(path) as db:
                before = snapshot(db, False)
            bootstrap(path, source)
            with connect(path) as db:
                assert before == snapshot(db, False), "body/head/attachment/account/link changed"
                assert db.execute("PRAGMA user_version").fetchone() == (113,)
        check("all-nonstatus-data-preserved", preserve)

        def repeated(path):
            bootstrap(path, source)
            with connect(path) as db:
                db.execute("UPDATE messages SET status=20 WHERE id=1")
                db.execute("UPDATE messages SET status=30 WHERE id=5")
            bootstrap(path, source)
            with connect(path) as db:
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone() == (35,)
                assert db.execute("SELECT status FROM messages WHERE id=1").fetchone() == (20,)
                # NSE bootstrap must not change a main-app publish already in flight.
                assert db.execute("SELECT status FROM messages WHERE id=5").fetchone() == (30,)
                assert db.execute("SELECT count(*) FROM claw_local_migrations").fetchone() == (2 if "c3MigrationReadSQL" in source else 1,)
        check("repeat-preserves-new20-and-active30", repeated)

        def interruption(path):
            with connect(path) as db:
                before = snapshot(db)
            try:
                bootstrap(path, source, interrupt=True)
            except RuntimeError:
                pass
            with connect(path) as db:
                assert snapshot(db) == before
                assert not db.execute("SELECT name FROM sqlite_master WHERE name='claw_local_migrations'").fetchall()
            bootstrap(path, source)
            with connect(path) as db:
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone() == (35,)
        check("interrupt-rolls-back-marker-and-status", interruption)

        def concurrent(path):
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(lambda _: bootstrap(path, source), range(2)))
            with connect(path) as db:
                assert db.execute("SELECT COUNT(*) FROM claw_local_migrations").fetchone() == (2 if "c3MigrationReadSQL" in source else 1,)
                assert db.execute("SELECT COUNT(*) FROM messages WHERE status=35").fetchone() == (5,)
        check("two-process-equivalent-sqlite-locks", concurrent)

        def unsupported(path, version):
            with connect(path) as db:
                db.execute(f"PRAGMA user_version={version}")
                before = snapshot(db)
            try:
                bootstrap(path, source)
            except RuntimeError:
                pass
            with connect(path) as db:
                assert snapshot(db) == before
                assert db.execute("PRAGMA user_version").fetchone() == (version,)
        check("unknown112-preserved", lambda p: unsupported(p,112))
        check("newer114-preserved", lambda p: unsupported(p,114))

        def wal_backup(path):
            live = sqlite3.connect(path)
            try:
                live.execute("PRAGMA journal_mode=WAL")
                live.execute("PRAGMA wal_autocheckpoint=0")
                live.execute("UPDATE messages SET content='WAL中的附件草稿' WHERE id=1")
                live.commit()
                assert Path(str(path) + "-wal").exists()
                target = folder / "backup.sqlite"
                with connect(target) as backup:
                    live.backup(backup)
                    assert snapshot(backup) == snapshot(live)
                bootstrap(path, source)
                assert live.execute("SELECT status FROM messages WHERE id=2").fetchone() == (35,)
                assert live.execute("SELECT content FROM messages WHERE id=1").fetchone() == ("WAL中的附件草稿",)
            finally:
                live.close()
        check("wal-data-and-consistent-backup", wal_backup)

        def rejection(path, mutations):
            with connect(path) as db:
                db.executescript(mutations)
                before = db.execute("SELECT group_concat(sql) FROM sqlite_master").fetchone()
            try:
                bootstrap(path, source)
            except (RuntimeError, sqlite3.DatabaseError):
                pass
            else:
                raise AssertionError("Unfamiliar structure was accepted")
            with connect(path) as db:
                assert db.execute("SELECT group_concat(sql) FROM sqlite_master").fetchone() == before
                assert db.execute("SELECT status FROM messages WHERE id=2").fetchone() == (20,)
        check("missing-column-rejected", lambda p: rejection(p,"ALTER TABLE messages RENAME COLUMN content TO unsupported"))
        check("unknown-table-rejected", lambda p: rejection(p,"CREATE TABLE future_table(id INTEGER)"))
        check("unknown-trigger-rejected", lambda p: rejection(p,"CREATE TRIGGER bad AFTER UPDATE ON messages BEGIN SELECT 1; END"))
        check("missing-unique-index-rejected", lambda p: rejection(p,"DROP INDEX messages_topic_seq"))
        check("wrong-partial-index-rejected", lambda p: rejection(p,"DROP INDEX messages_topic_effective; CREATE UNIQUE INDEX wrong ON messages(topic_id,effective_seq) WHERE effective_seq>0"))
        check("foreign-key-data-rejected", lambda p: rejection(p,"UPDATE users SET account_id=999 WHERE id=1"))
        check("unknown-marker-rule-rejected", lambda p: rejection(p,constant(source,"migrationCreateSQL") + "; INSERT INTO claw_local_migrations VALUES ('future',1)"))

        def commit_rejected(path):
            with connect(path) as db:
                before = snapshot(db)
            try:
                bootstrap(path,source,reject_commit=True)
            except sqlite3.DatabaseError:
                pass
            else:
                raise AssertionError("COMMIT failure must reject bootstrap")
            with connect(path) as db:
                assert snapshot(db) == before
                assert not db.execute("SELECT name FROM sqlite_master WHERE name='claw_local_migrations'").fetchall()
        check("actual-sqlite-commit-denial-rolls-back", commit_rejected)

        def marker_insert_rejected(path):
            with connect(path) as db:
                db.execute("CREATE TABLE claw_local_migrations(rule TEXT NOT NULL PRIMARY KEY, completed INTEGER NOT NULL CHECK(completed=0))")
                before = snapshot(db)
            try:
                bootstrap(path,source)
            except sqlite3.IntegrityError:
                pass
            else:
                raise AssertionError("Marker write failure must reject bootstrap")
            with connect(path) as db:
                assert snapshot(db) == before
                assert db.execute("SELECT COUNT(*) FROM claw_local_migrations").fetchone() == (0,)
        check("marker-insert-failure-rolls-back-status", marker_insert_rejected)

        fresh = folder / "fresh.sqlite"
        try:
            bootstrap(fresh,source)
            with connect(fresh) as db:
                assert db.execute(constant(source,"migrationReadSQL")).fetchone() == (1,)
                db.execute("INSERT INTO messages(status,content) VALUES (20,'new message')")
            bootstrap(fresh,source)
            with connect(fresh) as db:
                assert db.execute("SELECT status FROM messages").fetchone() == (20,)
            results.append({"name":"fresh-marker-before-new20", "status":"pass"})
        except Exception as error:
            results.append({"name":"fresh-marker-before-new20", "status":"fail", "error":str(error)})

    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source_path = ROOT / "TinodiosDB/BaseDb.swift"
    results = run(source_path.read_text(encoding="utf-8"))
    report = {"evidence": "real_sqlite_synthetic_fixture_production_SQL_Python_adapter_not_Swift",
              "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
              "fixture_sha256": hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
              "tests": len(results), "failed": sum(r["status"] != "pass" for r in results),
              "results": results}
    for result in results:
        print(result)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    assert report["failed"] == 0, report


if __name__ == "__main__":
    main()
