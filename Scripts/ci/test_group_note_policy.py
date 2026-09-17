"""Controller wiring only; SDK XCTest covers delta encoding and ACK merge."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
controller = (root / "Tinodios/TopicGeneralViewController.swift").read_text(encoding="utf-8")
body = controller.split("@IBAction func doneEditingClicked", 1)[1].split("@objc", 1)[0]
assert "topic.comment!" not in body
assert "PrivateType.commentDelta(from: topic.comment, to: topicPrivateTextField.text)" in body
assert "MetaSetDesc(pub: pub, priv: priv)" in body
owner_start = body.index("if topic.isOwner {")
depth = 0
owner_end = None
for index in range(body.index("{", owner_start), len(body)):
    if body[index] == "{": depth += 1
    if body[index] == "}":
        depth -= 1
        if depth == 0:
            owner_end = index
            break
owner = body[owner_start:owner_end]
assert "pub = TheCard(fn: title)" in owner
assert "Tinode.setUniqueTag" in owner and "Tinode.clearTagPrefix" in owner
assert body.index("let priv =") > owner_end
assert "priv = topic.priv" not in body and "priv = self.topic.priv" not in body
print("PASS: topic note uses the SDK delta; owner-only public/tags remain separate")
