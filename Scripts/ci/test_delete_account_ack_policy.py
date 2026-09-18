from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "TinodeSDK/Tinode.swift").read_text(encoding="utf-8")
start = source.index("public func delCurrentUser(hard: Bool)")
end = source.index("/// Low-level request to delete topic.", start)
block = source[start:end]
assert "this.finishAccountDeletion(packet: packet, requestId: msgId, ownerUid: ownerUid)" in block
assert "ctrl.id == requestId, ctrl.code == ServerMessage.kStatusOk" in block
assert block.index("ctrl.id == requestId") < block.index("self.store?.deleteAccount(ownerUid)")
assert "self.myUid == ownerUid, self.store?.myUid == ownerUid" in block
assert "withActiveSession" in block
assert "TinodeError.requestOutcomeUnknown" in block
assert "if ServerMessage.kStatusOk <= ctrl.code && ctrl.code < ServerMessage.kStatusBadRequest" in source
print("DELETE ACK exact request/200/owner production wiring PASS; not runtime or local purge proof")
