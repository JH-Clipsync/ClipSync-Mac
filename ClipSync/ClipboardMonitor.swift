import Foundation
import AppKit
import Combine

// ============================================================
// ClipboardMonitor：轮询 NSPasteboard.changeCount，检测本机剪贴板变化
// - macOS 没有剪贴板变化通知，只能 0.6s 轮询一次
// - 需要过滤"自己写入的内容"（收到远端消息后写回时不再上传）
// - 通过 suppressNext() + markSignature() 双重去重
// ============================================================

/// 剪贴板图片压缩：长边缩到 1600 + JPEG(0.82)，保证单条消息远小于服务端
/// readLimit（10MB），避免 Retina 全屏截图直接把 WebSocket 撑断。
enum ClipboardImageCompressor {
    static let maxEdge: CGFloat = 1600

    /// 返回 (base64, mime)。data 已是常见图片格式（PNG/TIFF 等）。
    static func compress(_ data: Data) -> (base64: String, mime: String)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }

        let longEdge = CGFloat(max(rep.pixelsWide, rep.pixelsHigh))
        // 小图不值得转 JPEG（JPEG 无透明通道），直接原样发
        if longEdge <= maxEdge {
            return (data.base64EncodedString(), "image/png")
        }

        let scale = maxEdge / longEdge
        let w = max(1, Int(CGFloat(rep.pixelsWide) * scale))
        let h = max(1, Int(CGFloat(rep.pixelsHigh) * scale))
        guard let img = NSImage(data: data) else { return nil }

        let dest = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        guard let destRep = dest else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: destRep)
        img.draw(
            in: NSRect(x: 0, y: 0, width: w, height: h),
            from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height),
            operation: .copy, fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let jpeg = destRep.representation(
            using: .jpeg, properties: [.compressionFactor: 0.82]
        ) else { return nil }
        return (jpeg.base64EncodedString(), "image/jpeg")
    }
}

final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    /// 是否启用（由 SettingsStore.autoSyncClipboard 控制）
    @Published var isEnabled: Bool = false

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private var lastSignature: String = ""
    private var suppressCount: Int = 0

    private weak var wsClient: WSClient?

    private init() {}

    func bind(_ ws: WSClient) {
        self.wsClient = ws
    }

    func start() {
        guard timer == nil else {
            NSLog("[Clipboard] 已在监听，跳过")
            return
        }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        NSLog("[Clipboard] 监听已启动")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSLog("[Clipboard] 监听已停止")
    }

    /// 在写入剪贴板前调用，让下一次 tick 忽略这次变化
    func suppressNext() {
        suppressCount += 1
    }

    /// 记录签名，防止连续两次相同内容重复上传
    func markSignature(_ sig: String) {
        lastSignature = sig
    }

    // MARK: - 手动推送（主页「推送当前剪贴板」按钮用）

    /// 读取当前剪贴板的文本（不上传）。返回 nil 表示剪贴板为空或不是文本。
    func peekText() -> String? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        return text
    }

    /// 读取当前剪贴板的图片（不上传），返回 NSImage 用于 UI 预览。
    /// 先尝试 PNG，再退到 TIFF，兼容 writeObjects / setData 两种写入方式。
    func peekImage() -> NSImage? {
        if let data = pasteboard.data(forType: .png) {
            return NSImage(data: data)
        }
        if let data = pasteboard.data(forType: .tiff) {
            return NSImage(data: data)
        }
        return nil
    }

    /// 当前剪贴板是否有可推送的内容（文本或图片）。
    var hasContent: Bool {
        if let t = pasteboard.string(forType: .string), !t.isEmpty { return true }
        if pasteboard.data(forType: .png) != nil { return true }
        if pasteboard.data(forType: .tiff) != nil { return true }
        return false
    }

    /**
     * 手动推送当前剪贴板内容到服务器。
     * 与自动 tick 不同，这里会强制放行（重置签名），因为用户明确点了「推送」按钮。
     * 返回推送类型（"text" / "image" / nil），供 UI 给出 Toast 反馈。
     */
    @discardableResult
    func manualPush() -> String? {
        // 重置签名，确保用户手动触发的推送一定能发出去
        lastSignature = ""

        // 优先文本
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            wsClient?.sendClipboardText(text)
            NSLog("[Clipboard] ↑ 手动推送文本 \(text.count) 字符")
            // 记录签名避免自动 tick 重复发
            lastSignature = "text:\(text.hashValue)"
            return "text"
        }

        // 尝试图片（PNG / TIFF → 压缩后发送）
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let (b64, mime) = ClipboardImageCompressor.compress(data) {
            wsClient?.sendClipboardImage(base64: b64, mime: mime)
            NSLog("[Clipboard] ↑ 手动推送图片 (base64 \(b64.count) 字符)")
            lastSignature = "img:\(data.count)"
            return "image"
        }

        return nil
    }

    private func tick() {
        guard isEnabled else { return }
        let cc = pasteboard.changeCount
        if cc == lastChangeCount { return }
        lastChangeCount = cc

        if suppressCount > 0 {
            suppressCount -= 1
            return
        }

        // 优先文本
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let sig = "text:\(text.hashValue)"
            if sig == lastSignature { return }
            lastSignature = sig
            wsClient?.sendClipboardText(text)
            NSLog("[Clipboard] ↑ 上传文本 \(text.count) 字符")
            return
        }

        // 尝试图片（PNG / TIFF → 压缩后发送）
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let (b64, mime) = ClipboardImageCompressor.compress(data) {
            let sig = "img:\(data.count)"
            if sig == lastSignature { return }
            lastSignature = sig
            wsClient?.sendClipboardImage(base64: b64, mime: mime)
            NSLog("[Clipboard] ↑ 上传图片 (base64 \(b64.count) 字符)")
        }
    }
}
