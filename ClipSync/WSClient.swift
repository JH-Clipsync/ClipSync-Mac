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

    /// 本机设备 ID（每次启动生成一次）
    let deviceID: String = "mac-\(UUID().uuidString.prefix(8))"

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    private var isRunning = false
    private var currentServer = ""
    private var currentToken = ""

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
        let server = settings.serverURL

        if !settings.token.isEmpty {
            start(server: server, token: settings.token)
            return
        }
        guard settings.hasCredentials else {
            authError = "请先填写用户名和密码"
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
            authError = error.localizedDescription
            NSLog("[WS] ✗ 自动登录失败: \(error.localizedDescription)")
        }
    }

    /// token 失效后重新换一个并接着连。密码存在本地，用户无需干预。
    @MainActor
    func reauthenticate(settings: SettingsStore) async {
        settings.token = ""
        await connect(settings: settings)
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
        state = .connecting
        authError = nil
        connectingSince = Date()

        session = URLSession(configuration: .default)
        task = session?.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
        startPing()
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
        if settings.encryptionActive {
            outgoing.payload = PayloadCipher.encrypt(msg.payload, password: settings.syncPassword)
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
                NSLog("[WS] ↑ 已发送 \(outgoing.type)\(settings.encryptionActive ? " (已加密)" : "")")
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
                self.noteAuthFailureIfNeeded(err)
                self.scheduleReconnect()
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
        guard let data = text.data(using: .utf8),
              let msg = try? JSONDecoder().decode(SyncMessage.self, from: data) else {
            NSLog("[WS] ✗ 解析失败: \(text.prefix(200))")
            return
        }
        // 过滤自己发的消息（避免自己收到自己）
        if msg.from == deviceID { return }

        // 密文消息：用本机同步密码解开；解不开就只提示，不把密文塞进历史
        var resolved = msg
        let settings = SettingsStore.shared
        switch PayloadCipher.decrypt(msg.payload, password: settings.syncPassword) {
        case .plaintext:
            NSLog("[WS] ↓ 收到 \(msg.type)")
        case .decrypted(let plain):
            resolved.payload = plain
            NSLog("[WS] ↓ 收到 \(msg.type) (已解密)")
        case .failed(let fingerprint):
            let localFP = PayloadCipher.fingerprint(password: settings.syncPassword) ?? "未设置"
            NSLog("[WS] ✗ 解密失败 对端 key=\(fingerprint) 本机 key=\(localFP)")
            DispatchQueue.main.async {
                self.state = .connected
                self.decryptFailure = "收到无法解密的消息：请确认两端「同步密码」填写一致"
            }
            return
        }

        DispatchQueue.main.async {
            self.state = .connected
            self.decryptFailure = nil
            self.history.insert(resolved, at: 0)
            if self.history.count > 200 { self.history.removeLast() }
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
                    self.noteAuthFailureIfNeeded(err)
                    if self.state != .disconnected { self.scheduleReconnect() }
                } else if self.state != .connected {
                    self.state = .connected
                    self.connectingSince = nil
                    NSLog("[WS] 🟢 已连接服务器")
                }
            }
        }
    }

    // MARK: - 鉴权失败识别

    /// 服务端在 token 失效时用 HTTP 401 拒绝 WS 升级，URLSession 会把它
    /// 报成握手错误。这里把它翻译成一句用户能看懂的提示。
    private func noteAuthFailureIfNeeded(_ error: Error) {
        let ns = error as NSError
        let desc = ns.localizedDescription
        let looksLikeAuth = desc.contains("401") || desc.contains("Unauthorized")
            || ns.code == 401
        guard looksLikeAuth else { return }
        DispatchQueue.main.async {
            NSLog("[WS] 🔒 token 已失效，尝试用已保存的账号密码重新换取")
            let settings = SettingsStore.shared
            guard settings.hasCredentials else {
                self.authError = "登录已失效，请到设置里填写账号密码"
                return
            }
            // 密码存在本地，这里悄悄换一个新 token 接着连，用户不用干预。
            // 先停掉当前重试循环，避免和 connect() 里的新连接打架。
            self.stop()
            Task { await self.reauthenticate(settings: settings) }
        }
    }

    private func scheduleReconnect() {
        DispatchQueue.main.async {
            // 保证 "连接中" 至少显示 minConnectingDuration，避免一闪而过
            let delay: TimeInterval = {
                guard let started = self.connectingSince else { return 0 }
                let elapsed = Date().timeIntervalSince(started)
                return max(0, self.minConnectingDuration - elapsed)
            }()

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.isRunning else { return }
                self.state = .disconnected
                self.connectingSince = nil
                self.isRunning = false
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.pingTimer?.invalidate(); self.pingTimer = nil
                NSLog("[WS] 🔴 连接失败，已停止（不自动重连；点重连按钮再试）")
            }
        }
    }
}
