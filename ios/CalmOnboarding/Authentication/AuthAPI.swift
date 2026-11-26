import Foundation
import Security

struct AuthUser: Decodable {
    let id: String
    let firstName: String
    let lastName: String?
    let email: String

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct AuthSession: Decodable {
    let token: String
    let user: AuthUser
}

struct PendingRegistration: Decodable {
    let status: String
    let email: String?
    let debugCode: String?

    enum CodingKeys: String, CodingKey {
        case status, email
        case debugCode = "debug_code"
    }
}

struct APIMessage: Decodable {
    let error: String
    let message: String
}

enum AuthAPIError: LocalizedError {
    case invalidAddress
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Укажите адрес сервера в API_BASE_URL."
        case .server(let message): return message
        case .invalidResponse: return "Не удалось прочитать ответ сервера."
        }
    }
}

enum AuthAPI {
    private static var baseURL: URL? {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else {
            return nil
        }
        return URL(string: address)
    }

    private static func post<Response: Decodable>(_ path: String, body: [String: String]) async throws -> Response {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else {
            throw AuthAPIError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = try? JSONDecoder().decode(APIMessage.self, from: data)
            throw AuthAPIError.server(message?.message ?? "Сервер временно недоступен")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthAPIError.invalidResponse
        }
    }

    static func register(firstName: String, lastName: String, email: String, password: String) async throws -> PendingRegistration {
        try await post("/v1/auth/register", body: [
            "first_name": firstName,
            "last_name": lastName,
            "email": email,
            "password": password,
        ])
    }

    static func verify(email: String, code: String) async throws -> AuthSession {
        try await post("/v1/auth/verify-email", body: ["email": email, "code": code])
    }

    static func resend(email: String) async throws -> PendingRegistration {
        try await post("/v1/auth/resend-code", body: ["email": email])
    }

    static func login(email: String, password: String) async throws -> AuthSession {
        try await post("/v1/auth/login", body: ["email": email, "password": password])
    }

    static func logout(token: String) async {
        guard let baseURL, let url = URL(string: "/v1/auth/logout", relativeTo: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }
}

enum SessionTokenStore {
    private static let account = "calm.auth.session"

    @discardableResult
    static func save(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = Data(token.utf8)
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
