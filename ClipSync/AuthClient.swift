import Foundation

// ============================================================
// AuthClient：用用户名 + 密码换 token
//
// 取代原来"手填 token"的流程。服务端行为：
//   - 当前账号没有客户端在线 → 新签发 token
//   - 已有客户端在线 → 返回同一个 token（reused = true）
// 所以两端各自登录同一账号，就会自动落到同一个同步分组里。
// ============================================================

/// 登录成功后的会话信息
struct AuthSession: Codable, Equatable {
    var token: String
    var userID: Int64
    var username: String
    var expiresAt: String?
    /// true = 复用了已在线客户端的 token
    var reused: Bool
    /// 服务端是否强制要求端到端加密
    var e2eeRequired: Bool
    var onlineDevices: Int
}

enum AuthError: LocalizedError {
    case badURL(String)
    case network(String)
    case server(status: Int, message: String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s):            return "服务器地址不合法：\(s)"
        case .network(let m):           return "网络错误：\(m)"
        case .server(_, let m):         return m
        case .decode(let m):            return "响应解析失败：\(m)"
        }
    }
}

final class AuthClient {
    static let shared = AuthClient()
    private init() {}

    /// 把 ws:// / wss:// 的服务器地址转成 http:// / https:// 的 REST 基址。
    /// 设置页里填的是 WebSocket 地址，认证接口走同一个端口的 HTTP。
    static func httpBase(from serverURL: String) -> String {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if s.hasPrefix("wss://") { return "https://" + s.dropFirst("wss://".count) }
        if s.hasPrefix("ws://")  { return "http://"  + s.dropFirst("ws://".count) }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
        return "http://" + s
    }

    /// POST /auth/login
    func login(server: String, username: String, password: String) async throws -> AuthSession {
        let body = ["username": username, "password": password]
        let json = try await post(server: server, path: "/auth/login", body: body, token: nil)

        guard let token = json["token"] as? String, !token.isEmpty else {
            throw AuthError.decode("响应缺少 token")
        }
        return AuthSession(
            token: token,
            userID: (json["user_id"] as? NSNumber)?.int64Value ?? 0,
            username: json["username"] as? String ?? username,
            expiresAt: json["expires_at"] as? String,
            reused: json["reused"] as? Bool ?? false,
            e2eeRequired: json["e2ee_required"] as? Bool ?? false,
            onlineDevices: (json["online_devices"] as? NSNumber)?.intValue ?? 0
        )
    }

    /// GET /auth/session —— 启动时用它确认本地 token 还有效
    func checkSession(server: String, token: String) async throws -> Bool {
        let base = Self.httpBase(from: server)
        guard let url = URL(string: base + "/auth/session") else {
            throw AuthError.badURL(server)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
    }

    /// POST /auth/logout —— 作废服务端会话
    func logout(server: String, token: String) async throws {
        _ = try await post(server: server, path: "/auth/logout", body: [:], token: token)
    }

    // MARK: - 内部

    private func post(server: String, path: String,
                      body: [String: String], token: String?) async throws -> [String: Any] {
        let base = Self.httpBase(from: server)
        guard let url = URL(string: base + path) else { throw AuthError.badURL(server) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let msg = json["error"] as? String ?? "服务端返回 \(status)"
            throw AuthError.server(status: status, message: msg)
        }
        return json
    }
}
