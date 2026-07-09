//
//  AuthScheme.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public struct AuthScheme {
    enum AuthSchemeError: Error {
        case invalidParams(String)
    }
    static let kLoginBasic = "basic"
    static let kLoginToken = "token"
    static let kLoginReset = "reset"
    static let kLoginCode  = "code"
    static let kLoginIdReset = "idreset"

    let scheme: String
    let secret: String

    init(scheme: String, secret: String) {
        self.scheme = scheme
        self.secret = secret
    }

    static func parse(from str: String?) throws -> AuthScheme? {
        if let data = str {
            let parts = data.split(separator: ":")
            if parts.count == 2 {
                let scheme = String(parts[0])
                if scheme == kLoginBasic || scheme == kLoginToken {
                    return AuthScheme(scheme: scheme, secret: String(parts[1]))
                }
            } else {
                throw AuthSchemeError.invalidParams("Invalid param string \(data)")
            }
        }
        return nil
    }

    static func encodeBasicToken(uname: String, password: String) throws -> String {
        guard !uname.contains(":") else {
            throw AuthSchemeError.invalidParams("invalid user name: \(uname)")
        }
        return (uname + ":" + password).toBase64()!
    }

    static func encodeResetToken(scheme: String, method: String, value: String) throws -> String {
        guard !scheme.contains(":") && !method.contains(":") else {
            throw AuthSchemeError.invalidParams("invalid parameter")
        }
        return "\(scheme):\(method):\(value)".toBase64()!
    }

    static func decodeBasicToken(token: String) throws -> [String] {
        guard let basicToken = token.fromBase64() else {
            throw AuthSchemeError.invalidParams(
                "Failed to decode auth token from base64: \(token)")
        }

        guard let separator = basicToken.firstIndex(of: ":") else {
            throw AuthSchemeError.invalidParams(
                "Invalid basic token string: \(basicToken)")
        }
        let login = basicToken[..<separator]
        let password = basicToken[basicToken.index(after: separator)...]
        if login.isEmpty {
            throw AuthSchemeError.invalidParams(
                "Invalid basic token string: \(basicToken)")
        }
        return [String(login), String(password)]
    }

    static func basicInstance(login: String, password: String) throws -> AuthScheme {
        return AuthScheme(scheme: kLoginBasic,
                          secret: try encodeBasicToken(uname: login, password: password))
    }

    static func tokenInstance(secret: String) -> AuthScheme {
        return AuthScheme(scheme: kLoginToken, secret: secret)
    }

    public static func codeInstance(code: String, method: String, value: String) throws -> AuthScheme {
        // The secret is structured as <code>:<cred_method>:<cred_value>, "123456:email:alice@example.com".
        return AuthScheme(scheme: AuthScheme.kLoginCode, secret: try encodeResetToken(scheme: code, method: method, value: value))
    }

    public static func idResetInstance(accountName: String, userId: String) throws -> AuthScheme {
        guard !accountName.contains(":") && !userId.contains(":") else {
            throw AuthSchemeError.invalidParams("invalid parameter")
        }
        return AuthScheme(scheme: AuthScheme.kLoginIdReset, secret: "\(accountName):\(userId)".toBase64()!)
    }
}

extension String {
    func fromBase64() -> String? {
        guard let data = Data(base64Encoded: self,
                              options: Data.Base64DecodingOptions(
                                rawValue: 0)) else {
            return nil
        }
        return String(data: data as Data, encoding: String.Encoding.utf8)
    }
    func toBase64() -> String? {
        guard let data = self.data(using: String.Encoding.utf8) else {
            return nil
        }
        return data.base64EncodedString(
            options: Data.Base64EncodingOptions(rawValue: 0))
    }
}
