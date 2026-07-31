import Foundation
import AppKit
import Combine

// ============================================================
// ClipboardMonitor：轮询 NSPasteboard.changeCount，检测本机剪贴板变化
// - macOS 没有剪贴板变化通知，只能 0.6s 轮询一次
// - 需要过滤"自己写入的内容"（收到远端消息后写回时不再上传）
// - 通过 suppressNext() + markSignature() 双重去重
// ============================================================

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

        // 尝试图片（TIFF → PNG）
        if let data = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            let sig = "img:\(png.count)"
            if sig == lastSignature { return }
            lastSignature = sig
            let b64 = png.base64EncodedString()
            wsClient?.sendClipboardImage(base64: b64)
            NSLog("[Clipboard] ↑ 上传图片 \(png.count) 字节")
        }
    }
}
