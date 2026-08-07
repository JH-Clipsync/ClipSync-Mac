import Foundation
import Combine

// ============================================================
// WSClient：与服务器的 WebSocket 长连接
// - 连接 / 断开 / 自动重连 / 心跳 ping
// - 收消息 → 更新 lastMessage & history
// - state (.disconnected/.connecting/.connected) 用 @Published 暴露给 UI
// - 只有第一次 ping 成功后才置 .connected，避免"闪现已连接"的假象
// ============================================================

final class WSClient: ObservableObject {
    static let shared = WSClient()

    enum ConnectionState: String { case connecting, connected, disconnected }

    @Published var state: ConnectionState = .disconnected
    @Published var lastMessage: SyncMessage?
    @Published var history: [SyncMessage] = []

    /// 最近一次连接被服务端拒绝的原因（token 失效时提示用户重新登录）
    @Published var authError: String?

    /// 收到了解不开的密文（两端同步密码不一致）时置位，UI 据此提示
    @Published var decryptFailure: String?

    /// 本机设备 ID：首次生成后存进 UserDefaults，之后一直复用。
    ///
    /// 不能每次启动都换：服务端按 device_id 在 Redis 里登记在线设备，ID 一直变
    /// 会堆出一串再也不会下线的幽灵设备，在线数虚高，进而影响登录时"复用还是
    /// 新签发 Token"的判断。
    let deviceID: String = {
        let key = "deviceID"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let fresh = "mac-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var isRunning = false
    private var currentServer = ""
    private var currentToken = ""

    /// 用户主动断开时置 true，scheduleReconnect 据此跳过自动重连
    private var userInitiatedDisconnect = false
    /// 被服务端踢下线（密码重置/封禁）时置 true，阻止自动重连
    private var wasKicked = false
    /// token 失效后重新登录的次数，超过 1 次不再重试（密码已被改）
    private var authRetryCount = 0
    /// 自动重连尝试次数（指数退避：2, 4, 8, 16, 30, 30...）
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30

    /// 最短 "连接中" 显示时间：进入 connecting 后至少停留 1.5s 才允许切回 disconnected
    private var connectingSince: Date?
    private let minConnectingDuration: TimeInterval = 1.5

    private init() {}

    // MARK: - 连接控制

    /// 统一的连接入口：没有 token 就先用账号密码换一个，再建立 WebSocket。
    ///
    /// 这样界面上只需要一个「连接」按钮，不必让用户先点「登录」再点「连接」。
    /// 只在本地没有 token 时才打 /auth/login，避免每次重连都去撞登录限流；
    /// token 失效由 WS 握手的 401 触发重新换取。
    @MainActor
    func connect(settings: SettingsStore) async {
        // 用户可能只填了 host:port，这里统一补上 ws:// 前缀
        let server = ServerAddress.normalize(settings.serverURL)
        guard !server.isEmpty else {
            authError = "请先填写服务器地址，例如 192.168.1.10:8080"
            return
        }

        if !settings.token.isEmpty {
            start(server: server, token: settings.token)
            return
        }
        guard settings.hasCredentials else {
            authError = settings.username.isEmpty
                ? "请填写用户名（账号由管理员创建）"
                : "请填写密码"
            return
        }

        state = .connecting
        authError = nil
        do {
            let session = try await AuthClient.shared.login(
                server: server,
                username: settings.username,
                password: settings.password
            )
            settings.token = session.token
            settings.username = session.username
            NSLog("[WS] 🔑 连接前自动登录成功：reused=\(session.reused) 在线 \(session.onlineDevices) 台")
            start(server: server, token: session.token)
        } catch {
            state = .disconnected
            // 区分"服务端不认这套账密"和"根本没连上服务端"，提示才有指导意义
            authError = Self.describeLoginFailure(error)
            NSLog("[WS] ✗ 自动登录失败: \(error.localizedDescription)")
        }
    }

    /// 把登录异常翻成一句用户能照着处理的话
    static func describeLoginFailure(_ error: Error) -> String {
        guard let authError = error as? AuthError else {
            return "连接失败：\(error.localizedDescription)"
        }
        switch authError {
        case .badURL(let s):
            return "服务器地址不合法：\(s)"
        case .network(let m):
            return "连不上服务器（\(m)），请检查地址、网络和服务是否已启动"
        case .server(let status, let message):
            if status == 401 || status == 403 {
                return "登录失败：\(message)，请检查用户名和密码"
            }
            return "服务端拒绝登录：\(message)"
        case .decode(let m):
            return "服务端响应异常：\(m)"
        }
    }

    /// token 失效后重新换一个并接着连。密码存在本地，用户无需干预。
    ///
    /// 这里不复用 [connect]，因为 connect 的登录失败统一走 [describeLoginFailure]，
    /// 会把"密码已被管理端重置"也提示成"请检查用户名和密码"，让人误以为是自己填错了。
    /// 重新登录失败要单独区分：服务端拒绝（401/403）= 密码已失效；其他 = 网络问题。
    @MainActor
    func reauthenticate(settings: SettingsStore) async {
        let server = ServerAddress.normalize(settings.serverURL)
        guard !server.isEmpty else { return }
        settings.token = ""
        state = .connecting
        authError = nil
        connectingSince = Date()
        do {
            let session = try await AuthClient.shared.login(
                server: server,
                username: settings.username,
                password: settings.password
            )
            settings.token = session.token
            NSLog("[WS] 🔑 重新登录成功，继续连接")
            start(server: server, token: session.token)
        } catch let error as AuthError {
            state = .disconnected
            connectingSince = nil
            switch error {
            case .server(let status, _):
                wasKicked = true
                if status == 401 || status == 403 {
                    // 服务端不认这套账密 → 密码已被管理端重置
                    authError = "密码已失效，请重新登录"
                    NSLog("[WS] 🔒 重新登录被拒（\(status)），密码已变更，不再重连")
                } else {
                    authError = "登录失败：\(error.errorDescription ?? "未知错误")"
                    NSLog("[WS] 🔒 重新登录被拒（\(status)），不再重连")
                }
            default:
                // 网络/解析类错误：提示用户，但不置 wasKicked，允许后续手动重试
                authError = Self.describeLoginFailure(error)
                NSLog("[WS] ✗ 重新登录失败: \(error.localizedDescription)")
            }
        } catch {
            state = .disconnected
            connectingSince = nil
            authError = Self.describeLoginFailure(error)
            NSLog("[WS] ✗ 重新登录失败: \(error.localizedDescription)")
        }
    }

    /// 启动连接。相同 server + token + isRunning 时直接跳过（防抖）
    func start(server: String, token: String) {
        if isRunning && server == currentServer && token == currentToken {
            NSLog("[WS] start 跳过：已在连接同一 server")
            return
        }
        stop()
        guard !token.isEmpty else {
            NSLog("[WS] start 失败：token 为空")
            return
        }
        guard let url = URL(string: "\(server)/ws?token=\(token)&device=\(deviceID)&role=pc") else {
            NSLog("[WS] start 失败：URL 非法 \(server)")
            return
        }
        NSLog("[WS] → 正在连接 \(url.absoluteString)")

        isRunning = true
        currentServer = server
        currentToken = token
        userInitiatedDisconnect = false
        wasKicked = false
        authRetryCount = 0
        reconnectAttempts = 0
        state = .connecting
        authError = nil
        connectingSince = Date()

        session = URLSession(configuration: .default)
        task = session?.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
        startPing()
        warmUpEncryptionKey()
    }

    /// 预热加密密钥。
    ///
    /// 派生一次要跑 20 万轮 PBKDF2，若留到第一条消息发送时才算，那条消息会
    /// 明显延迟。PayloadCipher 内部按密码缓存，所以先算一次就够了。
    private func warmUpEncryptionKey() {
        let password = SettingsStore.shared.effectiveSyncPassword
        guard !password.isEmpty else { return }
        Task.detached(priority: .utility) {
            _ = PayloadCipher.currentKey(password: password)
            NSLog("[WS] 🔑 端到端加密密钥已就绪")
        }
    }

    func stop() {
        isRunning = false
        currentServer = ""
        currentToken = ""
        reconnectTimer?.invalidate(); reconnectTimer = nil
        pingTimer?.invalidate();      pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    /// 用户主动断开：连 stop 一起把失败提示清掉，"手动断开"不是错误
    @MainActor
    func disconnect() {
        userInitiatedDisconnect = true
        wasKicked = false
        reconnectTimer?.invalidate(); reconnectTimer = nil
        stop()
        authError = nil
        decryptFailure = nil
    }

    // MARK: - 发送

    func sendClipboardText(_ text: String) {
        let payload = MessagePayload(
            text: text, mime: "text/plain", data: nil,
            preview: String(text.prefix(50)), kind: MessageKind.text
        )
        send(SyncMessage(
            id: UUID().uuidString, type: MessageType.clipboard,
            from: deviceID, to: "*",
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        ))
    }

    func sendClipboardImage(base64: String, mime: String = "image/png") {
        let payload = MessagePayload(
            text: nil, mime: mime, data: base64,
            preview: "[图片]", kind: MessageKind.image
        )
        send(SyncMessage(
            id: UUID().uuidString, type: MessageType.clipboard,
            from: deviceID, to: "*",
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        ))
    }

    private func send(_ msg: SyncMessage) {
        // 发送前按需加密：settings.encryptionActive 时把 payload 换成信封
        var outgoing = msg
        let settings = SettingsStore.shared
        let syncPassword = settings.effectiveSyncPassword
        if !syncPassword.isEmpty {
            outgoing.payload = PayloadCipher.encrypt(msg.payload, password: syncPassword)
        }
        guard let data = try? JSONEncoder().encode(outgoing),
              let text = String(data: data, encoding: .utf8) else {
            NSLog("[WS] 发送失败：编码错误")
            return
        }
        task?.send(.string(text)) { err in
            if let err = err {
                NSLog("[WS] 发送失败: \(err.localizedDescription)")
            } else {
                NSLog("[WS] ↑ 已发送 \(outgoing.type)\(syncPassword.isEmpty ? "" : " (已加密)")")
            }
        }
    }

    // MARK: - 接收

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self, self.isRunning else { return }
            switch result {
            case .failure(let err):
                NSLog("[WS] ✗ 接收错误: \(err.localizedDescription)")
                // 被踢下线后 isRunning=false，不再重连
                guard self.isRunning else { return }
                if !self.noteAuthFailureIfNeeded(err) {
                    self.scheduleReconnect(reason: Self.describeSocketFailure(err))
                }
            case .success(let msg):
                switch msg {
                case .string(let text): self.handle(text: text)
                case .data(let data):
                    if let s = String(data: data, encoding: .utf8) { self.handle(text: s) }
                @unknown default: break
                }
                if self.isRunning { self.receiveLoop() }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else {
            NSLog("[WS] ✗ 转换 UTF-8 失败: \(text.prefix(200))")
            return
        }
        let decoder = JSONDecoder()
        // 允许服务端额外加字段，不因未知字段 decode 失败丢整条消息
        guard let msg = try? decoder.decode(SyncMessage.self, from: data) else {
            NSLog("[WS] ✗ 解析失败: \(text.prefix(200))")
            return
        }
        // 过滤自己发的消息（避免自己收到自己）
        if msg.from == deviceID {
            NSLog("[WS] ⏭ 跳过本人消息 from=\(msg.from)")
            return
        }

        // 服务端踢下线通知：主动断开，不重连，提示用户
        if msg.type == MessageType.serverKick {
            NSLog("[WS] 👢 收到服务端踢下线通知")
            // 必须同步设置，否则紧随其后的 .failure 回调会在
            // main.async 之前进入 scheduleReconnect，导致重连
            self.wasKicked = true
            self.isRunning = false
            DispatchQueue.main.async {
                self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.pingTimer?.invalidate(); self.pingTimer = nil
                self.state = .disconnected
                self.authError = "密码已被管理员重置，请重新登录"
            }
            return
        }

        // 密文消息：用本机同步密码解开；解不开就只提示，不把密文塞进历史
        var resolved = msg
        let settings = SettingsStore.shared
        switch PayloadCipher.decrypt(msg.payload, password: settings.effectiveSyncPassword) {
        case .plaintext:
            NSLog("[WS] ↓ 收到 \(msg.type) text=\((resolved.payload.text ?? "").prefix(60))")
        case .decrypted(let plain):
            resolved.payload = plain
            NSLog("[WS] ↓ 收到 \(msg.type) (已解密) text=\((plain.text ?? "").prefix(60))")
        case .failed(let fingerprint):
            let localFP = PayloadCipher.fingerprint(password: settings.effectiveSyncPassword)
                ?? "未设置"
            NSLog("[WS] ✗ 解密失败 对端 key=\(fingerprint) 本机 key=\(localFP)")
            DispatchQueue.main.async {
                self.state = .connected
                self.decryptFailure = settings.e2eeEnabled
                    ? "收到无法解密的消息：请确认两端「同步密码」填写一致"
                    : "收到加密消息但本机未开启端到端加密，请在设置里打开"
            }
            return
        }

        DispatchQueue.main.async {
            self.state = .connected
            self.decryptFailure = nil
            self.history.insert(resolved, at: 0)
            if self.history.count > 200 { self.history.removeLast() }
            // 关键：即使内容相同，也要强制触发 Toast。
            // 用"先置 nil 再赋值"绕过 @Published 的 Equatable 去重，
            // 否则同一手机号的连续验证码，第二条不会弹通知。
            self.lastMessage = nil
            self.lastMessage = resolved
        }
    }

    // MARK: - 心跳 / 重连

    private func startPing() {
        pingTimer?.invalidate()
        sendPingOnce()  // 立即 ping 一次确认连接
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.sendPingOnce()
        }
        RunLoop.main.add(pingTimer!, forMode: .common)
    }

    private func sendPingOnce() {
        task?.sendPing { [weak self] err in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                if let err = err {
                    NSLog("[WS] ⚠ ping 失败: \(err.localizedDescription)")
                    if !self.noteAuthFailureIfNeeded(err) {
                        if self.state != .disconnected {
                            self.scheduleReconnect(reason: Self.describeSocketFailure(err))
                        }
                    }
                } else if self.state != .connected {
                    self.state = .connected
                    self.connectingSince = nil
                    self.reconnectAttempts = 0
                    self.authRetryCount = 0
                    // 连上了，之前的失败提示就该消失
                    self.authError = nil
                    NSLog("[WS] 🟢 已连接服务器")
                }
            }
        }
    }

    // MARK: - 鉴权失败识别

    /// 服务端在 token 失效时用 HTTP 401 拒绝 WS 升级，URLSession 会把它们
    /// 报成握手错误。这里把它翻译成一句用户能看懂的提示。
    /// 返回 true 表示已识别为鉴权失败并自行触发了重新登录，调用方无需再 scheduleReconnect。
    @discardableResult
    private func noteAuthFailureIfNeeded(_ error: Error) -> Bool {
        let ns = error as NSError
        let desc = ns.localizedDescription
        let looksLikeAuth = desc.contains("401") || desc.contains("Unauthorized")
            || ns.code == 401
        guard looksLikeAuth else { return false }
        // 已被服务端踢下线，不再尝试重新登录
        if wasKicked { return true }
        // 只允许重新登录 1 次，超过说明密码已被改
        authRetryCount += 1
        if authRetryCount > 1 {
            NSLog("[WS] 🔒 重新登录仍失败（第\(authRetryCount)次），密码可能已被重置")
            DispatchQueue.main.async {
                self.wasKicked = true
                self.authError = "密码已失效，请重新登录"
            }
            return true
        }
        DispatchQueue.main.async {
            NSLog("[WS] 🔒 token 已失效，尝试用已保存的账号密码重新换取（第\(self.authRetryCount)次）")
            let settings = SettingsStore.shared
            guard settings.hasCredentials else {
                self.authError = "登录已失效，请到设置里填写账号密码"
                return
            }
            self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
            self.stop()
            Task { await self.reauthenticate(settings: settings) }
        }
        return true
    }

    /// 把 URLSession 的底层错误翻成用户能看懂的一句话
    static func describeSocketFailure(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else {
            return "连接中断：\(ns.localizedDescription)"
        }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet:
            return "网络不可用，请检查本机网络连接"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "找不到服务器，请检查服务器地址"
        case NSURLErrorCannotConnectToHost:
            return "服务器拒绝连接，请确认地址、端口和服务是否已启动"
        case NSURLErrorTimedOut:
            return "连接服务器超时，请检查网络或服务器状态"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "TLS 握手失败，请确认服务器证书配置"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接已断开，请重新连接"
        default:
            return "连接失败：\(ns.localizedDescription)"
        }
    }

    private func scheduleReconnect(reason: String? = nil) {
        DispatchQueue.main.async {
            // 手动断开不重连
            guard !self.userInitiatedDisconnect else {
                NSLog("[WS] 🔴 用户已手动断开，不自动重连")
                return
            }
            // 被服务端踢下线不重连
            guard !self.wasKicked else {
                NSLog("[WS] 🔴 被服务端踢下线，不自动重连")
                return
            }

            // 清理当前连接资源，但保留 server/token 供重连使用
            self.isRunning = false
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.pingTimer?.invalidate(); self.pingTimer = nil

            // 保证 "连接中" 至少显示 minConnectingDuration
            let minDelay: TimeInterval = {
                guard let started = self.connectingSince else { return 0 }
                let elapsed = Date().timeIntervalSince(started)
                return max(0, self.minConnectingDuration - elapsed)
            }()

            // 指数退避：2, 4, 8, 16, 30, 30...
            let backoff = min(pow(2.0, Double(self.reconnectAttempts)), self.maxReconnectDelay)
            self.reconnectAttempts += 1
            let delay = max(backoff, minDelay)

            self.state = .disconnected
            self.connectingSince = nil
            if let reason, self.authError == nil {
                self.authError = reason
            }

            let server = self.currentServer
            let token = self.currentToken
            NSLog("[WS] 🔄 \(Int(delay))秒后自动重连（第\(self.reconnectAttempts)次）→ \(server)")

            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, !self.userInitiatedDisconnect else { return }
                guard !server.isEmpty, !token.isEmpty else {
                    NSLog("[WS] ✗ 重连失败：server 或 token 为空")
                    return
                }
                NSLog("[WS] 🔄 正在自动重连 → \(server)")
                self.start(server: server, token: token)
            }
            RunLoop.main.add(self.reconnectTimer!, forMode: .common)
        }
    }
}
