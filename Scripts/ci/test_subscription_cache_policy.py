#!/usr/bin/env python3
"""Guard the iOS subscription cache against duplicate-row launch crashes."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOPIC = ROOT / "TinodeSDK" / "Topic.swift"
SUBSCRIBER_DB = ROOT / "TinodiosDB" / "SubscriberDb.swift"
BASE_DB = ROOT / "TinodiosDB" / "BaseDb.swift"


def main() -> None:
    topic_source = TOPIC.read_text(encoding="utf-8")
    subscriber_source = SUBSCRIBER_DB.read_text(encoding="utf-8")
    base_source = BASE_DB.read_text(encoding="utf-8")

    assert "Dictionary(uniqueKeysWithValues: loaded.map" not in topic_source, (
        "Cached subscriptions must not trap when duplicate user IDs are present."
    )
    assert "indexSubscriptions(_ loaded:" in topic_source
    assert "candidate as? Subscription<SP, SR>" in topic_source
    assert "createIndex(topicId, userId, unique: true" in subscriber_source, (
        "The database must enforce one subscription per topic and user."
    )
    assert "existingRecord.update(setters)" in subscriber_source, (
        "Duplicate subscription writes must update the existing row."
    )
    assert "kSchemaVersion: Int32 = 113" in base_source, (
        "The schema must invalidate previously corrupted subscription caches."
    )


if __name__ == "__main__":
    main()
