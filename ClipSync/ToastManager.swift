import AppKit
import SwiftUI

// ============================================================
// ToastManager：右上角通知横幅管理器
// - 无边框浮窗，多条向下堆叠
// - 8 秒自动消失
// - 短时间内同一内容去重
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

    /// 短时间去重
    private var lastSig = ""
    private var lastTime: Date = .distantPast

    private init() {}

    /// 简洁通知（用于设备上下线等状态提示）：标题 + 正文，无操作按钮。
    func showInfo(title: String, body: String, icon: String = "bell.fill", tint: Color = .accentColor) {
        show(signal: "info|\(title)|\(body)", view: InfoToastView(
            title: title, detail: body, icon: icon, tint: tint,
            onClose: { [weak self] in self?.dismissTop() }
        ), width: 360)
    }

    func show(message: SyncMessage) {
        // 3 秒内相同内容不再重复弹
        let sig = "\(message.type)|\(message.payload.text ?? message.payload.preview ?? "")"
        if sig == lastSig, Date().timeIntervalSince(lastTime) < 3 {
            return
        }
        lastSig = sig
        lastTime = Date()

        // 短信类 → 尝试抽取验证码
        let code: String? = {
            guard message.looksLikeSms else { return nil }
            guard let text = message.payload.text else { return nil }
            return SmsCodeExtractor.extract(from: text)
        }()

        let win = ToastWindow()
        let content = ToastView(
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
        present(win: win, content: content, width: content.windowWidth, signal: sig)
    }

    /// 简洁通知通用入口：去重 → 清掉旧窗 → 摆放并淡入。
    private func show<V: View>(signal: String, view: V, width: CGFloat) {
        if signal == lastSig, Date().timeIntervalSince(lastTime) < 3 {
            return
        }
        lastSig = signal
        lastTime = Date()

        let win = ToastWindow()
        let content = view
        present(win: win, content: content, width: width, signal: signal)
    }

    /// 把 SwiftUI 内容装进 ToastWindow 并显示（show / showInfo 共用）。
    private func present<V: View>(win: ToastWindow, content: V, width: CGFloat, signal: String) {
        // 同屏只留一条：新通知直接挤掉旧窗
        for old in windows {
            let key = ObjectIdentifier(old)
            dismissWork[key]?.cancel()
            dismissWork[key] = nil
            old.orderOut(nil)
        }
        windows.removeAll()

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

        windows.append(win)
        placeAll()

        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            win.animator().alphaValue = 1.0
        }

        scheduleAutoDismiss(win)
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
                self.windows.removeAll { $0 == window }
                self.placeAll()
            }
        })
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
