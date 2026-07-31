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

    func show(message: SyncMessage) {
        // 3 秒内相同内容不再重复弹
        let sig = "\(message.type)|\(message.payload.text ?? message.payload.preview ?? "")"
        if sig == lastSig, Date().timeIntervalSince(lastTime) < 3 {
            return
        }
        lastSig = sig
        lastTime = Date()

        let win = ToastWindow()

        // 短信类 → 尝试抽取验证码
        let code: String? = {
            guard message.isSms else { return nil }
            guard let text = message.payload.text else { return nil }
            return SmsCodeExtractor.extract(from: text)
        }()

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
            }
        )
        // NSHostingView 会根据 SwiftUI 内容计算 fittingSize，我们用它做窗口大小
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        win.contentView = hosting
        let size = hosting.fittingSize
        // 保底最小尺寸，避免 fittingSize 拿到 0
        win.setContentSize(NSSize(
            width:  max(size.width,  380),
            height: max(size.height, 60)
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

    // MARK: - 布局

    private func placeAll() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        var y = vf.maxY - margin
        for w in windows {
            let s = w.frame.size
            let x = vf.maxX - s.width - margin
            w.setFrameOrigin(NSPoint(x: x, y: y - s.height))
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

// MARK: - 无边框浮窗（不激活 App）

final class ToastWindow: NSWindow {
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.borderless],
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
