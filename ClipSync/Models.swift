import Foundation

/// 端到端加密信封。字段与服务端 e2ee.go 的 EncEnvelope、Android 的 EncEnvelope 一一对应。
struct EncEnvelope: Codable, Equatable {
    var v: Int          // 协议版本
    var alg: String     // AES-256-GCM
    var kdf: String     // PBKDF2-HMAC-SHA256
    var iter: Int       // KDF 迭代次数
    var salt: String    // base64
    var iv: String      // base64，12 字节 nonce
    var ct: String      // base64，密文 + GCM tag
    var fp: String      // 密钥指纹（hex 前 16 位）
}

/// 跟云端协议一致的载荷
struct MessagePayload: Codable, Equatable {
    var text: String?
    var mime: String?
    var data: String?       // base64（图片等二进制）
    var preview: String?    // 短预览
    var kind: String?       // 业务子类型：sms_code / text / image / share ...
    var sender: String?     // 短信发件人（服务端清洗后填入，如手机号 15735961954）

    /// 加密信封。非空时 text/data 等字段为空，真实内容在 enc.ct 里。
    var enc: EncEnvelope?
}

/// 消息类型（传输通道 / 推送范围），跟服务端 TypeXxx 常量一致。
/// 决定服务端把这条消息投递给同 token 下的哪些客户端。
enum MessageType {
    static let notifyPC     = "notify_pc"      // 只发 PC
    static let notifyMobile = "notify_mobile"  // 只发移动端
    static let notifyAll    = "notify_all"     // 广播
    static let clipboard    = "clipboard"      // 剪贴板同步
    static let serverKick   = "server_kick"    // 服务端踢下线通知
    static let presence     = "presence"       // 在线设备列表变更（服务端下发）
}

/// 在线设备（服务端 presence 消息里的一台设备）
struct OnlineDevice: Codable, Identifiable, Equatable {
    var deviceID: String
    var role: String
    var ip: String
    var onlineAt: Int64
    var isSelf: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case role
        case ip
        case onlineAt = "online_at"
        case isSelf = "self"
    }

    var id: String { deviceID }

    /// 角色中文标签
    var roleLabel: String {
        switch role {
        case "mobile": return "手机"
        case "pc":     return "电脑"
        default:       return role
        }
    }

    /// 设备类型图标
    var roleIcon: String {
        switch role {
        case "mobile": return "iphone"
        case "pc":     return "desktopcomputer"
        default:       return "questionmark.circle"
        }
    }
}

/// 消息业务子类型（payload.kind）
enum MessageKind {
    static let smsCode  = "sms_code"
    static let text     = "text"
    static let image    = "image"
    static let share    = "share"
}

/// MessageCategory：消息业务大类。用于日志与 UI 分组，跟 MessageType（推送通道）解耦。
/// 三端约定值：sms / clipboard / notification。
enum MessageCategory {
    static let sms          = "sms"
    static let clipboard    = "clipboard"
    static let notification = "notification"

    /// 根据传输类型 + payload.kind 判定业务大类，与服务端 categorize() 保持一致
    static func of(type: String, kind: String?) -> String {
        let k = kind ?? ""
        if k.hasPrefix("sms") { return sms }
        if type == MessageType.clipboard
            || k == MessageKind.text
            || k == MessageKind.image
            || k == MessageKind.share {
            return clipboard
        }
        return notification
    }
}

/// MessageContent：内容格式。三端约定值：text / image。
enum MessageContent {
    static let text  = "text"
    static let image = "image"

    /// 根据 payload.kind + payload.mime 判定内容格式，与服务端 contentTypeOf() 保持一致
    static func of(kind: String?, mime: String?) -> String {
        let k = kind ?? ""
        let m = mime ?? ""
        if k == image || m.hasPrefix("image/") { return image }
        return text
    }
}

/// 统一消息结构
struct SyncMessage: Codable, Identifiable, Equatable {
    var id: String
    var type: String        // notify_pc | notify_mobile | notify_all | clipboard
    var from: String
    var to: String
    var ts: Int64
    var payload: MessagePayload

    /// 收到消息时的时间：ts 可能是秒或毫秒时间戳
    var date: Date {
        // ts 大于 1e12 时视为毫秒
        if ts > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
        }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// 业务子类型（payload.kind），没有时按 type 兜底
    var kind: String {
        if let k = payload.kind, !k.isEmpty { return k }
        // 兼容旧格式
        if type == MessageType.clipboard {
            if let mime = payload.mime, mime.hasPrefix("image/") { return MessageKind.image }
            return MessageKind.text
        }
        return type
    }

    /// 业务大类：sms / clipboard / notification
    var category: String { MessageCategory.of(type: type, kind: payload.kind) }

    /// 内容格式：text / image
    var content: String { MessageContent.of(kind: payload.kind, mime: payload.mime) }

    /// 是否属于剪贴板类
    var isClipboard: Bool {
        category == MessageCategory.clipboard
    }

    /// 是否属于短信/验证码类
    var isSms: Bool {
        category == MessageCategory.sms
    }

    /// 展示层面"看起来像短信"：kind 判定为短信，或文本带短信特征标记。
    /// 手机端推送经常不带 payload.kind，isSms 会漏判，
    /// 文本里出现【号码】/ [N条] 这类标记时同样按短信清洗和展示。
    var looksLikeSms: Bool {
        if isSms { return true }
        let raw = payload.text ?? payload.preview ?? ""
        return SmsPayloadSanitizer.hasSmsMarkers(raw)
    }
}
