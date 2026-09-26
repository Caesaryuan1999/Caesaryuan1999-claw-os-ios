// Fixture boundaries only. The adapter inserts the exact production functions
// and full PromisedReply.swift; it does not replace or translate their behavior.
import Foundation

public struct ServerMessage {}
public enum TinodeError: Error {
    case serverResponseError(Int, String, String?)
}
enum TopicError: Error { case alreadySubscribed }
public final class TestLog {
    func error(_ format: String, _ values: CVarArg...) {}
}
public final class Tinode {
    var active = true
    var reconnects = 0
    var me: DefaultMeTopic?
    func getMeTopic() -> DefaultMeTopic? { me }
    func reconnectNow(interactively: Bool, reset: Bool) { reconnects += 1 }
}
public final class DefaultMeTopic {
    public final class Listener {}
    final class Builder {
        func withCred() -> Builder { self }
        func withDesc() -> Builder { self }
        func withSub() -> Builder { self }
        func withTags() -> Builder { self }
        func build() -> Int { 0 }
    }
    var listener: Listener?
    var attached = false
    var subscribeCalls = 0
    var reply: () -> PromisedReply<ServerMessage> = { PromisedReply(value: ServerMessage()) }
    var afterReplyBeforeConsumer: (() -> Void)?
    init(tinode: Tinode, l: Listener?) { listener = l; tinode.me = self }
    func metaGetBuilder() -> Builder { Builder() }
    func subscribe(set: Int?, get: Int) -> PromisedReply<ServerMessage> {
        subscribeCalls += 1
        if attached { return PromisedReply(error: TopicError.alreadySubscribed) }
        let result = reply()
        // A reply is already resolved/rejected before thenCatch registration.
        // Deterministically replace the account at exactly this async boundary.
        afterReplyBeforeConsumer?()
        return result
    }
}
enum Cache {
    static var current: Tinode!
    static var tinode: Tinode { current }
    static let log = TestLog()
    static func isCurrent(_ owner: Tinode) -> Bool { current === owner && owner.active }
    @discardableResult static func ifCurrent<T>(_ owner: Tinode, _ body: () -> T) -> T? {
        guard isCurrent(owner) else { return nil }
        return body()
    }
}
enum UiUtils {
    static var logouts = 0
    static func logoutAndRouteToLoginVC(ifCurrent owner: Tinode? = nil) {
        guard owner == nil || Cache.current === owner else { return }
        guard Cache.current.active else { return }
        logouts += 1
        Cache.current.active = false
    }
    // INSERT_PRODUCTION_HELPER
}
final class TestRouter {
    func routeToLogin() { UiUtils.logoutAndRouteToLoginVC() }
}
final class ChatListInteractor {
    var meTopic: DefaultMeTopic?
    var meListener: DefaultMeTopic.Listener?
    var router: TestRouter? = TestRouter()
    var presentations = 0
    func loadAndPresentTopics() { presentations += 1 }
    // INSERT_PRODUCTION_CALLER
}

var checks: [String: Bool] = [:]
func setup(_ code: Int?, text: String = "fixture", replace: Bool = false) -> (Tinode, Tinode) {
    let original = Tinode(), replacement = Tinode()
    Cache.current = original; UiUtils.logouts = 0
    let me = DefaultMeTopic(tinode: original, l: nil)
    if let code = code {
        me.reply = { PromisedReply(error: TinodeError.serverResponseError(code, text, nil)) }
    }
    if replace { me.afterReplyBeforeConsumer = { original.active = false; Cache.current = replacement } }
    return (original, replacement)
}
func rejected(_ result: PromisedReply<ServerMessage>?, code: Int) -> Bool {
    guard let result = result else { return false }
    do { _ = try result.getResult(); return false }
    catch TinodeError.serverResponseError(let observed, _, _) { return observed == code }
    catch { return false }
}
for code in [401, 403, 404] {
    let (owner, _) = setup(code)
    let result = UiUtils.attachToMeTopic(meListener: nil)
    checks["current_\(code)_rejects_and_routes_once"] = rejected(result, code: code) && UiUtils.logouts == 1 && !owner.active
    let (_, replacement) = setup(code, replace: true)
    let stale = UiUtils.attachToMeTopic(meListener: nil)
    checks["stale_\(code)_cannot_logout_replacement"] = rejected(stale, code: code) && UiUtils.logouts == 0 && replacement.active
}
do {
    let (owner, _) = setup(502, text: "cluster unreachable")
    let result = UiUtils.attachToMeTopic(meListener: nil)
    checks["current_502_reconnects_original_and_rejects"] = rejected(result, code: 502) && owner.reconnects == 1 && UiUtils.logouts == 0
    let (old, replacement) = setup(502, text: "cluster unreachable", replace: true)
    let stale = UiUtils.attachToMeTopic(meListener: nil)
    checks["stale_502_does_not_reconnect_any_session"] = rejected(stale, code: 502) && old.reconnects == 0 && replacement.reconnects == 0
    let (other, _) = setup(502, text: "other gateway failure")
    let plain = UiUtils.attachToMeTopic(meListener: nil)
    checks["other_502_does_not_request_reconnect"] = rejected(plain, code: 502) && other.reconnects == 0
}
do {
    _ = setup(500)
    let result = UiUtils.attachToMeTopic(meListener: nil)
    checks["server_failure_is_not_sync_success_or_logout"] = rejected(result, code: 500) && UiUtils.logouts == 0
    _ = setup(nil)
    let current = ChatListInteractor(); current.attachToMeTopic()
    checks["current_success_presents_topics"] = current.presentations == 1 && current.meTopic != nil
    _ = setup(nil, replace: true)
    let stale = ChatListInteractor(); stale.attachToMeTopic()
    checks["stale_success_does_not_present_new_account"] = stale.presentations == 0 && stale.meTopic == nil
    let (_, replacement) = setup(401, replace: true)
    let staleFailure = ChatListInteractor(); staleFailure.attachToMeTopic()
    checks["stale_caller_failure_has_no_new_account_effect"] = staleFailure.presentations == 0 && UiUtils.logouts == 0 && replacement.active
    _ = setup(401)
    let rejectedCurrent = ChatListInteractor(); rejectedCurrent.attachToMeTopic()
    checks["current_failure_does_not_present_success"] = rejectedCurrent.presentations == 0 && UiUtils.logouts == 1
}
do {
    let (owner, _) = setup(nil)
    let originalMe = owner.me!
    originalMe.attached = true
    let caller = ChatListInteractor()
    let listener = DefaultMeTopic.Listener()
    caller.meListener = listener
    caller.attachToMeTopic()
    checks["already_attached_uses_original_me_and_presents"] = caller.meTopic === originalMe && caller.presentations == 1
    checks["already_attached_installs_listener_without_subscribe"] = originalMe.listener === listener && originalMe.subscribeCalls == 0
    caller.attachToMeTopic()
    checks["repeated_attach_is_idempotent"] = originalMe.subscribeCalls == 0 && caller.presentations == 1
}
let output: [String: Any] = ["level": "actual_Production_Promise_and_extracted_functions_with_controlled_Cache_transport_UI", "passed": checks.values.filter { $0 }.count, "total": checks.count, "checks": checks]
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
exit(checks.values.allSatisfy { $0 } ? 0 : 1)
