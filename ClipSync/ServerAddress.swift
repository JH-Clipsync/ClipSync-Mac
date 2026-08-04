import Foundation

// ============================================================
// 服务器地址规范化
//
// 用户在设置里只需要填 `192.168.1.10:8080` 或 `example.com`，
// `ws://` 前缀由程序补齐。443 端口和 https 输入会归一到 `wss://`。
//
// 对应 Android 端 ServerAddress.kt，两端行为保持一致。
// ============================================================
enum ServerAddress {

    /// 把用户输入补成完整的 WebSocket 地址。
    /// 空输入返回空串，交由调用方提示「请填写服务器地址」。
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return "" }

        if s.hasPrefix("ws://") || s.hasPrefix("wss://") { return s }
        // http/https 是常见误填，直接映射到对应的 WebSocket scheme
        if s.hasPrefix("https://") { return "wss://" + s.dropFirst("https://".count) }
        if s.hasPrefix("http://") { return "ws://" + s.dropFirst("http://".count) }
        // 443 端口默认按 TLS 处理，省得用户再手填 wss
        if s.hasSuffix(":443") { return "wss://" + s }
        return "ws://" + s
    }

    /// 界面展示用：去掉 scheme，输入框里就不必出现 `ws://` 了
    static func displayForm(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["wss://", "ws://", "https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
