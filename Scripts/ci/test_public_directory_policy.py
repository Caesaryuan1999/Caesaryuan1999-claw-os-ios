#!/usr/bin/env python3
"""Source wiring checks; actual production constructor/consumer runs in Mac XCTest."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
utils = (ROOT / "Tinodios/Utils.swift").read_text(encoding="utf-8")
find = (ROOT / "Tinodios/FindInteractor.swift").read_text(encoding="utf-8")
add = (ROOT / "Tinodios/AddByIDViewController.swift").read_text(encoding="utf-8")
view = (ROOT / "Tinodios/FindViewController.swift").read_text(encoding="utf-8")
tests = (ROOT / "TinodiosUITests/PublicDirectoryTests.swift").read_text(encoding="utf-8")
project = (ROOT / "Tinodios.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
ci = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text(encoding="utf-8")
assert 'return validAlias ? [Tinode.kTagAlias + value] : []' in utils
assert 'terms.joined(separator: ",")' in utils
assert "expected.contains(normalize($0))" in utils
assert "ticket.owner == ObjectIdentifier(owner)" in utils
assert "generation == ticket.generation" in utils
for source in (find, add):
    assert "getSubscriptions()" not in source
    assert "lookup.consume(" in source
    assert "response?.meta?.sub?.compactMap" in source
    assert "pub: ticket.wireQuery" in source
    assert "Cache.isCurrent(owner)" in source
assert "invalidateDirectorySearch(input: queryString)" in view
assert "interactor.canUse(selected, input: self.getQueryString())" in view
assert "newContacts.filter" in view
assert "lookup.invalidate()" in add
assert "self.presentChatReplacingCurrentVC(with: returnedUID)" in add
scanner = add.split("extension AddByIDViewController: QRScannerDelegate", 1)[1]
assert "handleCodeEntered" not in scanner
local_read = find.split("func fetchLocalContacts()", 1)[1].split("private func matchingLocalContacts", 1)[0]
assert "ClawLocalContactRead.read" in local_read and "Cache.ifCurrent(owner)" in local_read
assert "isConnectionAuthenticated" not in local_read
assert find.count("owner.isConnectionAuthenticated") == 2
assert utils.count("owner.store?.myUid == uid") == 2
assert "CLAW_PUBLIC_DIRECTORY_TESTS" in project
assert "PublicDirectoryTests.swift in Sources" in project
assert "-only-testing:TinodiosUITests/PublicDirectoryTests" in ci
assert tests.count("func test") == 13
print("PUBLIC02 wiring PASS; 13 native methods NOT_RUN on Windows")
