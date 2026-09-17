import XCTest
import UserNotifications
import UIKit
import Kingfisher

final class SecondaryUIStateTests: XCTestCase {
    func testNotificationNotDeterminedRequestsPermission() {
        let state = ClawNotificationAuthorization(status: .notDetermined,
            alertsEnabled: false, notificationCenterEnabled: false)
        XCTAssertFalse(state.isUsable)
        XCTAssertEqual(state.action(forStatusButton: true), .request)
        XCTAssertEqual(state.action(forStatusButton: false), .request)
    }

    func testNotificationDeniedOpensSettingsInsteadOfRequestingAgain() {
        let state = ClawNotificationAuthorization(status: .denied,
            alertsEnabled: false, notificationCenterEnabled: false)
        XCTAssertEqual(state.action(forStatusButton: true), .settings)
        XCTAssertEqual(state.action(forStatusButton: false), .settings)
        XCTAssertFalse(state.isUsable)
    }

    func testNotificationAuthorizedWithDisabledAlertOrCenterNeedsSettings() {
        for flags in [(false, true), (true, false), (false, false)] {
            let state = ClawNotificationAuthorization(status: .authorized,
                alertsEnabled: flags.0, notificationCenterEnabled: flags.1)
            XCTAssertFalse(state.isUsable)
            XCTAssertEqual(state.action(forStatusButton: false), .settings)
            XCTAssertTrue(state.title.contains("已授权"))
            XCTAssertTrue(state.summary.contains("部分提醒"))
        }
    }

    func testNotificationGrantedModesKeepUsablePreferencesWithoutReprompt() {
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            let state = ClawNotificationAuthorization(status: status,
                alertsEnabled: true, notificationCenterEnabled: true)
            XCTAssertTrue(state.isUsable)
            XCTAssertEqual(state.action(forStatusButton: false), .none)
            XCTAssertEqual(state.action(forStatusButton: true), .settings)
        }
    }

    func testNotificationReturnFromSettingsUsesNewSnapshot() {
        let denied = ClawNotificationAuthorization(status: .denied,
            alertsEnabled: false, notificationCenterEnabled: false)
        let enabled = ClawNotificationAuthorization(status: .authorized,
            alertsEnabled: true, notificationCenterEnabled: true)
        XCTAssertNotEqual(denied.isUsable, enabled.isUsable)
        XCTAssertEqual(denied.buttonTitle, "前往系统设置")
        XCTAssertEqual(enabled.action(forStatusButton: false), .none)
    }
    private func fixtureImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.blue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    func testInlineImageRequiresActualDecodeBeforeSharing() throws {
        let state = ClawMediaPreviewState()
        XCTAssertNil(state.loadInline(Data("broken image".utf8)))
        XCTAssertNil(state.shareData)
        XCTAssertEqual(state.phase, .failed)
        let bytes = try XCTUnwrap(fixtureImage().pngData())
        XCTAssertNotNil(state.loadInline(bytes))
        XCTAssertEqual(state.phase, .ready)
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(state.shareData)))
    }

    func testImageReferenceLoadingFailureAndRetryNeverSharePlaceholder() {
        let state = ClawMediaPreviewState()
        let first = state.begin()
        XCTAssertNil(state.shareData)
        XCTAssertTrue(state.fail(first))
        XCTAssertNil(state.shareData)
        let retry = state.begin()
        XCTAssertFalse(state.complete(first, image: fixtureImage()))
        XCTAssertNil(state.shareData)
        XCTAssertTrue(state.complete(retry, image: fixtureImage()))
        XCTAssertNotNil(state.shareData)
        XCTAssertFalse(state.fail(first))
        XCTAssertEqual(state.phase, .ready)
    }

    func testImageForbiddenRemovesPreviouslyReadyExport() {
        let state = ClawMediaPreviewState()
        let attempt = state.begin()
        XCTAssertTrue(state.complete(attempt, image: fixtureImage()))
        XCTAssertTrue(state.fail(attempt, forbidden: true))
        XCTAssertEqual(state.phase, .forbidden)
        XCTAssertNil(state.shareData)
    }

    func testMediaSessionRejectsLogoutAccountSwapAndOldGeneration() {
        let owner = NSObject()
        let other = NSObject()
        let gate = ClawMediaSession(owner: ObjectIdentifier(owner), uid: "account-A", generation: 4)
        XCTAssertTrue(gate.accepts(owner: owner, uid: "account-A", storedUID: "account-A", generation: 4))
        XCTAssertFalse(gate.accepts(owner: other, uid: "account-A", storedUID: "account-A", generation: 4))
        XCTAssertFalse(gate.accepts(owner: owner, uid: nil, storedUID: nil, generation: 4))
        XCTAssertFalse(gate.accepts(owner: owner, uid: "account-A", storedUID: "account-B", generation: 4))
        XCTAssertFalse(gate.accepts(owner: owner, uid: "account-A", storedUID: "account-A", generation: 5))
    }

    func testMediaCacheKeySeparatesAccountsAndOriginsWithoutPlaintext() throws {
        let origin = try XCTUnwrap(URL(string: "https://example.invalid/"))
        let url = origin.appendingPathComponent("media/file-id")
        let a = try XCTUnwrap(ClawMediaFiles.cacheKey(origin: origin, uid: "account-A", url: url))
        let b = try XCTUnwrap(ClawMediaFiles.cacheKey(origin: origin, uid: "account-B", url: url))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, ClawMediaFiles.cacheKey(origin: origin, uid: "account-A", url: url))
        XCTAssertFalse(a.contains("account-A"))
        XCTAssertFalse(a.contains("file-id"))
        let other = try XCTUnwrap(URL(string: "https://other.invalid/"))
        XCTAssertNotNil(ClawMediaFiles.cacheKey(origin: origin, uid: "account-A", url: other))
        XCTAssertFalse(ClawMediaFiles.isAllowedMediaURL(URL(string: "http://other.invalid/file")!, service: origin))
        XCTAssertNotEqual(a, ClawMediaFiles.cacheKey(origin: other, uid: "account-A",
                                                   url: other.appendingPathComponent("media/file-id")))
        XCTAssertNil(ClawMediaFiles.origin(try XCTUnwrap(URL(string: "https://user:password@example.invalid/file"))))
        XCTAssertNil(ClawMediaFiles.origin(try XCTUnwrap(URL(string: "file:///tmp/image"))))
    }

    func testActualKingfisherMemoryCacheIgnoresLegacyAndOtherAccountKeys() throws {
        let origin = try XCTUnwrap(URL(string: "https://example.invalid/"))
        let url = origin.appendingPathComponent("media/same")
        let a = try XCTUnwrap(ClawMediaFiles.cacheKey(origin: origin, uid: "A", url: url))
        let b = try XCTUnwrap(ClawMediaFiles.cacheKey(origin: origin, uid: "B", url: url))
        let cache = ImageCache(name: "claw-native-fixture-" + UUID().uuidString)
        defer { cache.clearMemoryCache() }
        cache.store(fixtureImage(), forKey: url.absoluteString, toDisk: false)
        XCTAssertNil(cache.retrieveImageInMemoryCache(forKey: a))
        cache.store(fixtureImage(), forKey: a, toDisk: false)
        XCTAssertNotNil(cache.retrieveImageInMemoryCache(forKey: a))
        XCTAssertNil(cache.retrieveImageInMemoryCache(forKey: b))
        let resource = ImageResource(downloadURL: url, cacheKey: a)
        XCTAssertEqual(resource.cacheKey, a)
        XCTAssertEqual(resource.downloadURL, url)
    }

    func testPNGExportsUseDistinctSafeDirectoriesForRemoteNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("outside.png")
        let originalBytes = Data("keep original".utf8)
        try originalBytes.write(to: original)
        let png = try XCTUnwrap(fixtureImage().pngData())
        var parents = Set<URL>()
        for name in ["../outside.png", original.path, "..\\outside.png", "..", "", "/absolute/folder/file.png"] {
            let export = try ClawMediaFiles.exportPNG(png, suggestedName: name, root: root)
            XCTAssertTrue(export.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/ClawImageExports/"))
            XCTAssertEqual(export.pathExtension, "png")
            XCTAssertEqual(try Data(contentsOf: export), png)
            XCTAssertNotEqual(export, original)
            parents.insert(export.deletingLastPathComponent())
        }
        XCTAssertEqual(parents.count, 6)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    func testFileReadUsesActualFoundationDataAndReportsMissingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.bin")
        let bytes = Data([0, 1, 2, 255])
        try bytes.write(to: file)
        XCTAssertEqual(try ClawMediaFiles.read(file), bytes)
        XCTAssertThrowsError(try ClawMediaFiles.read(root.appendingPathComponent("missing.bin")))
        XCTAssertTrue(ClawMediaFiles.readRecovery.contains("重新选择"))
    }

}
