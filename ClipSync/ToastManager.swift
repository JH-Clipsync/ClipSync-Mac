import AppKit
import SwiftUI

// ============================================================
// ToastManager：右上角通知横幅管理器
// - 无边框浮窗，多条向下堆叠
// - 8 秒自动消失
// - 按消息 id 去重（LRU 200 条 / 10 分钟窗口），同 id 补明文帧可原地更新
// - 无稳定 id 的消息退回「内容指纹 + 3 秒窗口」兜底
// - canBecomeKey=false → 不激活 App、不带出主窗口
// ============================================================

@MainActor
final class ToastManager {
    static let shared = ToastManager()

    private var windows: [NSWindow] = []
    private let spacing: CGFloat = 8
    private let margin: CGFloat = 14
    private let autoDismissSeconds: Double = 8
    private var dismissWork: [ObjectIdentifier: DispatchWorkItem] = [:]
    /// 全局 ESC 监听：Toast 浮窗本身不可以成为 key（会激活 App），
    /// 但用户按 ESC 时应关闭最顶部的 Toast。装一个本 App 范围的
    /// local monitor，keyDown 是 ESC 就关掉，其他事件原样放行。
    private var escapeMonitor: Any?

    /// 无 id 消息的兜底去重：单槽内容指纹 + 3 秒窗口（showInfo 同构）
    private var lastSig = ""
    private var lastTime: Date = .distantPast

    // MARK: 消息 id 去重（LRU）

    /// 去重条目：该 id 最近一次展示的消息 + 最近命中时间
    private struct DedupEntry {
        var message: SyncMessage
        var seenAt: Date
    }

    /// LRU 容量：200 条；时间窗口：10 分钟（覆盖 Android 75s 磁盘确认窗并留余量）
    private let dedupCapacity = 200
    private let dedupWindow: TimeInterval = 600

    /// id → 最近条目；dedupOrder 维护旧→新顺序，配合做 LRU 淘汰与过期清理。
    /// 所有访问都在 MainActor（show / showInfo 均由主线程调用），无需加锁。
    private var dedupTable: [String: DedupEntry] = [:]
    private var dedupOrder: [String] = []

    /// 在屏 Toast 窗口 → 消息 id：同 id 补明文帧用来定位要原地更新的浮窗
    private var windowMessageIDs: [ObjectIdentifier: String] = [:]

    private init() {}

    /// 简洁通知（用于设备上下线等状态提示）：标题 + 正文，无操作按钮。
    func showInfo(title: String, body: String, icon: String = "bell.fill", tint: Color = .accentColor) {
        show(signal: "info|\(title)|\(body)", view: InfoToastView(
            title: title, detail: body, icon: icon, tint: tint,
            onClose: { [weak self] in self?.dismissTop() }
        ), width: 360)
    }

    func show(message: SyncMessage) {
        // 无稳定 id（id 为空）→ 退回内容指纹 + 3 秒窗口的旧兜底行为
        if message.id.isEmpty {
            let sig = contentFingerprint(of: message)
            if sig == lastSig, Date().timeIntervalSince(lastTime) < 3 {
                return
            }
            lastSig = sig
            lastTime = Date()
            presentToast(message, id: nil)
            return
        }

        switch register(message) {
        case .show:
            presentToast(message, id: message.id)
        case .silent:
            break
        case .refresh:
            refreshToast(message)
        }
    }

    /// 同 id 帧的去重处置
    private enum IdDedupResult {
        case show       // 新 id：正常弹
        case silent     // 命中 id 且没有更完整内容：静默
        case refresh    // 命中 id 且正文更完整（如打码→明文）：更新展示
    }

    /// 把消息登记进 id 去重表并给出处置方式。仅 MainActor 调用。
    private func register(_ message: SyncMessage) -> IdDedupResult {
        let now = Date()
        pruneExpired(now: now)

        if let entry = dedupTable[message.id] {
            // LRU 命中：提到最新位并刷新时间窗
            dedupOrder.removeAll { $0 == message.id }
            dedupOrder.append(message.id)

            if message.payload == entry.message.payload {
                // 完全相同的重复帧（重连补发等）：静默，保留原条目
                dedupTable[message.id] = DedupEntry(message: entry.message, seenAt: now)
                NSLog("[Toast] 同 id 重复帧静默 id=\(message.id.prefix(8))")
                return .silent
            }
            if message.isMoreComplete(than: entry.message) {
                // 同 id 补明文 / 更完整版本：升级条目并刷新展示
                dedupTable[message.id] = DedupEntry(message: message, seenAt: now)
                NSLog("[Toast] 同 id 更完整帧，更新展示 id=\(message.id.prefix(8))")
                return .refresh
            }
            // 内容不同但并不更完整（如明文之后又到打码帧）：静默且不降级
            dedupTable[message.id] = DedupEntry(message: entry.message, seenAt: now)
            NSLog("[Toast] 同 id 后到帧不更完整，静默忽略 id=\(message.id.prefix(8))")
            return .silent
        }

        // 新 id：入表，超出容量淘汰最久未使用的队头
        dedupTable[message.id] = DedupEntry(message: message, seenAt: now)
        dedupOrder.append(message.id)
        while dedupOrder.count > dedupCapacity, let oldest = dedupOrder.first {
            dedupOrder.removeFirst()
            dedupTable.removeValue(forKey: oldest)
        }
        return .show
    }

    /// 懒清理：丢弃超过 10 分钟窗口的最旧条目（从队头开始连续清理）
    private func pruneExpired(now: Date) {
        while let oldest = dedupOrder.first,
              let entry = dedupTable[oldest],
              now.timeIntervalSince(entry.seenAt) > dedupWindow {
            dedupOrder.removeFirst()
            dedupTable.removeValue(forKey: oldest)
        }
    }

    /// 无 id 消息的内容指纹（与历史方案同构）：type|text|preview
    private func contentFingerprint(of message: SyncMessage) -> String {
        "\(message.type)|\(message.payload.text ?? message.payload.preview ?? "")"
    }

    /// 同 id 更完整帧：浮窗还在屏上就原地换内容，已消失则重新弹一条，
    /// 保证打码帧先到时用户最终一定看得到明文。
    private func refreshToast(_ message: SyncMessage) {
        if let win = activeWindow(id: message.id) {
            let content = makeToastView(message: message, window: win)
            replaceContent(win: win, content: content, width: content.windowWidth)
            // 内容刚更新，重新给足 8 秒阅读时间
            scheduleAutoDismiss(win)
        } else {
            presentToast(message, id: message.id)
        }
    }

    private func activeWindow(id: String) -> ToastWindow? {
        guard let win = windows.first(where: { windowMessageIDs[ObjectIdentifier($0)] == id }) else {
            return nil
        }
        return win as? ToastWindow
    }

    private func presentToast(_ message: SyncMessage, id: String?) {
        let win = ToastWindow()
        let content = makeToastView(message: message, window: win)
        present(win: win, content: content, width: content.windowWidth, messageID: id)
    }

    /// 构建短信/剪贴板 Toast 内容；更新帧复用同一工厂，闭包捕获最新 message
    private func makeToastView(message: SyncMessage, window win: ToastWindow) -> ToastView {
        // 短信类 → 尝试抽取验证码
        let code: String? = {
            guard message.looksLikeSms else { return nil }
            guard let text = message.payload.text else { return nil }
            return SmsCodeExtractor.extract(from: text)
        }()

        return ToastView(
            message: message,
            showContent: SettingsStore.shared.showContent,
            extractedCode: code,
            onCopyCode: {
                if let c = code {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(c, forType: .string)
                    ClipboardMonitor.shared.suppressNext()
                    ClipboardMonitor.shared.markSignature("text:\(c.hashValue)")
                }
            },
            onCopyAll: {
                ClipboardWriter.apply(payload: message.payload)
            },
            onPreviewImage: { [weak self, weak win] in
                guard let self, let w = win else { return }
                // 先关掉 Toast，再弹出大预览窗口
                self.dismiss(w)
                if let b64 = message.payload.data,
                   let data = Data(base64Encoded: b64),
                   let img = NSImage(data: data) {
                    ImagePreviewWindows.show(image: img)
                }
            },
            onClose: { [weak self, weak win] in
                guard let self, let w = win else { return }
                self.dismiss(w)
            },
            onOpen: { [weak self, weak win] in
                guard let self, let w = win else { return }
                // 先关掉弹窗，再打开主窗口跳到对应 Tab
                self.dismiss(w)
                let target: SidebarItem = message.looksLikeSms ? .sms : .clipboard
                AppRouter.shared.open(target)
            }
        )
    }

    /// 简洁通知通用入口：去重 → 清掉旧窗 → 摆放并淡入。
    private func show<V: View>(signal: String, view: V, width: CGFloat) {
        if signal == lastSig, Date().timeIntervalSince(lastTime) < 3 {
            return
        }
        lastSig = signal
        lastTime = Date()

        let win = ToastWindow()
        present(win: win, content: view, width: width, messageID: nil)
    }

    /// 把 SwiftUI 内容装进 ToastWindow 并显示（show / showInfo 共用）。
    private func present<V: View>(win: ToastWindow, content: V, width: CGFloat, messageID: String?) {
        // 同屏只留一条：新通知直接挤掉旧窗
        for old in windows {
            let key = ObjectIdentifier(old)
            dismissWork[key]?.cancel()
            dismissWork[key] = nil
            windowMessageIDs.removeValue(forKey: key)
            old.orderOut(nil)
        }
        windows.removeAll()

        host(content: content, in: win, width: width)

        windows.append(win)
        if let messageID {
            windowMessageIDs[ObjectIdentifier(win)] = messageID
        }
        placeAll()

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            win.animator().alphaValue = 1.0
        }

        installEscapeMonitorIfNeeded()
        scheduleAutoDismiss(win)
    }

    /// 把 SwiftUI 内容装进窗口并按 fittingSize 定尺寸。
    /// 首次展示与同 id 补明文的原地更新共用这条装配路径。
    private func host<V: View>(content: V, in win: ToastWindow, width: CGFloat) {
        // NSHostingView 会根据 SwiftUI 内容计算 fittingSize，我们用它做窗口大小
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // 承载视图自己也要带圆角：SwiftUI 里的 clipShape 管不到 AppKit 层，
        // 漏出来的方角就是"有时圆角有时方角"的由来
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = ToastStyle.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        win.contentView = hosting
        // 先给定初始宽度让 SwiftUI 按 width 布局，再量高度
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        let size = hosting.fittingSize
        win.setContentSize(NSSize(
            width:  ceil(max(size.width,  width)),
            height: ceil(max(size.height, 60))
        ))
    }

    /// 同 id 补明文：在同一个浮窗内替换内容并按新正文重算尺寸/位置，
    /// 不新增窗口、不改变 alpha，桌面表现为横幅内容原地刷新。
    private func replaceContent<V: View>(win: ToastWindow, content: V, width: CGFloat) {
        host(content: content, in: win, width: width)
        placeAll()
    }

    /// 首次有 Toast 显示时装上 ESC 监听；监听只在本 App 内生效，
    /// 不会吃掉其他 App 的按键。
    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // ESC：关掉最顶部的 Toast（栈顶），并吞掉事件避免传给下层控件
            if event.keyCode == 53, let top = self.windows.last {
                self.dismiss(top)
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitorIfNeeded() {
        guard windows.isEmpty, let monitor = escapeMonitor else { return }
        NSEvent.removeMonitor(monitor)
        escapeMonitor = nil
    }

    /// 关闭最顶部的通知（InfoToastView 的关闭按钮用）。
    private func dismissTop() {
        guard let top = windows.last else { return }
        dismiss(top)
    }

    // MARK: - 布局

    private func placeAll() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        var y = vf.maxY - margin
        for w in windows {
            let s = w.frame.size
            let x = vf.maxX - s.width - margin
            // 原点同样要落在整像素上：visibleFrame 在有刘海/菜单栏的屏幕上会带
            // 小数，半像素的窗口位置会把描边重新抹掉。
            w.setFrameOrigin(NSPoint(x: (x).rounded(), y: (y - s.height).rounded()))
            y = y - s.height - spacing
        }
    }

    // MARK: - 自动消失

    private func scheduleAutoDismiss(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        dismissWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let w = window else { return }
            self.dismiss(w)
        }
        dismissWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissSeconds, execute: work)
    }

    private func dismiss(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        dismissWork[key]?.cancel()
        dismissWork[key] = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            window.animator().alphaValue = 0
        }, completionHandler: {
            // completionHandler 是 @Sendable 闭包，非 main actor 上下文
            // 显式切回 MainActor 才能改 windows / 调 placeAll()
            Task { @MainActor in
                window.orderOut(nil)
                self.windowMessageIDs.removeValue(forKey: ObjectIdentifier(window))
                self.windows.removeAll { $0 == window }
                self.placeAll()
                self.removeEscapeMonitorIfNeeded()
            }
        })
    }
}

// MARK: - SyncMessage 去重判定（ToastManager 与 HistoryStore 共用同一口径）

extension SyncMessage {
    /// 去重比较用正文：text 优先、preview 兜底，与 ToastView 的展示口径一致
    var dedupBody: String {
        if let text = payload.text, !text.isEmpty { return text }
        return payload.preview ?? ""
    }

    /// 正文是否为系统「锁屏防偷窥」打码占位：含连续 5 个及以上 *。
    /// 与 Android NotificationSmsListener 的 looksMasked 判定保持同口径。
    var looksMaskedBody: Bool {
        dedupBody.range(of: #"\*{5,}"#, options: .regularExpression) != nil
    }

    /// 同 id 后到帧是否比当前帧「更完整」。规则只允许升级、不允许降级：
    /// - 旧帧打码、新帧为非空非打码明文 → 更完整（通知打码先到、广播明文后到）
    /// - 正文严格变长 → 更完整
    /// - 图片 data 从无到有 → 更完整
    func isMoreComplete(than old: SyncMessage) -> Bool {
        if !looksMaskedBody && old.looksMaskedBody && !dedupBody.isEmpty { return true }
        if dedupBody.count > old.dedupBody.count { return true }
        if old.payload.data == nil && payload.data != nil { return true }
        return false
    }
}

// MARK: - 无边框浮窗（点击不激活 App）

/// Toast 浮窗。
///
/// 必须是 NSPanel 且带 .nonactivatingPanel：这是唯一能让"点击浮窗上的按钮
/// 不激活本 App"的做法。普通 NSWindow 即使 canBecomeKey=false，点击时系统
/// 仍会激活所属 App，进而把主窗口一起带到前台，挡住用户正在操作的地方。
final class ToastWindow: NSPanel {
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // 浮窗自己不参与激活，也别抢已有的 key 状态
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
