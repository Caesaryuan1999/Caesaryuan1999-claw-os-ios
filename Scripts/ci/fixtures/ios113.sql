-- Synthetic old-version 113 fixture, transcribed from the five table builders
-- at 97e21f49 / takeover-20260917-214922. No real accounts or attachment data.
PRAGMA user_version = 113;
CREATE TABLE accounts (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, uid TEXT, last_active INTEGER, cred_methods TEXT, device_id TEXT);
CREATE UNIQUE INDEX accounts_uid ON accounts(uid);
CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), uid TEXT, updated TEXT, pub TEXT, account_name TEXT);
CREATE INDEX users_account_uid ON users(account_id, uid);
CREATE TABLE topics (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), status INTEGER, topic TEXT, type INTEGER, visible INTEGER, created TEXT, updated TEXT, read INTEGER, recv INTEGER, seq INTEGER, clear INTEGER, max_del INTEGER, mode TEXT, defacs TEXT, last_used TEXT, min_local_seq INTEGER, max_local_seq INTEGER, next_unsent_seq INTEGER, tags TEXT, creds TEXT, pub TEXT, priv TEXT, trusted TEXT);
CREATE UNIQUE INDEX topics_account_topic ON topics(account_id, topic);
CREATE TABLE subscriptions (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, mode TEXT, updated TEXT, read INTEGER, recv INTEGER, clear INTEGER, priv TEXT, last_seen TEXT, user_agent TEXT, subscription_class TEXT NOT NULL);
CREATE UNIQUE INDEX subscriptions_topic_user ON subscriptions(topic_id, user_id);
CREATE TABLE messages (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, sender TEXT, ts TEXT, seq INTEGER, high INTEGER, del_id INTEGER, repl_seq INTEGER, effective_seq INTEGER, effective_ts TEXT, head TEXT, content TEXT);
CREATE UNIQUE INDEX messages_topic_seq ON messages(topic_id, seq DESC);
CREATE UNIQUE INDEX messages_topic_effective ON messages(topic_id, effective_seq DESC) WHERE effective_seq IS NOT NULL;
INSERT INTO accounts VALUES (1,'usrFixtureA',1,NULL,'fixture-device'),(2,'usrFixtureB',0,NULL,NULL);
INSERT INTO users(id,account_id,uid,updated,pub,account_name) VALUES (1,1,'usrFixtureA','2026-09-01T00:00:00.000','{"fn":"甲"}','fixtureA'),(2,2,'usrFixtureB','2026-09-01T00:00:00.000','{"fn":"乙"}','fixtureB');
INSERT INTO topics(id,account_id,status,topic,type,visible,seq,next_unsent_seq) VALUES (1,1,50,'grpFixtureA',2,1,8,2000000007),(2,2,50,'grpFixtureB',2,1,1,2000000001);
INSERT INTO subscriptions(id,topic_id,user_id,status,mode,subscription_class) VALUES (1,1,1,50,'JRWP','DefaultSubscription'),(2,2,2,50,'JRWP','DefaultSubscription');
-- Rows 2 and 3 deliberately have identical content/head/timestamp: only the
-- external event history knows whether dispatch happened; SQLite cannot know.
INSERT INTO messages(id,topic_id,user_id,status,sender,ts,seq,effective_seq,head,content) VALUES
(1,1,1,10,'usrFixtureA','2026-09-01T00:00:00.000',2000000001,2000000001,NULL,'草稿'),
(2,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000002,2000000002,'{"attachments":["/v0/file/s/fixture-safe"]}','同样文本与附件'),
(3,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000003,2000000003,'{"attachments":["/v0/file/s/fixture-safe"]}','同样文本与附件'),
(4,1,1,30,'usrFixtureA','2026-09-01T00:00:00.000',2000000004,2000000004,NULL,'在途'),
(5,1,1,40,'usrFixtureA','2026-09-01T00:00:00.000',2000000005,2000000005,NULL,'明确失败'),
(6,1,1,50,'usrFixtureA','2026-09-01T00:00:00.000',6,6,NULL,'已确认'),
(7,2,2,20,'usrFixtureB','2026-09-01T00:00:00.000',2000000001,2000000001,NULL,'另一个账户');
INSERT INTO messages(id,topic_id,user_id,status,sender,ts,seq,repl_seq,effective_seq,effective_ts,head,content) VALUES
(8,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000006,6,2000000006,'2026-09-01T00:00:00.000','{"replace":"msg:6"}','编辑修订');
INSERT INTO messages(id,topic_id,status,seq,high,del_id) VALUES (9,1,80,7,9,1);
