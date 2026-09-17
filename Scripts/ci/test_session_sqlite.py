#!/usr/bin/env python3
"""Synthetic old-113 SQLite evidence; Python adapter, NOT Swift execution."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'Scripts/ci/fixtures/ios113.sql'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-ref')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    def source(path):
        if args.source_ref:
            return subprocess.run(['rtk', 'git', 'show', f'{args.source_ref}:{path}'],
                cwd=ROOT, check=True, capture_output=True).stdout.decode('utf-8')
        return (ROOT / path).read_text(encoding='utf-8')
    base = source('TinodiosDB/BaseDb.swift')
    store = source('TinodiosDB/SqlStore.swift')
    message = source('TinodiosDB/MessageDb.swift')
    def sql(text, name):
        match = re.search(r'static let ' + name + r' = "([^"\n]+)"', text)
        return match.group(1) if match else None
    deactivate = sql(base, 'deactivateAccountSQL')
    ownership = sql(store, 'ownedTopicSQL')
    def fixture():
        db = sqlite3.connect(':memory:')
        db.executescript(FIXTURE.read_text(encoding='utf-8'))
        db.execute('UPDATE messages SET status=35 WHERE id=3')
        db.execute('UPDATE messages SET status=36 WHERE id=4')
        db.execute('UPDATE messages SET head=? WHERE id IN (2,3,4)',
            ('{"clientmsgid":"abcdefab-1111-4111-8111-abcdefabcdef"}',))
        db.commit()
        return db
    def logout(db, account=1, uid='usrFixtureA'):
        if deactivate:
            db.execute(deactivate, (account, uid))
        else:
            # The pre-IOS04 supported-store logout implementation's clearDb.
            for table in ['messages','subscriptions','topics','users','accounts','sqlite_sequence']:
                db.execute('DELETE FROM ' + table)
    def owns(db, topic, account, uid):
        return db.execute(ownership, (topic, account, uid)).fetchone()[0] == 1 if ownership else True
    results = []
    def check(name, body):
        db = fixture()
        try:
            body(db)
            results.append({'name': name, 'status': 'pass'})
        except Exception as error:
            results.append({'name': name, 'status': 'fail', 'error': str(error) or type(error).__name__})
        finally:
            db.close()
    def preserve(db):
        before = db.execute('SELECT * FROM messages ORDER BY id').fetchall()
        sequence = db.execute('SELECT * FROM sqlite_sequence ORDER BY name').fetchall()
        logout(db)
        assert db.execute('SELECT * FROM messages ORDER BY id').fetchall() == before
        assert db.execute('SELECT * FROM sqlite_sequence ORDER BY name').fetchall() == sequence
        assert db.execute('SELECT last_active,device_id FROM accounts WHERE id=1').fetchone() == (0,None)
    check('logout-preserves-all-message-payloads-statuses-UUID-and-sequence', preserve)
    def stale(db):
        db.execute("UPDATE accounts SET last_active=CASE id WHEN 2 THEN 1 ELSE 0 END")
        db.execute("UPDATE accounts SET device_id='new-device' WHERE id=2")
        logout(db)
        assert db.execute('SELECT last_active,device_id FROM accounts WHERE id=2').fetchone() == (1,'new-device')
        assert db.execute('SELECT COUNT(*) FROM messages').fetchone()[0] == 9
    check('captured-old-UID-deactivation-preserves-new-account', stale)
    def unknown(db):
        logout(db)
        db.execute('UPDATE accounts SET last_active=1 WHERE id=1')
        assert db.execute('SELECT status FROM messages WHERE id IN (2,3,4) ORDER BY id').fetchall() == [(20,),(35,),(36,)]
    check('reactivation-preserves-never-sent-and-uncertain-qualification', unknown)
    def rollback(db):
        before = db.execute('SELECT * FROM accounts').fetchall()
        db.execute('BEGIN IMMEDIATE')
        logout(db)
        db.rollback()
        assert db.execute('SELECT * FROM accounts').fetchall() == before
        assert db.execute('SELECT COUNT(*) FROM messages').fetchone()[0] == 9
    check('interrupted-deactivation-transaction-rolls-back-without-loss', rollback)
    def anonymous(db):
        db.execute('UPDATE accounts SET last_active=0')
        assert not owns(db,1,1,'usrFixtureA')
    check('inactive-account-cannot-read-cached-topic-ID', anonymous)
    def cross(db):
        db.execute('UPDATE accounts SET last_active=CASE id WHEN 2 THEN 1 ELSE 0 END')
        db.execute("UPDATE topics SET topic='grpFixtureA' WHERE id=2")
        assert not owns(db,1,2,'usrFixtureB')
        assert owns(db,2,2,'usrFixtureB')
    check('same-topic-name-does-not-cross-account-row-ownership', cross)
    def mismatch(db):
        assert not owns(db,1,1,'usrFixtureB')
    check('UID-and-account-row-must-match', mismatch)
    def latest(db):
        # Mirror the production SQLite.swift DSL account predicate separately.
        predicate = ' WHERE t.account_id=?' if 'topics[topicDb.accountId] == account.id' in message else ''
        rows = db.execute('SELECT DISTINCT m.topic_id FROM messages m JOIN topics t ON m.topic_id=t.id' + predicate,
                          (2,) if predicate else ()).fetchall()
        assert rows == [(2,)]
    check('latest-preview-query-is-account-scoped', latest)
    report = {'evidence':'actual_SQLite_synthetic_fixture_production_SQL_Python_adapter_not_Swift',
        'source_ref':args.source_ref or 'working-tree', 'fixture_sha256':hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
        'tests':len(results), 'failed':sum(x['status'] != 'pass' for x in results), 'results':results}
    if args.report:
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    raise SystemExit(bool(report['failed']))


if __name__ == '__main__':
    main()
