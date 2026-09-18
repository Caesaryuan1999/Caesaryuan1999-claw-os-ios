import XCTest
import AVFoundation

// AV/system boundaries are injected; every lifecycle operation is the production
// MediaRecorder class. No microphone, permission dialog, account login or upload.
private final class RecordingSessionFixture: MediaRecordingSession {
    var recordPermission: AVAudioSession.RecordPermission = .granted
    var permissionCallback: ((Bool) -> Void)?
    var activations = 0
    var deactivations = 0
    var failActivation = false
    func requestRecordPermission(_ callback: @escaping (Bool) -> Void) { permissionCallback = callback }
    func activate() throws {
        activations += 1
        if failActivation { throw MediaRecorderError.initializationFailed }
    }
    func deactivate() throws { deactivations += 1 }
}

private final class RecordingEngineFixture: MediaRecordingEngine {
    weak var delegate: AVAudioRecorderDelegate?
    var isRecording = false
    var currentTime: TimeInterval = 0
    var isMeteringEnabled = false
    var prepareSucceeds = true
    var recordSucceeds = true
    var records = 0
    var stops = 0
    var onPrepare: (() -> Void)?
    let url: URL
    init(url: URL) { self.url = url }
    func prepareToRecord() -> Bool {
        try? Data([1, 2, 3, 4]).write(to: url)
        onPrepare?()
        return prepareSucceeds
    }
    func record() -> Bool { records += 1; isRecording = recordSucceeds; return recordSucceeds }
    func record(forDuration duration: TimeInterval) -> Bool { record() }
    func stop() { stops += 1; isRecording = false; currentTime = 0 }
    func pause() { isRecording = false }
    func updateMeters() {}
    func averagePower(forChannel channelNumber: Int) -> Float { -12 }
}

private final class RecordingDelegateFixture: MediaRecorderDelegate {
    var starts = 0
    var finishes = 0
    var failures = 0
    var permission: ((MediaRecorderPermissionEvent) -> Void)?
    func didStartRecording(recorder: MediaRecorder) { starts += 1 }
    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval) { finishes += 1 }
    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval) {}
    func didFailRecording(recorder: MediaRecorder, _ error: Error) { failures += 1 }
    func didUpdateRecordingPermission(recorder: MediaRecorder, event: MediaRecorderPermissionEvent) { permission?(event) }
}

final class MediaRecorderLifecycleTests: XCTestCase {
    private func onMain(_ body: () throws -> Void) rethrows {
        if Thread.isMainThread { try body() } else { try DispatchQueue.main.sync(execute: body) }
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPermissionCompletionNeverStartsRecordingOrRevivesRetiredIntent() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let completed = expectation(description: "permission result, no recording")
        let lateDrained = expectation(description: "retired callback drained")
        var recorder: MediaRecorder!
        var created = 0
        let session = RecordingSessionFixture()
        let delegate = RecordingDelegateFixture()
        session.recordPermission = .undetermined
        onMain {
            recorder = MediaRecorder(session: session, factory: { url, _ in
                created += 1; return RecordingEngineFixture(url: url)
            }, directory: dir, schedulesTimer: false)
            recorder.delegate = delegate
            delegate.permission = { event in
                if event == .granted { completed.fulfill() }
            }
            recorder.start()
            recorder.cancelPendingIntent()
            session.permissionCallback?(true)
        }
        wait(for: [completed], timeout: 2)
        onMain {
            XCTAssertEqual(created, 0)
            XCTAssertEqual(delegate.starts, 0)
            XCTAssertEqual(recorder.state, .idle)
            recorder.start()
            recorder.retire()
            session.permissionCallback?(true)
            DispatchQueue.main.async { lateDrained.fulfill() }
        }
        wait(for: [lateDrained], timeout: 2)
        onMain {
            XCTAssertEqual(created, 0)
            XCTAssertEqual(recorder.state, .retired)
            let denied = RecordingSessionFixture()
            denied.recordPermission = .denied
            let r = MediaRecorder(session: denied, factory: { url, _ in
                created += 1; return RecordingEngineFixture(url: url)
            }, directory: dir, schedulesTimer: false)
            r.start()
            XCTAssertEqual(created, 0)
            XCTAssertNil(r.recordFileURL)
            r.retire()
        }
    }

    func testInitializationFailuresClearPartialFileAndRemainNilSafe() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            for failure in 0..<4 {
                let session = RecordingSessionFixture()
                session.failActivation = failure == 2
                let delegate = RecordingDelegateFixture()
                let recorder = MediaRecorder(session: session, factory: { url, _ in
                    if failure == 0 { throw MediaRecorderError.initializationFailed }
                    let engine = RecordingEngineFixture(url: url)
                    engine.prepareSucceeds = failure != 1
                    engine.recordSucceeds = failure != 3
                    return engine
                }, directory: dir, schedulesTimer: false)
                recorder.delegate = delegate
                recorder.start()
                XCTAssertEqual(recorder.state, .idle)
                XCTAssertFalse(recorder.isRecording)
                XCTAssertNil(recorder.recordFileURL)
                XCTAssertNil(recorder.stopForPreview())
                recorder.pause()
                recorder.stop()
                XCTAssertEqual(delegate.failures, 1)
                XCTAssertEqual(delegate.starts, 0)
                XCTAssertEqual(session.deactivations, failure >= 2 ? 1 : 0)
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
                recorder.retire()
            }
        }
    }

    func testRepeatedStopPreservesFirstDurationFileAndPreview() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            var engine: RecordingEngineFixture!
            let delegate = RecordingDelegateFixture()
            let recorder = MediaRecorder(session: RecordingSessionFixture(), factory: { url, _ in
                engine = RecordingEngineFixture(url: url); return engine
            }, directory: dir, schedulesTimer: false)
            recorder.delegate = delegate
            recorder.start()
            engine.currentTime = 4.25
            recorder.recordUpdate()
            let first = try XCTUnwrap(recorder.stopForPreview())
            let again = try XCTUnwrap(recorder.stopForPreview())
            XCTAssertEqual(first.duration, 4250)
            XCTAssertEqual(first.duration, again.duration)
            XCTAssertEqual(first.url, again.url)
            XCTAssertEqual(first.preview, again.preview)
            XCTAssertEqual(engine.stops, 1)
            XCTAssertEqual(delegate.finishes, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
            recorder.retire()
        }
    }

    func testRetirementDuringPreparationClosesAdmissionBeforeAVStart() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            var recorder: MediaRecorder!
            var engine: RecordingEngineFixture!
            let session = RecordingSessionFixture()
            let delegate = RecordingDelegateFixture()
            recorder = MediaRecorder(session: session, factory: { url, _ in
                engine = RecordingEngineFixture(url: url)
                engine.onPrepare = { recorder.markRetired() }
                return engine
            }, directory: dir, schedulesTimer: false)
            recorder.delegate = delegate
            recorder.start()
            XCTAssertEqual(engine.records, 0)
            XCTAssertEqual(session.activations, 0)
            XCTAssertEqual(delegate.starts, 0)
            XCTAssertEqual(delegate.failures, 0)
            XCTAssertEqual(recorder.state, .retired)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
            recorder.finishRetirement()
            recorder.start()
            XCTAssertEqual(engine.records, 0)
        }
    }

    func testSuspensionPreservesPreviewWithoutAutomaticRestart() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            var engine: RecordingEngineFixture!
            let session = RecordingSessionFixture()
            let recorder = MediaRecorder(session: session, factory: { url, _ in
                engine = RecordingEngineFixture(url: url); return engine
            }, directory: dir, schedulesTimer: false)
            recorder.start()
            engine.currentTime = 5
            recorder.cancelPendingIntent()
            let take = try XCTUnwrap(recorder.stopForPreview())
            recorder.start()
            XCTAssertEqual(recorder.state, .preview)
            XCTAssertEqual(engine.records, 1)
            XCTAssertEqual(session.deactivations, 1)
            XCTAssertEqual(take.duration, 5000)
            XCTAssertTrue(FileManager.default.fileExists(atPath: take.url.path))
            recorder.retire()
        }
    }

    func testLateEngineCallbacksCannotMutateNewTakeOrRetiredOwner() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        onMain {
            var current = true
            var engines: [RecordingEngineFixture] = []
            let delegate = RecordingDelegateFixture()
            let recorder = MediaRecorder(ownerIsCurrent: { current }, session: RecordingSessionFixture(), factory: { url, _ in
                let engine = RecordingEngineFixture(url: url); engines.append(engine); return engine
            }, directory: dir, schedulesTimer: false)
            recorder.delegate = delegate
            recorder.start()
            recorder.delete()
            recorder.start()
            let failures = delegate.failures
            recorder.recordingFinished(engines[0], successfully: false)
            XCTAssertTrue(recorder.isRecording)
            XCTAssertEqual(delegate.failures, failures)
            current = false
            recorder.recordingFinished(engines[1], successfully: false)
            XCTAssertEqual(delegate.failures, failures)
            recorder.retire()
            XCTAssertNil(recorder.recordFileURL)
            XCTAssertEqual(recorder.state, .retired)
        }
    }

    func testRetirementDeletesOnlyUnsubmittedOwnedFile() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            var engine: RecordingEngineFixture!
            func make() -> MediaRecorder {
                MediaRecorder(session: RecordingSessionFixture(), factory: { url, _ in
                    engine = RecordingEngineFixture(url: url); return engine
                }, directory: dir, schedulesTimer: false)
            }
            let transferred = make()
            transferred.start()
            engine.currentTime = 4
            let (take, bits) = try transferred.prepareSubmission(minimumDuration: 3000)
            XCTAssertEqual(bits, Data([1, 2, 3, 4]))
            transferred.didSubmit(take)
            transferred.retire()
            XCTAssertTrue(FileManager.default.fileExists(atPath: take.url.path))
            let abandoned = make()
            abandoned.start()
            let abandonedURL = try XCTUnwrap(abandoned.recordFileURL)
            abandoned.retire()
            XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: take.url.path))
        }
    }

    func testShortAndUnreadableSubmissionKeepPreviewForRecovery() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try onMain {
            var engine: RecordingEngineFixture!
            var readFails = true
            let recorder = MediaRecorder(session: RecordingSessionFixture(), factory: { url, _ in
                engine = RecordingEngineFixture(url: url); return engine
            }, directory: dir, schedulesTimer: false, readData: { url in
                if readFails { throw MediaRecorderError.unreadable }
                return try Data(contentsOf: url)
            })
            recorder.start()
            engine.currentTime = 2.999
            XCTAssertThrowsError(try recorder.prepareSubmission(minimumDuration: 3000)) {
                XCTAssertEqual($0 as? MediaRecorderError, .tooShort)
            }
            XCTAssertEqual(recorder.state, .preview)
            recorder.delete()
            recorder.start()
            engine.currentTime = 4
            XCTAssertThrowsError(try recorder.prepareSubmission(minimumDuration: 3000)) {
                XCTAssertEqual($0 as? MediaRecorderError, .unreadable)
            }
            let url = try XCTUnwrap(recorder.recordFileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(recorder.state, .preview)
            readFails = false
            let (take, bits) = try recorder.prepareSubmission(minimumDuration: 3000)
            XCTAssertEqual(take.url, url)
            XCTAssertEqual(take.duration, 4000)
            XCTAssertEqual(bits, Data([1, 2, 3, 4]))
            recorder.retire()
        }
    }
}
