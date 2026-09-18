//
//  MediaRecorder.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

// Recorder lifecycle is owned by one page/account lease. AV work stays on main;
// retirement admission is synchronous and never invokes AV or UI under Cache locks.
//
import AVFoundation

enum MediaRecorderPermissionEvent: Equatable { case requesting, granted, denied }

protocol MediaRecorderDelegate: AnyObject {
    func didStartRecording(recorder: MediaRecorder)
    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval)
    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval)
    func didFailRecording(recorder: MediaRecorder, _ error: Error)
    func didUpdateRecordingPermission(recorder: MediaRecorder, event: MediaRecorderPermissionEvent)
}

enum MediaRecorderError: Error, Equatable {
    case initializationFailed, recordingFailed, cancelledByUser, tooShort, unreadable
}

protocol MediaRecordingSession: AnyObject {
    var recordPermission: AVAudioSession.RecordPermission { get }
    func requestRecordPermission(_ callback: @escaping (Bool) -> Void)
    func activate() throws
    func deactivate() throws
}

private final class SystemMediaRecordingSession: MediaRecordingSession {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }
    var recordPermission: AVAudioSession.RecordPermission { session.recordPermission }
    func requestRecordPermission(_ callback: @escaping (Bool) -> Void) {
        session.requestRecordPermission(callback)
    }
    func activate() throws {
        try session.setCategory(.playAndRecord, options: .defaultToSpeaker)
        try session.setActive(true)
    }
    func deactivate() throws { try session.setActive(false) }
}

protocol MediaRecordingEngine: AnyObject {
    var delegate: AVAudioRecorderDelegate? { get set }
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
    var isMeteringEnabled: Bool { get set }
    func prepareToRecord() -> Bool
    func record() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
    func pause()
    func updateMeters()
    func averagePower(forChannel channelNumber: Int) -> Float
}
extension AVAudioRecorder: MediaRecordingEngine {}

class MediaRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable { case idle, requestingPermission, preparing, recording, preview, transferred, retired }
    struct Recording {
        let url: URL
        let duration: Int
        let preview: Data
    }

    private let admissionLock = NSLock()
    private var retired = false
    private let ownerIsCurrent: () -> Bool
    private let session: MediaRecordingSession
    private let factory: (URL, [String: Any]) throws -> MediaRecordingEngine
    private let directory: URL
    private let log: (String) -> Void
    private let schedulesTimer: Bool
    private let readData: (URL) throws -> Data
    private let removeFile: (URL) throws -> Void
    private var engine: MediaRecordingEngine?
    private var updateTimer: Timer?
    private var ownedURL: URL?
    private var completed: Recording?
    private var permissionRequest: UUID?
    private var activeSession = false
    private var lastTime: TimeInterval = 0
    private var audioSampler = AudioSampler()
    private(set) var state: State = .idle
    weak var delegate: MediaRecorderDelegate?
    var onRetired: (() -> Void)?
    var timerPrecision: TimeInterval = 0.03
    var maxDuration: Int?
    var recordFileURL: URL? { completed?.url ?? ownedURL }
    var duration: Int? { completed?.duration ?? (ownedURL == nil ? nil : Int(lastTime * 1000)) }
    var preview: Data { completed?.preview ?? audioSampler.obtain(dstCount: 96) }

    init(ownerIsCurrent: @escaping () -> Bool = { true },
         session: MediaRecordingSession? = nil,
         factory: @escaping (URL, [String: Any]) throws -> MediaRecordingEngine = {
             try AVAudioRecorder(url: $0, settings: $1)
         },
         directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
         schedulesTimer: Bool = true, readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         log: @escaping (String) -> Void = { _ in }) {
        self.ownerIsCurrent = ownerIsCurrent
        self.session = session ?? SystemMediaRecordingSession()
        self.factory = factory
        self.directory = directory
        self.schedulesTimer = schedulesTimer
        self.readData = readData
        self.removeFile = removeFile
        self.log = log
        super.init()
    }

    var isCurrent: Bool {
        admissionLock.lock()
        let admitted = !retired
        admissionLock.unlock()
        return admitted && ownerIsCurrent()
    }

    var isRecording: Bool {
        isCurrent && state == .recording && engine?.isRecording == true
    }

    // This is the ONLY operation allowed while the SDK/Cache locks are held.
    // Physical stop, file deletion and callbacks are performed later, outside those locks.
    func markRetired() {
        admissionLock.lock()
        retired = true
        admissionLock.unlock()
    }

    func finishRetirement() {
        let finish = { [self] in
            discardOwnedRecording()
            state = .retired
            delegate = nil
            let callback = onRetired
            onRetired = nil
            callback?()
        }
        if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
    }

    func retire() { markRetired(); finishRetirement() }

    func start() {
        precondition(Thread.isMainThread)
        guard isCurrent, state == .idle else { return }
        switch session.recordPermission {
        case .undetermined:
            guard permissionRequest == nil else { return }
            state = .requestingPermission
            let request = UUID()
            permissionRequest = request
            delegate?.didUpdateRecordingPermission(recorder: self, event: .requesting)
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.isCurrent, self.permissionRequest == request else { return }
                    self.permissionRequest = nil
                    if self.state == .requestingPermission { self.state = .idle }
                    // Permission completion never carries a recording intent.
                    self.delegate?.didUpdateRecordingPermission(recorder: self, event: granted ? .granted : .denied)
                }
            }
        case .granted:
            permissionRequest = nil
            startRecording()
        case .denied:
            delegate?.didUpdateRecordingPermission(recorder: self, event: .denied)
        @unknown default:
            delegate?.didUpdateRecordingPermission(recorder: self, event: .denied)
        }
    }

    private func startRecording() {
        state = .preparing
        let candidate = directory.appendingPathComponent(UUID().uuidString + ".m4a")
        var prepared: MediaRecordingEngine?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            let recorder = try factory(candidate, settings)
            prepared = recorder
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw MediaRecorderError.initializationFailed }
            guard isCurrent else { throw MediaRecorderError.cancelledByUser }
            // activate may partially configure AVAudioSession before throwing.
            activeSession = true
            try session.activate()
            guard isCurrent else { throw MediaRecorderError.cancelledByUser }
            // All AV calls are outside the admission/Cache/SDK locks. Retirement
            // closes admission immediately; an already-entered AV call is stopped
            // on main before any result/delegate delivery can be accepted.
            let started = maxDuration.map { recorder.record(forDuration: TimeInterval($0) / 1000) }
                ?? recorder.record()
            guard started else { throw MediaRecorderError.recordingFailed }
            engine = recorder
            ownedURL = candidate
            completed = nil
            lastTime = 0
            audioSampler = AudioSampler()
            state = .recording
            guard isCurrent else { retire(); return }
            if schedulesTimer {
                updateTimer = Timer.scheduledTimer(timeInterval: timerPrecision, target: self,
                    selector: #selector(recordUpdate), userInfo: nil, repeats: true)
            }
            delegate?.didStartRecording(recorder: self)
        } catch {
            prepared?.delegate = nil
            prepared?.stop()
            deactivate()
            try? FileManager.default.removeItem(at: candidate)
            engine = nil
            ownedURL = nil
            completed = nil
            state = isCurrent ? .idle : .retired
            log("recording_initialization_failed")
            if isCurrent { delegate?.didFailRecording(recorder: self, MediaRecorderError.initializationFailed) }
        }
    }

    // Pending authorization is not a pending start operation. Its eventual result
    // may still inform this same live page, but can never start the microphone.
    func cancelPendingIntent() {
        precondition(Thread.isMainThread)
        if state == .requestingPermission { state = .idle }
    }

    @discardableResult
    func stopForPreview() -> Recording? {
        precondition(Thread.isMainThread)
        guard isCurrent else { retire(); return nil }
        if let completed = completed { return completed }
        guard let recorder = engine, let url = ownedURL else {
            cancelPendingIntent()
            return nil
        }
        let elapsed = max(lastTime, recorder.currentTime)
        updateTimer?.invalidate()
        updateTimer = nil
        recorder.delegate = nil
        recorder.stop()
        engine = nil
        deactivate()
        lastTime = elapsed
        let recording = Recording(url: url, duration: max(0, Int(elapsed * 1000)),
                                  preview: audioSampler.obtain(dstCount: 96))
        completed = recording
        state = .preview
        delegate?.didFinishRecording(recorder: self, url: url, duration: elapsed)
        return recording
    }

    func stop(discard: Bool = false) {
        if discard { delete() } else { _ = stopForPreview() }
    }

    func pause() {
        precondition(Thread.isMainThread)
        guard isCurrent else { return }
        engine?.pause()
    }

    func delete() {
        precondition(Thread.isMainThread)
        let hadOwnedRecording = ownedURL != nil || state == .requestingPermission
        discardOwnedRecording()
        if isCurrent {
            state = .idle
            if hadOwnedRecording { delegate?.didFailRecording(recorder: self, MediaRecorderError.cancelledByUser) }
        }
    }

    // The same production entry is exercised with real temporary files in tests.
    // A short/unreadable take remains available for explicit discard or retry.
    func prepareSubmission(minimumDuration: Int) throws -> (Recording, Data) {
        precondition(Thread.isMainThread)
        guard let recording = stopForPreview(), isCurrent else { throw MediaRecorderError.cancelledByUser }
        guard recording.duration >= minimumDuration else { throw MediaRecorderError.tooShort }
        let data: Data
        do { data = try readData(recording.url) } catch { throw MediaRecorderError.unreadable }
        guard !data.isEmpty else { throw MediaRecorderError.unreadable }
        guard isCurrent else { retire(); throw MediaRecorderError.cancelledByUser }
        return (recording, data)
    }

    // The existing message/upload entry accepts Data, not this source URL.
    // Its independent payload/copy survives cleanup of this lease's source file.
    // A failed removal keeps ownedURL so retirement can retry that same file.
    func didSubmit(_ recording: Recording) {
        precondition(Thread.isMainThread)
        guard state == .preview, completed?.url == recording.url else { return }
        completed = nil
        state = .transferred
        removeOwnedFile()
    }

    private func removeOwnedFile() {
        guard let url = ownedURL else { return }
        do {
            try removeFile(url)
            ownedURL = nil
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileNoSuchFileError {
                ownedURL = nil
            } else {
                // Keep the exact cleanup responsibility, never another take's URL.
                log("recording_cleanup_failed")
            }
        }
    }

    private func discardOwnedRecording() {
        permissionRequest = nil
        updateTimer?.invalidate()
        updateTimer = nil
        engine?.delegate = nil
        engine?.stop()
        engine = nil
        deactivate()
        removeOwnedFile()
        completed = nil
        lastTime = 0
        audioSampler = AudioSampler()
    }

    private func deactivate() {
        guard activeSession else { return }
        activeSession = false
        do { try session.deactivate() } catch { log("recording_deactivation_failed") }
    }

    @objc func recordUpdate() {
        guard isCurrent else { retire(); return }
        guard let recorder = engine else { return }
        if recorder.isRecording {
            recorder.updateMeters()
            let amplitude = pow(10, 0.1 * recorder.averagePower(forChannel: 0))
            audioSampler.put(amplitude)
            lastTime = recorder.currentTime
            delegate?.didUpdateRecording(recorder: self, amplitude: amplitude, atTime: lastTime)
        } else {
            _ = stopForPreview()
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        recordingFinished(recorder, successfully: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        recordingFinished(recorder, successfully: false)
    }

    // Both AV callbacks and the native fake AV boundary enter this exact identity check.
    func recordingFinished(_ recorder: MediaRecordingEngine, successfully flag: Bool) {
        let finish = { [weak self] in
            guard let self = self, self.engine === recorder, self.isCurrent else { return }
            if flag { _ = self.stopForPreview() } else { self.failRecording() }
        }
        if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
    }

    private func failRecording() {
        discardOwnedRecording()
        state = .idle
        log("recording_failed")
        delegate?.didFailRecording(recorder: self, MediaRecorderError.recordingFailed)
    }
}

// Class for generating audio preview from a stream of amplitudes of unknown length.
private class AudioSampler {
    private static let kVisualizationBars = 128

    private var samples: [Float]
    private var scratchBuff: [Float]
    // The index of a bucket being filled.
    private var bucketIndex: Int
    // Number of samples per bucket in mScratchBuff.
    private var aggregateCount: Int
    // Number of samples added the the current bucket.
    private var samplesPerBucket: Int

    init() {
        samples = [Float](repeating: 0, count: AudioSampler.kVisualizationBars * 2)
        scratchBuff = [Float](repeating: 0, count: AudioSampler.kVisualizationBars)
        bucketIndex = 0
        samplesPerBucket = 0
        aggregateCount = 1
    }

    public func put(_ val: Float) {
        // Fill out the main buffer first.
        if aggregateCount == 1 {
            if bucketIndex < samples.count {
                samples[bucketIndex] = val
                bucketIndex += 1
                return
            }
            compact()
        }

        // Check if the current bucket is full.
        if samplesPerBucket == aggregateCount {
            // Normalize the bucket.
            scratchBuff[bucketIndex] = scratchBuff[bucketIndex] / Float(samplesPerBucket)
            bucketIndex += 1
            samplesPerBucket = 0
        }

        // Check if scratch buffer is full.
        if bucketIndex == scratchBuff.count {
            compact()
        }
        scratchBuff[bucketIndex] += Float(val)
        samplesPerBucket += 1
    }

    // Get the count of available samples in the main buffer + scratch buffer.
    private var length: Int {
        if aggregateCount == 1 {
            // Only the main buffer is available.
            return bucketIndex
        }
        // Completely filled main buffer + partially filled scratch buffer.
        return samples.count + bucketIndex + 1
    }

    // Get bucket content at the given index from the main + scratch buffer.
    private func getAt(_ index: Int) -> Float {
        var index = index
        // Index into the main buffer.
        if index < samples.count {
            return samples[index]
        }
        // Index into scratch buffer.
        index -= samples.count
        if index < bucketIndex {
            return scratchBuff[index]
        }
        // Last partially filled bucket in the scratch buffer.
        return scratchBuff[index] / Float(samplesPerBucket)
    }

    public func obtain(dstCount: Int) -> Data {
        // We can only return as many as we have.
        var dst = [Float](repeating: 0, count: dstCount)
        let srcCount = self.length
        // Resampling factor. Couple be lower or higher than 1.
        let factor: Float = Float(srcCount) / Float(dstCount)
        var maxAmp: Float = -1
        // src = 100, dst = 200, factor = 0.5
        // src = 200, dst = 100, factor = 2.0
        for i in 0..<dstCount {
            let lo = Int(Float(i) * factor) // low bound
            let hi = Int(Float(i + 1) * factor) // high bound
            if (hi == lo) {
                dst[i] = getAt(lo)
            } else {
                var amp: Float = 0
                for j in lo..<hi {
                    amp += getAt(j)
                }
                dst[i] = max(0, amp / Float(hi - lo))
            }
            maxAmp = max(dst[i], maxAmp)
        }

        var result = [UInt8](repeating: 0, count: dst.count)
        if maxAmp > 0 {
            for i in 0..<dst.count {
                result[i] = UInt8(100 * dst[i] / maxAmp)
            }
        }

        return Data(result)
    }

    // Downscale the amplitudes 2x.
    private func compact() {
        let len = AudioSampler.kVisualizationBars / 2
        // Donwsample the main buffer: two consecutive samples make one new sample.
        for i in 0..<len {
            samples[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5
        }
        // Copy scratch buffer to the upper half the the main buffer.
        for i in 0..<len {
            samples[len + i] = scratchBuff[i]
        }
        // Clear the scratch buffer.
        scratchBuff = scratchBuff.map{ _ in return 0 }
        // Double the number of samples per bucket.
        aggregateCount *= 2
        // Reset scratch counters.
        bucketIndex = 0
        samplesPerBucket = 0
    }
}
