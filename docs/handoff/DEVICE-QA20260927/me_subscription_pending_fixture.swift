// Added diagnostic matrix, separate from the unchanged original 17 checks.
// Production Promise/helper/caller are injected verbatim; Cache/Topic/UI are controlled.
final class OpaqueFixtureError: Error {}
var pendingChecks: [String: Bool] = [:]
var observations: [[String: Any]] = []

func sameError(_ actual: Error?, _ expected: Error) -> Bool {
    guard let actual = actual else { return false }
    if case TinodeError.serverResponseError(let expectedCode, let expectedText, let expectedWhat) = expected {
        guard case TinodeError.serverResponseError(let code, let text, let what) = actual else { return false }
        return code == expectedCode && text == expectedText && what == expectedWhat
    }
    if let expected = expected as? OpaqueFixtureError, let actual = actual as? OpaqueFixtureError {
        return expected === actual
    }
    return false
}

func details(_ error: Error?) -> [String: Any] {
    guard let error = error else { return ["present": false] }
    var fields: [String: Any] = ["present": true, "type": String(reflecting: type(of: error)),
                                "description": String(describing: error)]
    if case TinodeError.serverResponseError(let code, let text, let what) = error {
        fields["code"] = code; fields["text"] = text; fields["what"] = what ?? "<nil>"
    }
    return fields
}

func resultError(_ promise: PromisedReply<ServerMessage>?) -> Error? {
    guard let promise = promise, promise.isDone else { return nil }
    do { _ = try promise.getResult(); return nil }
    catch { return error }
}

func effects(_ owner: Tinode, _ replacement: Tinode, replaced: Bool, code: Int) -> Bool {
    let expires = [401, 403, 404].contains(code) && !replaced
    return UiUtils.logouts == (expires ? 1 : 0)
        && owner.reconnects == (code == 502 && !replaced ? 1 : 0)
        && replacement.reconnects == 0 && replacement.active
        && (replaced ? Cache.current === replacement : Cache.current === owner)
}

// Capture the exact ten completed-promise errors hidden by the original 17-case observer.
let completedCases: [(String, Int, String, Bool)] = [
    ("current_401", 401, "fixture", false), ("stale_401", 401, "fixture", true),
    ("current_403", 403, "fixture", false), ("stale_403", 403, "fixture", true),
    ("current_404", 404, "fixture", false), ("stale_404", 404, "fixture", true),
    ("current_502", 502, "cluster unreachable", false), ("stale_502", 502, "cluster unreachable", true),
    ("other_502", 502, "other gateway failure", false), ("server_500", 500, "fixture", false)]
for (label, code, text, replaced) in completedCases {
    let owner = Tinode(), replacement = Tinode()
    Cache.current = owner; UiUtils.logouts = 0
    let me = DefaultMeTopic(tinode: owner, l: nil)
    let expected = TinodeError.serverResponseError(code, text, "fixture-what")
    me.reply = { PromisedReply(error: expected) }
    if replaced { me.afterReplyBeforeConsumer = { owner.active = false; Cache.current = replacement } }
    let helper = UiUtils.attachToMeTopic(meListener: nil)
    let observed = resultError(helper)
    pendingChecks["completed_" + label] = sameError(observed, expected)
    observations.append(["case": "completed_" + label, "error": details(observed),
                         "expected": details(expected), "done": helper?.isDone ?? false])
}

// Register helper or the real ChatList caller before rejection; test the calling
// thread and a real background queue. Await only completion, never fake callbacks.
for code in [401, 403, 404, 502, 0] {
    for replaced in [false, true] {
        for background in [false, true] {
            for caller in [false, true] {
                let label = "pending_\(code)_\(replaced ? "stale" : "current")_\(background ? "background" : "calling")_\(caller ? "caller" : "helper")"
                let owner = Tinode(), replacement = Tinode()
                Cache.current = owner; UiUtils.logouts = 0
                let me = DefaultMeTopic(tinode: owner, l: nil)
                let pending = PromisedReply<ServerMessage>()
                me.reply = { pending }
                let expected: Error = code == 0 ? OpaqueFixtureError()
                    : TinodeError.serverResponseError(code, code == 502 ? "cluster unreachable" : "original-text-\(code)", "original-what-\(code)")
                let chat = ChatListInteractor()
                var helper: PromisedReply<ServerMessage>?
                if caller { chat.attachToMeTopic() }
                else { helper = UiUtils.attachToMeTopic(meListener: nil) }
                let registeredBeforeReject = !pending.isDone && me.subscribeCalls == 1
                if replaced { owner.active = false; Cache.current = replacement }
                var producerError: Error?
                var completedOnMain = false
                let done = DispatchSemaphore(value: 0)
                let reject = {
                    completedOnMain = Thread.isMainThread
                    do { try pending.reject(error: expected) }
                    catch { producerError = error }
                    done.signal()
                }
                if background { DispatchQueue.global(qos: .userInitiated).async(execute: reject) }
                else { reject() }
                let finished = done.wait(timeout: .now() + 3) == .success
                // No state read races on timeout: stop the process with a failure
                // report rather than reading fields still owned by the worker.
                if !finished {
                    let timeout: [String: Any] = ["status": "FAIL", "case": label, "reason": "background rejection did not complete"]
                    let data = try JSONSerialization.data(withJSONObject: timeout, options: [.sortedKeys])
                    print(String(data: data, encoding: .utf8)!); exit(2)
                }
                let rootError = resultError(pending)
                let helperError = resultError(helper)
                let observedProducer = caller ? producerError == nil : sameError(producerError, expected)
                let observedHelper = caller || (helper?.isRejected == true && sameError(helperError, expected))
                let ok = registeredBeforeReject && pending.isRejected && sameError(rootError, expected)
                    && observedProducer && observedHelper
                    && effects(owner, replacement, replaced: replaced, code: code)
                    && chat.presentations == 0 && chat.meTopic == nil
                    && completedOnMain == !background
                pendingChecks[label] = ok
                observations.append(["case": label, "registered_before_reject": registeredBeforeReject,
                    "completed_on_main": completedOnMain, "source_error": details(rootError),
                    "helper_error": details(helperError), "producer_error": details(producerError),
                    "expected": details(expected), "logouts": UiUtils.logouts,
                    "original_reconnects": owner.reconnects, "replacement_reconnects": replacement.reconnects,
                    "replacement_active": replacement.active, "presentations": chat.presentations,
                    "note": caller ? "Caller consumes its terminal failure; no second observer is attached" : "Terminal helper result and reject throw observed separately"])
            }
        }
    }
}
let pendingOutput: [String: Any] = ["level": "actual_Promise_extracted_functions_controlled_Cache_Topic_UI_pending_diagnostics",
    "total": pendingChecks.count, "passed": pendingChecks.values.filter { $0 }.count,
    "checks": pendingChecks, "observations": observations]
let pendingData = try JSONSerialization.data(withJSONObject: pendingOutput, options: [.sortedKeys])
print(String(data: pendingData, encoding: .utf8)!)
exit(pendingChecks.values.allSatisfy { $0 } ? 0 : 1)
