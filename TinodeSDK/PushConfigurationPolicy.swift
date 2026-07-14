//
//  PushConfigurationPolicy.swift
//  TinodeSDK
//

import Foundation

public enum PushConfigurationPolicy {
    private static let requiredStringKeys = [
        "API_KEY",
        "BUNDLE_ID",
        "GCM_SENDER_ID",
        "GOOGLE_APP_ID",
        "PROJECT_ID"
    ]

    public static func isUsable(_ values: [String: Any]) -> Bool {
        guard boolValue(values["IS_GCM_ENABLED"]) else {
            return false
        }

        let strings = requiredStringKeys.compactMap { key -> String? in
            guard let value = values[key] as? String else {
                return nil
            }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
        guard strings.count == requiredStringKeys.count else {
            return false
        }

        guard !strings.contains(where: { $0.localizedCaseInsensitiveContains("placeholder") }) else {
            return false
        }

        guard let senderId = values["GCM_SENDER_ID"] as? String,
              senderId.contains(where: { $0 != "0" }),
              let appId = values["GOOGLE_APP_ID"] as? String,
              appId.contains(where: { $0 != "0" && $0 != ":" }) else {
            return false
        }
        return true
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return false
    }
}
