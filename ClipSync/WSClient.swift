import Foundation
import Combine

// ============================================================
// WSClient：与服务器的 WebSocket 长连接
// - 连接 / 断开 / 自动重连 / 心跳 ping
// - 收消息 → 更新 lastMessage & history
// - state (.disconnected/.connecting/.connected) 用 @Published 暴露给 UI
// - 只有第一次 ping 成功后才置 .connected，避免"闪现已连接"的假象
// ============================================================

final class WSClient: NSObject, ObservableObject {
    static let shared = WSClient()

    enum ConnectionState: String { case connecting, connected, disconnected }

    @Published var state: ConnectionState = .disconnected
    @Published var lastMessage: SyncMessage?
    @Published var history: [SyncMessage] = []

    /// 当前账号下的在线设备列表（服务端 presence 推送实时更新）
    @Published var onlineDevices: [OnlineDevice] = []

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
    private var currentCaps = ""

    /// 最近一次 WebSocket 握手返回的 HTTP 状态码。
    ///
    /// URLSession 在 WebSocket 握手失败（如 401）时，错误不会直接带 HTTP 状态码，
    /// 只报 NSURLErrorBadServerResponse(-1011)，所以需要通过 URLSessionTaskDelegate
    /// 在 didFinishCollectingMetrics 里把真实 statusCode 抓出来，供失败分类使用。
    private var lastHandshakeStatus: Int?

    /// 未连接时暂存的剪贴板消息，连上后自动补发。
    ///
    /// 场景：App 启动后用户立刻复制了东西，或断线重连期间复制了东西。
    /// 之前直接 send() 到一个还没建立的 task 上，消息就静默丢失了 ——
    /// 这正是"Mac 复制东西没到手机"偶发的原因。
    /// 只保留最新一条（剪贴板语义就是"最后一次复制"），避免堆积。
    private var pendingClipboard: SyncMessage?

    /// 用户主动断开时置 true，scheduleReconnect 据此跳过自动重连
    private var userInitiatedDisconnect = false
    /// 被服务端踢下线（密码重置/封禁）时置 true，阻止自动重连
    private var wasKicked = false
    /// token 失效后重新登录的次数，超过 1 次不再重试（密码已被改）
    private var authRetryCount = 0
    /// 自动重连尝试次数（指数退避：2, 4, 8, 16, 30, 30...）
    private var reconnectAttempts = 0
    /// 连续遇到"服务端拒绝"（4xx 非 401）的次数，超过上限停止重连
    private var hardFailureCount = 0
    private let maxReconnectDelay: TimeInterval = 30
    /// 4xx（非 401/403）连续失败超过此次数后停止，避免无限撞墙
    private let maxHardFailures = 3

    /// 重连定时器是否已排期。
    ///
    /// 被踢下线/网络断开瞬间，receive failure、ping failure、URLSession delegate close
    /// 可能在同一个 RunLoop 周期里各触发一次 scheduleReconnect，如果只靠 invalidate
    /// 旧定时器，多次调用会被各自重置回 3 秒（看似"重连好几次"）。这个标志保证
    /// 同一轮断连只会排一次重连，真正发起重连时才清掉。
    private var reconnectScheduled = false

    /// 本次 task 是否已失败处理过。
    ///
    /// 一次断线可能触发三个回调：receive failure、ping failure、
    /// urlSession(_:task:didCompleteWithError:)。
    /// 用这个标志保证同一次 task 失败只走一次分类和重连逻辑，
    /// 这才是"一下重连好几次"的根本解法。
    private var taskFailureHandled = false

    /// 最短 "连接中" 显示时间：进入 connecting 后至少停留 1.5s 才允许切回 disconnected
    private var connectingSince: Date?
    private let minConnectingDuration: TimeInterval = 1.5

    private override init() { super.init() }

    // MARK: - 连接控制

    /// 把本机同步开关拼成上报字符串：clip_up（剪贴板上行）/ auto_put（自动写入本机）。
    /// Mac 端这两个行为目前都是随连接生效，只要连上即视为开启。
    private func capsString(_ settings: SettingsStore) -> String {
        var parts: [String] = []
        if settings.autoSyncClipboard { parts.append("clip_up") }
        parts.append("auto_put") // Mac 收到远端剪贴板默认自动写入
        return parts.joined(separator: ",")
    }

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
            start(server: server, token: settings.token, caps: capsString(settings))
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
            start(server: server, token: session.token, caps: capsString(settings))
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

    /// 启动连接（用户主动点"连接"时调用）。
    /// 重置所有状态、错误计数，然后建立 WebSocket。
    /// - Parameter caps: 本机同步能力/开关，逗号分隔（如 "clip_up,auto_put"），上报给服务端用于在线列表展示。
    func start(server: String, token: String, caps: String = "") {
        // 只有在已连接/连接中且参数完全一样时才跳过。
        // 之前只看 isRunning，但被 403 踢下线后 isRunning 仍可能为 true
        // 而 state 已是 .disconnected，导致解禁后点连接被跳过、没反应。
        if (state == .connected || state == .connecting)
            && isRunning
            && server == currentServer
            && token == currentToken
            && caps == currentCaps {
            NSLog("[WS] start 跳过：已在连接同一 server")
            return
        }
        stop()
        isRunning = true
        userInitiatedDisconnect = false
        wasKicked = false
        authRetryCount = 0
        reconnectAttempts = 0
        hardFailureCount = 0
        currentServer = server
        currentToken = token
        currentCaps = caps
        state = .connecting
        authError = nil
        connectingSince = Date()
        openConnection(server: server, token: token, caps: caps)
    }

    /// 实际建立 WebSocket 连接。首次连接和静默重连都走这里。
    private func openConnection(server: String, token: String, caps: String? = nil) {
        guard !token.isEmpty else {
            NSLog("[WS] openConnection 失败：token 为空")
            return
        }
        let capsStr = caps ?? currentCaps
        // 设备名：优先用用户自定义名，为空才用系统主机名。
        // 否则每次重连都会用 Host.current().localizedName 覆盖掉用户在在线设备里改的名字。
        let rawName = SettingsStore.shared.customDeviceName.isEmpty
            ? (Host.current().localizedName ?? "Mac")
            : SettingsStore.shared.customDeviceName
        let deviceName = rawName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        var q = "token=\(token)&device=\(deviceID)&role=pc&platform=mac&name=\(deviceName)"
        if !capsStr.isEmpty {
            q += "&caps=\(capsStr)"
        }
        guard let url = URL(string: "\(server)/ws?\(q)") else {
            NSLog("[WS] openConnection 失败：URL 非法 \(server)")
            return
        }
        NSLog("[WS] → 正在连接 \(url.absoluteString)")

        // 清理旧连接资源（重连时复用）
        reconnectTimer?.invalidate(); reconnectTimer = nil
        pingTimer?.invalidate(); pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)

        // 重置握手状态码，让 delegate 抓本次的真实响应
        lastHandshakeStatus = nil
        // 新 task 开始，允许失败处理
        taskFailureHandled = false
        // 用自己作为 delegate，捕获 WebSocket 握手时的 HTTP 状态码
        // （URLSession 默认配置在握手失败时不会把 401/403 透传到 error 里）
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        task = session?.webSocketTask(with: url)
        task?.resume()
        isRunning = true
        receiveLoop()
        startPing()
        warmUpEncryptionKey()
    }

    /// 统一的 task 失败入口。
    ///
    /// receive failure、ping failure、didCompleteWithError 都会到这里。
    /// 用 taskFailureHandled 保证同一次 task 失败只处理一次，避免多个回调
    /// 同时触发重连造成"一下重连好几次"。
    /// didCompleteWithError 最后到达时 metrics 已就绪，能拿到准确 HTTP 状态码。
    private func handleTaskCompletion(error: Error, source: String) {
        DispatchQueue.main.async {
            // 主动断开 / 被踢 / 已处理过，直接忽略
            guard self.isRunning,
                  !self.userInitiatedDisconnect,
                  !self.wasKicked else { return }
            if self.taskFailureHandled {
                NSLog("[WS] 🔁 [\(source)] task 失败已处理过，跳过")
                return
            }
            self.taskFailureHandled = true

            NSLog("[WS] ✗ [\(source)] task 失败，开始分类处理")
            if !self.handleFailure(error, source: source) {
                self.scheduleReconnect(reason: Self.describeSocketFailure(error))
            }
        }
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
        currentCaps = ""
        pendingClipboard = nil
        reconnectScheduled = false
        reconnectTimer?.invalidate(); reconnectTimer = nil
        pingTimer?.invalidate();      pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
        onlineDevices = []
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
        let msg = SyncMessage(
            id: UUID().uuidString, type: MessageType.clipboard,
            from: deviceID, to: "*",
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        )
        enqueueOrSend(msg)
    }

    func sendClipboardImage(base64: String, mime: String = "image/png") {
        let payload = MessagePayload(
            text: nil, mime: mime, data: base64,
            preview: "[图片]", kind: MessageKind.image
        )
        let msg = SyncMessage(
            id: UUID().uuidString, type: MessageType.clipboard,
            from: deviceID, to: "*",
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        )
        enqueueOrSend(msg)
    }

    /// 未连接时入队，连上后补发；已连接直接发送。
    private func enqueueOrSend(_ msg: SyncMessage) {
        guard state == .connected, task != nil else {
            pendingClipboard = msg
            NSLog("[WS] ⏳ 未连接，剪贴板内容已暂存，连上后自动补发")
            return
        }
        send(msg)
    }

    /// 连接成功后把暂存的剪贴板补发出去。
    private func flushPendingClipboard() {
        guard let msg = pendingClipboard else { return }
        pendingClipboard = nil
        NSLog("[WS] 📤 补发暂存的剪贴板内容")
        send(msg)
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
                // 不在 receive 回调里直接重连：URLSession 的 didCompleteWithError
                // 会在 task 真正结束后回调，那时 metrics 已就绪、能拿到准确的 HTTP 状态码。
                // 在这里重连会导致 403（设备禁用）被误判、且和 delegate 回调重复触发。
                // 只做标记，由 handleTaskCompletion 统一处理。
                self.handleTaskCompletion(error: err, source: "receive")
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

        // presence 消息的 payload 是 {"devices":[...]}，跟业务消息的 MessagePayload 结构不同，
        // 在整体 decode 成 SyncMessage 之前先单独解析并更新在线设备列表。
        if let presence = decodePresence(data) {
            let newDevices = presence.payload.devices
            DispatchQueue.main.async {
                // 在赋值前和旧列表做 diff，对其他设备的上下线弹通知。
                // 首次拿到列表（旧为空）不弹，避免冷启动把所有在线设备误报为上线。
                if !self.onlineDevices.isEmpty {
                    self.notifyPresenceChanges(old: self.onlineDevices, new: newDevices)
                }
                self.onlineDevices = newDevices
            }
            NSLog("[WS] 👥 在线设备更新：\(newDevices.count) 台")
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

        // 服务端踢下线通知：主动断开，不重连，提示用户。
        // payload 形如 {"reason":"password_reset"|"device_banned"|...}，
        // 旧服务端可能不带 reason，按密码重置兜底。
        if msg.type == MessageType.serverKick {
            let reason = Self.extractKickReason(fromRaw: text)
            NSLog("[WS] 👢 收到服务端踢下线通知 reason=\(reason)")
            // 必须同步设置，否则紧随其后的 .failure 回调会在
            // main.async 之前进入 scheduleReconnect，导致重连
            self.wasKicked = true
            self.isRunning = false
            self.reconnectScheduled = false
            let prompt = Self.kickReasonPrompt(reason)
            DispatchQueue.main.async {
                self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.pingTimer?.invalidate(); self.pingTimer = nil
                self.state = .disconnected
                self.authError = prompt
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

    // MARK: - 在线设备（presence）

    private struct PresenceEnvelope: Codable {
        var type: String
        var payload: PayloadBody
        struct PayloadBody: Codable {
            var devices: [OnlineDevice]
        }
    }

    /// 若原始 JSON 是服务端下发的 presence 消息，解析出设备列表；否则返回 nil。
    private func decodePresence(_ data: Data) -> PresenceEnvelope? {
        guard let env = try? JSONDecoder().decode(PresenceEnvelope.self, from: data),
              env.type == MessageType.presence else { return nil }
        return env
    }

    /// 对比新旧在线列表，对其他设备的上线/下线弹通知（已在主线程调用）。
    @MainActor
    private func notifyPresenceChanges(old: [OnlineDevice], new: [OnlineDevice]) {
        let oldOthers = Dictionary(uniqueKeysWithValues: old
            .filter { !$0.isSelf }
            .map { ($0.deviceID, $0) })
        let newOthers = Dictionary(uniqueKeysWithValues: new
            .filter { !$0.isSelf }
            .map { ($0.deviceID, $0) })

        // 新上线：新列表里有、旧列表里没有
        for (id, dev) in newOthers where oldOthers[id] == nil {
            ToastManager.shared.showInfo(
                title: "设备上线",
                body: Self.presenceBody(dev, action: "已连接"),
                icon: dev.platformIcon,
                tint: .green
            )
        }
        // 刚下线：旧列表里有、新列表里没有
        for (id, dev) in oldOthers where newOthers[id] == nil {
            ToastManager.shared.showInfo(
                title: "设备下线",
                body: Self.presenceBody(dev, action: "已断开"),
                icon: dev.platformIcon,
                tint: .secondary
            )
        }
    }

    /// 构造上下线通知正文：有自定义名就显示「名字 · 平台（短ID）」，
    /// 没名字才 fallback 到「平台（短ID）」。
    private static func presenceBody(_ dev: OnlineDevice, action: String) -> String {
        if let name = dev.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "\(name) · \(dev.platformLabel)（\(dev.shortID)）\(action)"
        }
        return "\(dev.platformLabel)（\(dev.shortID)）\(action)"
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
                guard let self, self.isRunning,
                      !self.wasKicked, !self.userInitiatedDisconnect else { return }
                if let err = err {
                    NSLog("[WS] ⚠ ping 失败: \(err.localizedDescription)")
                    self.handleTaskCompletion(error: err, source: "ping")
                } else if self.state != .connected {
                    self.state = .connected
                    self.connectingSince = nil
                    self.reconnectAttempts = 0
                    self.hardFailureCount = 0
                    self.authRetryCount = 0
                    // 连上了，之前的失败提示就该消失
                    self.authError = nil
                    NSLog("[WS] 🟢 已连接服务器")
                    // 把未连接期间暂存的剪贴板内容补发出去
                    self.flushPendingClipboard()
                }
            }
        }
    }

    // MARK: - 失败分类与重连决策

    /// 失败类型：决定是否重连、用什么策略重连
    private enum FailureKind {
        case authExpired       // 401：token 过期，尝试重新登录
        case forbidden         // 403：被服务端拒绝，不重连
        case hardReject        // 其他 4xx：有限次重试后停止
        case serverError       // 5xx：服务端临时问题，持续退避
        case network           // 网络问题（断网/DNS/超时），持续退避
        case cancelled         // 主动 cancel 旧 task，不重连
        case unknown
    }

    private func classifyFailure(_ error: Error) -> FailureKind {
        let ns = error as NSError
        // 主动 cancel 旧 task（用户点连接/断开、重连切换 task）不算失败，不重连
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return .cancelled
        }
        // 诊断日志
        NSLog("[WS] 🔍 classifyFailure domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) handshakeStatus=\(lastHandshakeStatus.map { String($0) } ?? "nil")")

        // 1) 优先用 delegate 抓到的真实握手 HTTP 状态码（最可靠）
        if let status = lastHandshakeStatus {
            switch status {
            case 401: return .authExpired
            case 403: return .forbidden
            case 400..<500: return .hardReject
            case 500..<600: return .serverError
            default: break
            }
        }
        // 2) 再试从 error.userInfo 里提
        if let status = Self.extractHTTPStatus(from: error) {
            switch status {
            case 401: return .authExpired
            case 403: return .forbidden
            case 400..<500: return .hardReject
            case 500..<600: return .serverError
            default: break
            }
        }
        // 3) NSURLErrorBadServerResponse 拿不到 status 时：
        //    不能假定为 token 过期 —— 设备禁用/账号禁用也是握手阶段返回非 101，
        //    重新登录拿到新 token 后照样被 403，会形成死循环。
        //    按 hardReject 处理，最多重试 3 次后停止并提示用户。
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorBadServerResponse {
            NSLog("[WS] 🔍 握手失败且无状态码，按硬拒绝处理")
            return .hardReject
        }
        // 网络类错误
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorTimedOut:
                return .network
            default:
                return .unknown
            }
        }
        return .unknown
    }

    /// 统一处理失败：分类后决定是重连、重新登录还是停止。
    /// 返回 true 表示已自行处理（调用方不用再调 scheduleReconnect）。
    @discardableResult
    private func handleFailure(_ error: Error, source: String) -> Bool {
        let kind = classifyFailure(error)
        NSLog("[WS] ✗ [\(source)] 失败类型=\(kind) desc=\(error.localizedDescription)")

        switch kind {
        case .cancelled:
            // 主动 cancel：忽略，不重连、不报错、不改状态
            NSLog("[WS] → [\(source)] task 被主动取消，忽略")
            return true
        case .authExpired:
            return handleAuthExpired()
        case .forbidden:
            DispatchQueue.main.async {
                self.wasKicked = true
                self.isRunning = false
                self.taskFailureHandled = false
                self.reconnectScheduled = false
                self.reconnectTimer?.invalidate()
                self.reconnectTimer = nil
                self.pingTimer?.invalidate()
                self.pingTimer = nil
                self.state = .disconnected
                self.authError = "服务端拒绝连接（403），请检查账号或设备状态"
            }
            return true
        case .hardReject:
            hardFailureCount += 1
            if hardFailureCount >= maxHardFailures {
                let status = Self.extractHTTPStatus(from: error) ?? 0
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.taskFailureHandled = false
                    self.reconnectScheduled = false
                    self.reconnectTimer?.invalidate()
                    self.reconnectTimer = nil
                    self.state = .disconnected
                    self.authError = "服务端连续返回错误（HTTP \(status)），已停止重连，请检查配置"
                    NSLog("[WS] 🔴 连续 \(self.hardFailureCount) 次 4xx，停止重连")
                }
                return true
            }
            return false // 继续重连
        case .serverError, .network, .unknown:
            return false // 继续走指数退避重连
        }
    }

    /// 401 处理：token 失效，用保存的账号密码重新换 token
    private func handleAuthExpired() -> Bool {
        if wasKicked { return true }
        authRetryCount += 1
        if authRetryCount > 1 {
            NSLog("[WS] 🔒 重新登录仍失败（第\(authRetryCount)次），密码可能已被重置")
            DispatchQueue.main.async {
                self.wasKicked = true
                self.reconnectScheduled = false
                self.reconnectTimer?.invalidate()
                self.reconnectTimer = nil
                self.state = .disconnected
                self.authError = "登录已失效，请在设置中重新填写密码后手动连接"
            }
            return true
        }
        DispatchQueue.main.async {
            NSLog("[WS] 🔒 token 已失效，尝试用已保存的账号密码重新换取（第\(self.authRetryCount)次）")
            let settings = SettingsStore.shared
            guard settings.hasCredentials else {
                self.wasKicked = true
                self.reconnectScheduled = false
                self.authError = "登录已失效，请到设置里填写账号密码"
                self.state = .disconnected
                return
            }
            self.reconnectScheduled = false
            self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
            self.stop()
            Task { await self.reauthenticate(settings: settings) }
        }
        return true
    }

    /// 把 URLSession 的底层错误翻成用户能看懂的一句话
    static func describeSocketFailure(_ error: Error) -> String {
        let ns = error as NSError

        // 优先根据 HTTP 状态码给出精确描述
        if let status = Self.extractHTTPStatus(from: error) {
            switch status {
            case 400: return "服务器拒绝了请求（400），请检查服务器地址是否正确"
            case 401: return "登录已失效，正在尝试自动重新登录…"
            case 403: return "服务器拒绝访问（403），请检查账号状态"
            case 404: return "服务器地址无效（404），请检查路径是否正确"
            case 408: return "服务器响应超时（408），请稍后自动重连"
            case 413: return "消息内容过大，被服务器拒绝（413）"
            case 429: return "请求过于频繁，被服务器限流（429）"
            case 500: return "服务器内部错误（500），稍后自动重连"
            case 502: return "服务器网关错误（502），服务可能正在重启"
            case 503: return "服务器暂时不可用（503），稍后自动重连"
            case 504: return "服务器网关超时（504），稍后自动重连"
            default:
                if status >= 500 { return "服务器错误（HTTP \(status)），稍后自动重连" }
                if status >= 400 { return "服务器返回错误（HTTP \(status)），请检查配置" }
            }
        }

        guard ns.domain == NSURLErrorDomain else {
            return "连接中断：\(ns.localizedDescription)"
        }
        switch ns.code {
        case NSURLErrorBadServerResponse:
            return "服务器返回了无效响应，请检查服务器地址和协议（ws/wss）"
        case NSURLErrorNotConnectedToInternet:
            return "网络不可用，请检查本机网络连接"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "找不到服务器，请检查服务器地址"
        case NSURLErrorCannotConnectToHost:
            return "无法连接到服务器，请确认地址、端口和服务是否已启动"
        case NSURLErrorTimedOut:
            return "连接服务器超时，请检查网络或服务器状态"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "TLS 握手失败，请确认服务器证书配置"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接已断开，正在自动重连…"
        case NSURLErrorUserCancelledAuthentication:
            return "服务器要求认证，请检查用户名和密码"
        case NSURLErrorUserAuthenticationRequired:
            return "认证失败，请检查用户名和密码"
        default:
            return "连接失败：\(ns.localizedDescription)"
        }
    }

    /// 从 URLSession 错误中提取 HTTP 状态码（供 describeSocketFailure 用）
    private static func extractHTTPStatus(from error: Error) -> Int? {
        let ns = error as NSError
        if let code = ns.userInfo["HTTPResponseStatusCode"] as? Int { return code }
        if let resp = ns.userInfo[NSURLErrorFailingURLErrorKey] as? HTTPURLResponse {
            return resp.statusCode
        }
        if let resp = ns.userInfo["NSErrorFailingURLKey"] as? HTTPURLResponse {
            return resp.statusCode
        }
        if let match = ns.localizedDescription.range(of: "\\b(\\d{3})\\b", options: .regularExpression) {
            return Int(ns.localizedDescription[match])
        }
        return nil
    }

    // MARK: - Kick reason

    /// 从原始 JSON 文本里提取 server_kick 的 payload.reason。
    /// MessagePayload 没有 reason 字段，decode 成 SyncMessage 时会丢掉，
    /// 所以这里单独解一次原始数据。
    private static func extractKickReason(fromRaw raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let reason = payload["reason"] as? String
        else { return "" }
        return reason
    }

    /// reason → 提示文案。设备禁用等"不能再连"的场景必须明确告诉用户不要尝试。
    private static func kickReasonPrompt(_ reason: String) -> String {
        switch reason {
        case "password_reset":
            return "密码已被管理员重置，请重新登录"
        case "user_disabled":
            return "账号已被管理员禁用，请联系管理员"
        case "user_deleted":
            return "账号已被删除"
        case "device_banned":
            return "当前设备已被管理员禁用，无法继续连接"
        case "device_kicked":
            // 只是被踢一脚，没改状态；但客户端不应自动重连，等用户手动重连
            return "已被管理员强制下线，请点击连接重新登录"
        default:
            return "已被服务端强制下线，请重新登录"
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
            // 本轮已经排过重连定时器，不再重复排期。
            // 否则 receive failure + ping failure + delegate close 会各触发一次，
            // 每次都把定时器重置回 3 秒，看起来像"一下重连好几次"。
            if self.reconnectScheduled {
                NSLog("[WS] 🔄 重连已排期，跳过重复触发")
                return
            }
            self.reconnectScheduled = true

            // 清理当前连接资源，但保留 server/token 供重连使用
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.pingTimer?.invalidate(); self.pingTimer = nil

            // 固定 3 秒重连一次，简单可预期；UI 在重连期间保持 .connecting
            // 状态，不会在"连接/未连接"之间反复跳动，用户可以正常点按钮
            let delay: TimeInterval = 3
            self.reconnectAttempts += 1

            // 重连期间保持 .connecting 状态，不切到 .disconnected，
            // 这样 UI 不会在"连接/未连接"之间反复跳动，用户可以正常点按钮
            self.state = .connecting
            self.connectingSince = Date()
            // 错误原因只在第一次断开时设置，避免反复覆盖
            if let reason, self.authError == nil {
                self.authError = reason
            }

            let server = self.currentServer
            let token = self.currentToken
            NSLog("[WS] 🔄 \(Int(delay))秒后静默重连（第\(self.reconnectAttempts)次）→ \(server)")

            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, !self.userInitiatedDisconnect, !self.wasKicked else { return }
                guard !server.isEmpty, !token.isEmpty else {
                    NSLog("[WS] ✗ 重连失败：server 或 token 为空")
                    self.reconnectScheduled = false
                    return
                }
                NSLog("[WS] 🔄 正在静默重连 → \(server)")
                // 真正发起重连前清掉排期标志，允许下一轮失败再次排期
                self.reconnectScheduled = false
                // 静默重连：不重置 isRunning，不闪 UI；
                // 保留上次的 authError，让用户看到重连原因，直到连上才清
                self.currentServer = server
                self.currentToken = token
                self.openConnection(server: server, token: token)
            }
            RunLoop.main.add(self.reconnectTimer!, forMode: .common)
        }
    }
}

// MARK: - URLSessionTaskDelegate

/// 用 delegate 捕获 WebSocket 握手时的真实 HTTP 状态码。
///
/// URLSession 的 webSocketTask 在握手失败（服务端返回 401/403/5xx 等非 101 响应）时，
/// error 只会是 NSURLErrorBadServerResponse(-1011)，不携带状态码，导致我们无法
/// 区分"token 过期"和"服务端 500"。这里从 transactionMetrics 里把 response 抓出来，
/// classifyFailure 会优先读 lastHandshakeStatus 做准确判断。
extension WSClient: URLSessionTaskDelegate, URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        for trans in metrics.transactionMetrics {
            if let http = trans.response as? HTTPURLResponse {
                lastHandshakeStatus = http.statusCode
                NSLog("[WS] 📡 握手 HTTP \(http.statusCode)")
                break
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // 正常关闭（error == nil）不处理；只有异常结束才走失败分类。
        // 此时 transactionMetrics 已全部就绪，lastHandshakeStatus 一定有值，
        // 能准确区分 401（token 过期）和 403（设备禁用/账号封禁）。
        guard let error else { return }
        NSLog("[WS] 🏁 didCompleteWithError: \(error.localizedDescription) status=\(lastHandshakeStatus.map { String($0) } ?? "nil")")
        handleTaskCompletion(error: error, source: "delegate")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        NSLog("[WS] ✅ WebSocket 已打开")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        NSLog("[WS] 🔌 WebSocket 已关闭 code=\(closeCode.rawValue)")
    }
}
