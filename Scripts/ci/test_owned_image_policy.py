from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
def read(name):
    return (ROOT / name).read_text(encoding="utf-8")

helper = read("Tinodios/ClawSecondaryUIState.swift")
owned = helper[helper.index("enum ClawOwnedImageError"):]
assert "Cache." not in owned
assert "session.accepts(owner: owner" in owned
assert "owner.withActiveSession" in owned and "inCurrentSlot" in owned
assert "isConnectionAuthenticated" not in owned
assert "ClawMediaFiles.cacheKey(origin:" in owned
assert "ClawMediaFiles.isAllowedMediaURL" in owned
assert "ClawMediaFiles.origin(url) == ClawMediaFiles.origin(serviceURL)" in owned
assert "owner.getRequestHeaders()" in owned
assert '["X-Tinode-APIKey", "X-Tinode-Auth", "Authorization", "Cookie"]' in owned
assert "func redirectedRequest(_ request: URLRequest) -> URLRequest? { nil }" in owned
assert "Kingfisher.ImageResource(downloadURL:" in owned
assert 'ImageDownloader(name: "claw-owned-" + UUID().uuidString)' in owned
assert ".ephemeral" in owned and ".downloader(downloader)" in owned
assert "DispatchQueue.main.async" in owned and "DispatchQueue.main.sync" not in owned

utils = read("Tinodios/Utils.swift")
bridge = utils[utils.index("extension Utils {"):utils.index("enum AccountNames {")]
assert "Cache.ifCurrent(owner)" in bridge and "Cache.sessionGeneration" in bridge
assert "context: ownedImageContext()" in bridge
assert "loader.load(from: url, context: context)" in bridge
assert "url!.downloadURL" not in utils
avatar = read("Tinodios/widgets/RoundImageView.swift")
assert avatar.count("invalidateImageRequest()") >= 5
assert "ownedImageContextProvider()" in avatar
assert "self.imageSlot.accepts(ticket)" in avatar and "context.withCurrent" in avatar
assert "Cache.tinode" not in avatar and "AnyModifier" not in avatar
attachment = read("Tinodios/format/AsyncImageTextAttachment.swift")
assert "context: Utils.ownedImageContext()" in attachment
assert "self.imageSlot.accepts(ticket), self.url == requestURL" in attachment
assert "context.withCurrent" in attachment
assert "process(image) ?? errorImage" in attachment
assert 'Log.default.info("inline_image_load_failed")' in attachment
assert "error.localizedDescription" not in attachment and "self.url.absoluteString" not in attachment
thumbnail = read("Tinodios/format/ThumbnailTransformer.swift")
assert "private let imageContext = Utils.ownedImageContext()" in thumbnail
assert "context?.resourceURL(from: ref), context: context" in thumbnail
assert "let applied = context.withCurrent" in thumbnail

tests = read("TinodiosUITests/OwnedImageTests.swift")
# The original ten image methods remain; the same selected class now adds eleven file-transfer methods.
image_tests = tests[:tests.index("// Actual URLSession download tasks")]
assert len(re.findall(r"    func test\w+\(", image_tests)) == 10
assert len(re.findall(r"    func test\w+\(", tests)) == 21
assert "BaseDb(databasePath:" in tests and "KingfisherManager.shared.retrieveImage" in tests
assert "RoundImageView(frame:" in tests and "AsyncImageTextAttachment(url:" in tests
assert "modifier.modified(for: current)" in tests and ".onlyFromCache" in tests
project = read("Tinodios.xcodeproj/project.pbxproj")
for file in ("RoundImageView.swift", "AsyncImageTextAttachment.swift", "EntityTextAttachment.swift"):
    assert project.count(file + " in Sources */ =") == 2
assert "OwnedImageTests.swift in Sources */ =" in project
assert "-only-testing:TinodiosUITests/OwnedImageTests" in read("Scripts/ci/verify_publish_outcomes_macos.sh")
print("OWNED-IMAGE-02 source/real-consumer/target wiring PASS; Swift and device execution are separate")
