//
//  LargeFileHelper.swift
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK

enum AttachmentUploadPolicy {
    static let maxAttempts = 3

    enum FailureKind: Equatable {
        case transient
        case terminal
        case cancelled
    }

    enum Outcome {
        case success
        case retry
        case failedRetryable
        case failedTerminal
        case cancelled
    }

    static func isRetryable(statusCode: Int) -> Bool {
        return statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
    }

    static func shouldRetry(statusCode: Int?, error: Error?, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        return classify(statusCode: statusCode, error: error) == .transient
    }

    static func classify(statusCode: Int?, error: Error?) -> FailureKind {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                return .cancelled
            }
            return error.domain == NSURLErrorDomain ? .transient : .terminal
        }
        if let statusCode = statusCode {
            return isRetryable(statusCode: statusCode) ? .transient : .terminal
        }
        // A missing response is treated as transient until the retry budget is
        // exhausted; the caller then records it as a terminal failure.
        return .transient
    }

    static func shouldDeleteTemporarySource(outcome: Outcome) -> Bool {
        switch outcome {
        case .success, .cancelled, .failedTerminal:
            return true
        case .retry, .failedRetryable:
            return false
        }
    }
}

public class Upload {
    enum UploadError: Error {
        case invalidState(String)
        case cancelledByUser
    }

    fileprivate var url: URL
    fileprivate var topicId: String = ""
    fileprivate var msgId: Int64 = 0
    fileprivate var filename: String = ""
    fileprivate var isUploading = false
    fileprivate var progress: Float = 0
    fileprivate var responseData: Data = Data()
    fileprivate var progressCb: ((Float) -> Void)?
    fileprivate var finalCb: ((ServerMessage?, Error?) -> Void)?

    fileprivate var task: URLSessionUploadTask?
    fileprivate var request: URLRequest?
    fileprivate var localURL: URL?
    fileprivate var attempt = 1

    public var id: String {
        return "\(topicId)-\(msgId)-\(filename)"
    }

    public var hasResponse: Bool {
        return !self.responseData.isEmpty
    }

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let cb = finalCb {
            cb(nil, UploadError.invalidState("Topic \(topicId), msg id \(msgId), filename \(filename): Could not finish upload. Cancelling."))
        }
    }

    public func appendResponse(_ other: Data) {
        self.responseData.append(other)
    }

    public func getResponse() -> Data {
        return self.responseData
    }

    public func progress(_ val: Float) {
        self.progressCb?(val)
    }

    public func finished(msg: ServerMessage?, err: Error?) {
        self.isUploading = false
        self.finalCb?(msg, err)
        self.finalCb = nil
    }

    fileprivate func prepareForRetry() {
        self.responseData.removeAll(keepingCapacity: true)
        self.progress = 0
    }

    fileprivate func cleanupTemporaryFile() {
        guard let localURL = localURL else { return }
        do {
            try FileManager.default.removeItem(at: localURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // The system may already have removed an old temporary file.
        } catch {
            Cache.log.error("Could not remove upload temporary file: %@", error.localizedDescription)
        }
        self.localURL = nil
    }
}

public class LargeFileHelper: NSObject {
    static let kBoundary = "*****\(Date().millisecondsSince1970)*****"
    static let kTwoHyphens = "--"
    static let kLineEnd = "\r\n"

    private var urlSession: URLSession!
    private var activeUploads: [String: Upload] = [:]
    private var downloadCallbacks: [Int: ((Error?) -> Void)] = [:]
    private var tinode: Tinode!
    // Numeric id of upload.
    private var reqId = 0

    init(with tinode: Tinode, config: URLSessionConfiguration) {
        super.init()
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.tinode = tinode
    }

    convenience init(with tinode: Tinode) {
        let config = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier!)
        self.init(with: tinode, config: config)
    }

    public static func addCommonHeaders(to request: inout URLRequest, using tinode: Tinode) {
        let headers = tinode.getRequestHeaders()
        headers.forEach({ (key: String, value: String) in
            request.addValue(value, forHTTPHeaderField: key)
        })
    }

    public static func addAuthQueryParams(to url: URL, using tinode: Tinode) -> URL {
        return tinode.addAuthQueryParams(url)
    }

    public static func taskID(forTopic topicId: String, msgId: Int64, filename: String) -> String {
        if msgId != 0 {
            return "\(topicId)-\(msgId)-\(filename)"
        }
        return "\(topicId)-avatar"
    }

    public func startMsgAttachmentUpload(filename: String, mimetype: String, data payload: Data, topicId: String, msgId: Int64, progressCallback: ((Float) -> Void)?, completionCallback: @escaping (ServerMessage?, Error?) -> Void) {
        guard var url = tinode.baseURL(useWebsocketProtocol: false) else {
            Cache.log.error("Upload failed: unable to form upload url")
            completionCallback(nil, Upload.UploadError.invalidState("invalid upload url"))
            return
        }
        url.appendPathComponent("file/u/")
        let upload = Upload(url: url)
        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.addValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.addValue(tinode.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("multipart/form-data; boundary=\(LargeFileHelper.kBoundary)", forHTTPHeaderField: "Content-Type")

        LargeFileHelper.addCommonHeaders(to: &request, using: self.tinode)

        var newData = Data()
        // Id section.
        self.reqId += 1
        var header = LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd +
            "Content-Disposition: form-data; name=\"id\"" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd +
            "\(self.reqId)" + LargeFileHelper.kLineEnd
        if !topicId.isEmpty {
            // Topic.
            header +=
                LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd +
                "Content-Disposition: form-data; name=\"topic\"" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd + topicId + LargeFileHelper.kLineEnd
        }
        // File section.
        // Content-Disposition: form-data; name="file"; filename="1519014549699.pdf"
        header += LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kLineEnd +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"" + LargeFileHelper.kLineEnd
        // Content type & transfer encoding.
        header += "Content-Type: \(mimetype)" + LargeFileHelper.kLineEnd + "Content-Transfer-Encoding: binary" + LargeFileHelper.kLineEnd + LargeFileHelper.kLineEnd
        newData.append(contentsOf: header.utf8)
        newData.append(payload)
        let footer = LargeFileHelper.kLineEnd + LargeFileHelper.kTwoHyphens + LargeFileHelper.kBoundary + LargeFileHelper.kTwoHyphens + LargeFileHelper.kLineEnd
        newData.append(contentsOf: footer.utf8)

        let tempDir = FileManager.default.temporaryDirectory

        let localFileName = UUID().uuidString
        let localURL = tempDir.appendingPathComponent("throwaway-\(localFileName)")
        do {
            try newData.write(to: localURL, options: .atomic)
        } catch {
            completionCallback(nil, error)
            return
        }

        let uploadKey = LargeFileHelper.taskID(forTopic: topicId, msgId: msgId, filename: filename)
        Cache.log.info("Starting upload (id='%@', topic='%@', dbMsgId=%lld): file name = %@", uploadKey, topicId, msgId, filename, mimetype)
        upload.isUploading = true
        upload.topicId = topicId
        upload.msgId = msgId
        upload.filename = filename
        upload.progressCb = progressCallback
        upload.finalCb = completionCallback
        upload.request = request
        upload.localURL = localURL
        activeUploads[uploadKey] = upload
        retry(upload: upload, taskId: uploadKey)
    }

    public func startAvatarUpload(mimetype: String, data payload: Data, topicId: String, completionCallback: @escaping (ServerMessage?, Error?) -> Void) {
        let fileName = "avatar-\(Utils.uniqueFilename(forMime: mimetype))"
        startMsgAttachmentUpload(filename: fileName, mimetype: mimetype, data: payload, topicId: topicId, msgId: 0, progressCallback: {_ in /* do nothing */}, completionCallback: completionCallback)
    }

    public func cancelUpload(topicId: String, msgId: Int64 = 0) -> Bool {
        let uploadKeyPrefix = LargeFileHelper.taskID(forTopic: topicId, msgId: msgId, filename: "")
        var keys = [String]()
        for uploadKey in activeUploads.keys {
            if uploadKey.starts(with: uploadKeyPrefix) {
                keys.append(uploadKey)
            }
        }
        for k in keys {
            if let upload = activeUploads.removeValue(forKey: k) {
                upload.task?.cancel()
                upload.cleanupTemporaryFile()
                upload.finished(msg: nil, err: Upload.UploadError.cancelledByUser)
            }
        }
        return !keys.isEmpty
    }

    public func getActiveUpload(for taskId: String) -> Upload? {
        return self.activeUploads[taskId]
    }

    public func uploadFinished(for taskId: String) {
        self.activeUploads.removeValue(forKey: taskId)
    }

    private func retry(upload: Upload, taskId: String) {
        guard let request = upload.request, let localURL = upload.localURL else {
            uploadFinished(for: taskId)
            upload.cleanupTemporaryFile()
            upload.finished(msg: nil, err: Upload.UploadError.invalidState("Missing upload request data"))
            return
        }
        upload.prepareForRetry()
        let task = urlSession.uploadTask(with: request, fromFile: localURL)
        task.taskDescription = taskId
        upload.task = task
        task.resume()
    }

    public func startDownload(from url: URL, completion: ((Error?) -> Void)? = nil) {
        var request = URLRequest(url: url)
        LargeFileHelper.addCommonHeaders(to: &request, using: self.tinode)

        let task = urlSession.downloadTask(with: request)
        if let completion = completion {
            downloadCallbacks[task.taskIdentifier] = completion
        }
        task.resume()
    }
}

extension LargeFileHelper: URLSessionDelegate {
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
    }
}

// Upload result
extension LargeFileHelper: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: Data) {
        if let taskId = dataTask.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            upload.appendResponse(didReceive)
        }
    }
}

// Upload progress
extension LargeFileHelper: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError: Error?) {
        Cache.log.info("Upload (id=%@) complete. Status: %@", task.taskDescription ?? "UNKNOWN", didCompleteWithError?.localizedDescription ?? "ok")
        guard let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) else {
            return
        }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        if AttachmentUploadPolicy.shouldRetry(statusCode: statusCode, error: didCompleteWithError, attempt: upload.attempt) {
            upload.attempt += 1
            Cache.log.info("Retrying upload (id=%@), attempt %d of %d", taskId, upload.attempt, AttachmentUploadPolicy.maxAttempts)
            retry(upload: upload, taskId: taskId)
            return
        }
        self.uploadFinished(for: taskId)
        var serverMsg: ServerMessage?
        var uploadError: Error? = didCompleteWithError
        var outcome: AttachmentUploadPolicy.Outcome =
            AttachmentUploadPolicy.classify(statusCode: statusCode, error: didCompleteWithError) == .cancelled
                ? .cancelled : .failedTerminal
        defer {
            if AttachmentUploadPolicy.shouldDeleteTemporarySource(outcome: outcome) {
                upload.cleanupTemporaryFile()
            }
            upload.finished(msg: serverMsg, err: uploadError)
        }
        guard uploadError == nil else {
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            uploadError = Upload.UploadError.invalidState(String(format: NSLocalizedString("Upload failed (%@). No server response.", comment: "Error message"), upload.id))
            return
        }
        guard response.statusCode == 200 else {
            uploadError = Upload.UploadError.invalidState(String(format: NSLocalizedString("Upload failed (%@): response code %d.", comment: "Error message"), upload.id, response.statusCode))
            return
        }
        guard upload.hasResponse else {
            uploadError = Upload.UploadError.invalidState(String(format: NSLocalizedString("Upload failed (%@): empty response body.", comment: "Error message"), upload.id))
            return
        }
        do {
            serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: upload.getResponse())
            outcome = .success
        } catch {
            uploadError = error
            return
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let taskId = task.taskDescription, let upload = self.getActiveUpload(for: taskId) {
            let progress: Float = totalBytesExpectedToSend > 0 ? Float(totalBytesSent) / Float(totalBytesExpectedToSend) : 0
            upload.progress(progress)
        }
    }
}

// Downloads.
extension LargeFileHelper: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        defer {
            if let cb = downloadCallbacks.removeValue(forKey: downloadTask.taskIdentifier) {
                cb(downloadTask.error)
            }
        }
        guard downloadTask.error == nil else {
            Cache.log.error("LargeFileHelper - download failed: %@", downloadTask.error!.localizedDescription)
            return
        }

        guard let url = downloadTask.originalRequest?.url else { return }
        let fn = url.extractQueryParam(named: "origfn") ?? url.lastPathComponent

        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(fn)

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: destinationURL)
        } catch {
            // Non-fatal: file probably doesn't exist
        }
        do {
            try fileManager.moveItem(at: location, to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.error("LargeFileHelper - could not copy file to disk: %@", error.localizedDescription)
        }
    }
}
