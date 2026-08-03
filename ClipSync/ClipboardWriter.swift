import AppKit

// ============================================================
// ClipboardWriter：把远端消息应用到本机剪贴板
// ============================================================

enum ClipboardWriter {
    /// 根据 payload 类型写入剪贴板（文本 / 图片）
    static func apply(payload: MessagePayload) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let mime = payload.mime, mime.hasPrefix("image/"),
           let b64 = payload.data,
           let data = Data(base64Encoded: b64),
           let img = NSImage(data: data) {
            // 转成 PNG 写入剪贴板，确保 peekImage() 能稳定读取
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            } else {
                pb.writeObjects([img])
            }
            ClipboardMonitor.shared.suppressNext()
            ClipboardMonitor.shared.markSignature("img:\(data.count)")
            NSLog("[Clipboard] ↓ 已写入图片")
        } else if let text = payload.text, !text.isEmpty {
            pb.setString(text, forType: .string)
            ClipboardMonitor.shared.suppressNext()
            ClipboardMonitor.shared.markSignature("text:\(text.hashValue)")
            NSLog("[Clipboard] ↓ 已写入文本 \(text.count) 字符")
        }
    }
}
