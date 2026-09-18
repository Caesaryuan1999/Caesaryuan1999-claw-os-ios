// Copyright (c) 2026 CLAW OS contributors.
import Foundation

enum ClawAssistantError: Error, Equatable {
    case signInRequired, retired, insecureOrigin, transport, invalidResponse, incompatible
    case responseTooLarge, historyChanged, unavailable
    case server(Int, String)

    var message: String {
        switch self {
        case .signInRequired, .retired: return "请重新登录后查看助手历史。"
        case .insecureOrigin: return "助手需要安全连接，请检查连接设置。"
        case .transport: return "暂时无法连接助手服务，请检查网络后重试。"
        case .invalidResponse, .incompatible: return "助手历史格式暂不兼容，请更新应用后重试。"
        case .responseTooLarge: return "本次历史内容过大，无法完整加载，请稍后重试。"
        case .historyChanged: return "历史已变化，请重新加载。"
        case .unavailable: return "助手历史暂不可用，请稍后重试。"
        case .server(let status, let code):
            if status == 401 { return "登录已失效，请重新登录后查看助手历史。" }
            if status == 403 { return "当前账号无权使用助手历史。" }
            if status == 404 { return "暂时无法访问这段对话，请重新加载历史。" }
            if status == 410 { return "这段对话已删除。" }
            if code == "provider_not_configured" { return "服务暂未开通。" }
            if status == 503 { return "助手历史暂不可用，请稍后重试。" }
            return "暂时无法完成操作，请稍后重试。"
        }
    }
}

enum ClawAssistantWire {
    static func uuid(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                    options: .regularExpression) != nil
    }
    static func decimal(_ value: String) -> Bool {
        let maximum = "9223372036854775807"
        return value.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil &&
            (value.count < maximum.count || (value.count == maximum.count && value <= maximum))
    }
    static func less(_ a: String, _ b: String) -> Bool {
        a.count == b.count ? a < b : a.count < b.count
    }
    static func date(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value)
    }
}

protocol ClawAssistantValidated: Decodable { func validate() throws }

struct ClawAssistantCapabilities: ClawAssistantValidated {
    struct Feature: Decodable { let available: Bool; let reason: String? }
    struct Limits: Decodable {
        let body_bytes: Int
        let text_bytes: Int
        let page_size_max: Int
    }
    let version: String
    let history: Feature
    let generation: Feature
    let stream: Feature
    let limits: Limits
    let run_protocol: String?
    let message_states: ClawAssistantMessageStates?
    private enum CodingKeys: String, CodingKey {
        case version, history, generation, stream, limits, run_protocol, message_states
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        history = try values.decode(Feature.self, forKey: .history)
        generation = try values.decode(Feature.self, forKey: .generation)
        stream = try values.decode(Feature.self, forKey: .stream)
        limits = try values.decode(Limits.self, forKey: .limits)
        // Unknown B fields must not break the original A-only history reader.
        run_protocol = try? values.decode(String.self, forKey: .run_protocol)
        message_states = try? values.decode(ClawAssistantMessageStates.self, forKey: .message_states)
    }
    func validate() throws {
        guard version == "claw-ai-v1", limits.body_bytes == 65536,
              limits.text_bytes == 32000, limits.page_size_max == 100 else {
            throw ClawAssistantError.incompatible
        }
        // A callers do not use the B fields to enable generation.
    }
}

// B is explicitly negotiated. A message decoding and the A UI remain unchanged.
struct ClawAssistantMessageStates: Decodable {
    let user: [String]
    let assistant: [String]
}

extension ClawAssistantCapabilities {
    func validateRuns() throws {
        try validate()
        guard run_protocol == "claw-ai-run-v1",
              let states = message_states,
              Set(states.user) == Set(["partial", "interrupted", "completed"]), states.user.count == 3,
              Set(states.assistant) == Set(["partial", "completed", "stopped", "interrupted", "failed"]),
              states.assistant.count == 5 else { throw ClawAssistantError.incompatible }
    }
}

struct ClawAssistantRunInput: Encodable, Equatable {
    let request_id: String
    let text: String
    let retry_of: String?
    func body() throws -> Data {
        guard ClawAssistantWire.uuid(request_id), retry_of.map(ClawAssistantWire.uuid) ?? true,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 32000 else { throw ClawAssistantError.invalidResponse }
        // Validate emptiness only: the transmitted/hash input is the original text.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 65536 else { throw ClawAssistantError.responseTooLarge }
        return data
    }
}

struct ClawAssistantConversationPageValue: ClawAssistantValidated {
    let value: ClawAssistantConversation
    init(from decoder: Decoder) throws { value = try ClawAssistantConversation(from: decoder) }
    func validate() throws { try value.validate() }
}

enum ClawAssistantRunWire {
    static let active = Set(["queued", "running"])
    static let terminal = Set(["completed", "stopped", "interrupted", "failed"])
    static let reasons = Set(["", "user_stop", "process_lost", "auth_revoked", "provider_error",
                              "output_limit", "event_limit", "shutdown", "legacy_history"])
    static let outputLimit = 256 * 1024
    static func next(_ value: String) -> String? {
        guard ClawAssistantWire.decimal(value), let number = Int64(value), number < Int64.max else { return nil }
        return String(number + 1)
    }
}

struct ClawAssistantRunReceipt: ClawAssistantValidated, Equatable {
    let legacy: Bool?
    let conversation_id: String
    let run_id: String
    let request_id: String
    let question_message_id: String
    let answer_message_id: String
    let state: String
    let last_event: String
    let revision: String
    let created_at: String
    var isLegacy: Bool { legacy == true }
    var isTerminal: Bool { ClawAssistantRunWire.terminal.contains(state) }
    func validate() throws {
        guard ClawAssistantWire.uuid(conversation_id), ClawAssistantWire.uuid(run_id),
              ClawAssistantWire.uuid(request_id), ClawAssistantWire.decimal(last_event),
              ClawAssistantWire.decimal(revision), ClawAssistantWire.date(created_at) != nil,
              ClawAssistantRunWire.active.contains(state) || isTerminal,
              ClawAssistantWire.uuid(question_message_id) || (isLegacy && question_message_id.isEmpty),
              ClawAssistantWire.uuid(answer_message_id) || (isLegacy && answer_message_id.isEmpty),
              !isLegacy || isTerminal else { throw ClawAssistantError.invalidResponse }
    }
}

struct ClawAssistantRunSnapshot: ClawAssistantValidated, Equatable {
    let receipt: ClawAssistantRunReceipt
    let text: String
    let updated_at: String
    let reason: String
    private enum CodingKeys: String, CodingKey { case text, updated_at, reason }
    init(from decoder: Decoder) throws {
        receipt = try ClawAssistantRunReceipt(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        updated_at = try values.decode(String.self, forKey: .updated_at)
        reason = try values.decode(String.self, forKey: .reason)
    }
    func validate() throws {
        try receipt.validate()
        guard text.utf8.count <= ClawAssistantRunWire.outputLimit,
              ClawAssistantWire.date(updated_at) != nil, ClawAssistantRunWire.reasons.contains(reason),
              receipt.isTerminal || reason.isEmpty else { throw ClawAssistantError.invalidResponse }
    }
}

struct ClawAssistantRunEvent: ClawAssistantValidated, Equatable {
    let id: String
    let kind: String
    let delta: String?
    let state: String?
    let reason: String?
    let revision: String
    func validate() throws {
        guard ClawAssistantWire.decimal(id), id != "0", ClawAssistantWire.decimal(revision) else {
            throw ClawAssistantError.invalidResponse
        }
        switch kind {
        case "accepted":
            guard state == "queued", delta == nil, reason == nil else { throw ClawAssistantError.invalidResponse }
        case "delta":
            guard let delta = delta, !delta.isEmpty, delta.utf8.count <= 4096,
                  state == nil, reason == nil else { throw ClawAssistantError.invalidResponse }
        case "terminal":
            guard let state = state, ClawAssistantRunWire.terminal.contains(state), delta == nil,
                  reason.map({ ClawAssistantRunWire.reasons.contains($0) }) ?? true else {
                throw ClawAssistantError.invalidResponse
            }
        default: throw ClawAssistantError.incompatible
        }
    }
}

struct ClawAssistantRunEvents: ClawAssistantValidated {
    let conversation_id: String
    let run_id: String
    let items: [ClawAssistantRunEvent]
    let next_after_event: String
    let last_event: String
    let state: String
    func validate() throws {
        guard ClawAssistantWire.uuid(conversation_id), ClawAssistantWire.uuid(run_id), items.count <= 100,
              ClawAssistantWire.decimal(last_event),
              ClawAssistantRunWire.active.contains(state) || ClawAssistantRunWire.terminal.contains(state),
              next_after_event.isEmpty || next_after_event == items.last?.id else { throw ClawAssistantError.invalidResponse }
        var previous: String?
        for item in items {
            try item.validate()
            guard !ClawAssistantWire.less(last_event, item.id),
                  previous.map({ ClawAssistantRunWire.next($0) == item.id }) ?? true else {
                throw ClawAssistantError.invalidResponse
            }
            previous = item.id
        }
        if let last = items.last {
            guard (next_after_event.isEmpty ? last.id == last_event : ClawAssistantWire.less(last.id, last_event)) else {
                throw ClawAssistantError.invalidResponse
            }
        }
    }
}

struct ClawAssistantConversation: Decodable, Equatable {
    let conversation_id: String
    let revision: String
    let deleted: Bool
    let title: String?
    let created_at: String?
    let updated_at: String?
    var displayTitle: String {
        guard let title = title, !title.isEmpty else { return "新对话" }
        return title
    }

    func validate() throws {
        guard ClawAssistantWire.uuid(conversation_id), ClawAssistantWire.decimal(revision) else {
            throw ClawAssistantError.invalidResponse
        }
        if deleted {
            guard title == nil, created_at == nil, updated_at == nil else {
                throw ClawAssistantError.invalidResponse
            }
        } else {
            guard title != nil, let created = created_at, let updated = updated_at,
                  ClawAssistantWire.date(created) != nil, ClawAssistantWire.date(updated) != nil else {
                throw ClawAssistantError.invalidResponse
            }
        }
    }
}

struct ClawAssistantConversationPage: ClawAssistantValidated {
    let items: [ClawAssistantConversation]
    let snapshot_revision: String
    let next_cursor: String
    func validate() throws {
        guard ClawAssistantWire.decimal(snapshot_revision), items.count <= 100,
              next_cursor.isEmpty || ClawAssistantWire.uuid(next_cursor) else {
            throw ClawAssistantError.invalidResponse
        }
        var previous = ""
        for item in items {
            try item.validate()
            guard item.conversation_id > previous,
                  !ClawAssistantWire.less(snapshot_revision, item.revision) else {
                throw ClawAssistantError.invalidResponse
            }
            previous = item.conversation_id
        }
        guard next_cursor.isEmpty || next_cursor == items.last?.conversation_id else {
            throw ClawAssistantError.invalidResponse
        }
    }
}

struct ClawAssistantMessage: Decodable, Equatable {
    let message_id: String
    let conversation_id: String
    let run_id: String
    let seq: String
    let role: String
    let text: String
    let state: String
    let created_at: String
    let updated_at: String
    var stateText: String? {
        guard role == "assistant" else { return nil }
        return state == "partial" ? "回答尚未完成" : "回答已中断"
    }
    func validate() throws {
        guard ClawAssistantWire.uuid(message_id), ClawAssistantWire.uuid(conversation_id),
              run_id.isEmpty || ClawAssistantWire.uuid(run_id), ClawAssistantWire.decimal(seq),
              seq != "0", ClawAssistantWire.date(created_at) != nil,
              ClawAssistantWire.date(updated_at) != nil else { throw ClawAssistantError.invalidResponse }
        guard ["user", "assistant"].contains(role), ["partial", "interrupted"].contains(state) else {
            throw ClawAssistantError.incompatible
        }
    }
}

struct ClawAssistantMessagePage: ClawAssistantValidated {
    let conversation_id: String
    let items: [ClawAssistantMessage]
    let snapshot_revision: String
    let next_after_seq: String
    func validate() throws {
        guard ClawAssistantWire.uuid(conversation_id), ClawAssistantWire.decimal(snapshot_revision),
              items.count <= 100, next_after_seq.isEmpty || ClawAssistantWire.decimal(next_after_seq) else {
            throw ClawAssistantError.invalidResponse
        }
        var previous = "0"
        var ids = Set<String>()
        for item in items {
            try item.validate()
            guard item.conversation_id == conversation_id, ClawAssistantWire.less(previous, item.seq),
                  ids.insert(item.message_id).inserted else { throw ClawAssistantError.invalidResponse }
            previous = item.seq
        }
        guard next_after_seq.isEmpty || next_after_seq == items.last?.seq else {
            throw ClawAssistantError.invalidResponse
        }
    }
}

struct ClawAssistantDeleteReceipt: ClawAssistantValidated {
    let conversation_id: String
    let deleted: Bool
    let revision: String
    func validate() throws {
        guard ClawAssistantWire.uuid(conversation_id), deleted, ClawAssistantWire.decimal(revision) else {
            throw ClawAssistantError.invalidResponse
        }
    }
}
