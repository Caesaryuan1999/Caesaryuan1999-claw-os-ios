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
        value.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil && value.count <= 20
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
    func validate() throws {
        guard version == "claw-ai-v1", limits.body_bytes == 65536,
              limits.text_bytes == 32000, limits.page_size_max == 100 else {
            throw ClawAssistantError.incompatible
        }
        // Even a future server advertising generation=true cannot enable B in this client.
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
