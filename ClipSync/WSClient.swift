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

    func sendClipboardImage(base64: String) {
        let payload = MessagePayload(
            text: nil, mime: "image/png", data: base64,
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
        guard let data = try? JSONEncoder().encode(msg),
              let text = String(data: data, encoding: .utf8) else {
            NSLog("[WS] 发送失败：编码错误")
            return
        }
        task?.send(.string(text)) { err in
            if let err = err {
                NSLog("[WS] 发送失败: \(err.localizedDescription)")
            } else {
                NSLog("[WS] ↑ 已发送 \(msg.type)")
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

        NSLog("[WS] ↓ 收到 \(msg.type)")
        DispatchQueue.main.async {
            self.state = .connected
            self.history.insert(msg, at: 0)
            if self.history.count > 200 { self.history.removeLast() }
            self.lastMessage = msg
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
                    if self.state != .disconnected { self.scheduleReconnect() }
                } else if self.state != .connected {
                    self.state = .connected
                    self.connectingSince = nil
                    NSLog("[WS] 🟢 已连接服务器")
                }
            }
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
