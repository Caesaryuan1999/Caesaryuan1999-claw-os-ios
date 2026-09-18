from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
def read(name): return (ROOT / name).read_text(encoding="utf-8")
sdk = read("TinodeSDK/Tinode.swift")
store = read("TinodiosDB/SqlStore.swift")
db = read("TinodiosDB/BaseDb.swift")
ui = read("Tinodios/SettingsSecurityViewController.swift")
storage = read("TinodeSDK/Storage.swift")
assert "func deleteAccount(_ uid: String)" in storage and "deleteAccountData" not in storage
assert "public protocol AccountDeletionStorage: Storage" in sdk
assert "case accountDeletedLocalCleanupIncomplete" in sdk
assert "let cleaned = (self.store as? AccountDeletionStorage)?.deleteAccountData(ownerUid) ?? false" in sdk
assert "self.logout()\n            return cleaned ? nil" in sdk
recovery = sdk[sdk.index("public final class AccountDeletionRecovery"):sdk.index("public enum PublishFailureDisposition")]
assert "owner.withActiveSession" in recovery and "let entered = inCurrentSlot" in recovery
assert "owner.myUid == nil, store.myUid == nil, owner.store === store" in recovery
assert "store.deleteAccountData(deletedUID)" in recovery
assert "delCurrentUser" not in recovery and "Cache." not in recovery
assert "public class SqlStore: AccountDeletionStorage" in store
assert "database.uid == nil || database.uid == uid" in store
block = db[db.index("public func deleteUid("):db.index("public static func updateCounter")]
assert "BaseDb.accessQueue.sync" in block and "database.transaction(.immediate)" in block
assert "database.changes == 1" in block
assert "self.account?.uid == uid { self.account = nil }" in block
assert "topicDb?.deleteAll" not in block and "accountDb?.delete" not in block
assert "releaseSavepoint" not in block
assert "local_account_cleanup_failed" in block
assert block.index("DELETE FROM accounts") < block.index("self.account = nil")
assert "let cleanupStore = owner.store as? AccountDeletionStorage" in ui
assert "Cache.isLoggedOut(generation: loggedOutGeneration)" in ui
assert "AccountDeletionRecovery(owner: anonymous, store: store, deletedUID: deletedUID" in ui
assert "Cache.ifCurrent(anonymous)" in ui and "Cache.sessionGeneration == loggedOutGeneration" in ui
assert "重试本机清理" in ui and "暂不处理" in ui
tail = ui[ui.index("private static func presentLocalCleanupRecovery"):]
assert "recovery.retry()" in tail and "delCurrentUser" not in tail
print("LOCAL-DELETE observable/atomic/recovery production wiring PASS; not native runtime")
