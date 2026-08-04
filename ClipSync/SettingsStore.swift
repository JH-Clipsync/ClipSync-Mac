import Foundation
import Combine

// ============================================================
// 设置存储：服务器地址、账号、同步密码、显示内容、自动同步剪贴板
//
// token 不再手填：由「用户名 + 密码」登录后从服务端换取并存在这里。
// 同步密码（syncPassword）是端到端加密的密钥来源，只留在本机，从不上传。
// 用 UserDefaults 持久化，@Published 让 SwiftUI 自动感知
// ============================================================

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    /// 登录用户名
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "username") }
    }
    /// 服务端签发的 token（登录后自动写入，不需要用户手填）
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    /// 端到端加密用的同步密码。只存本机，两端填一致才能互相解密。
    @Published var syncPassword: String {
        didSet {
            UserDefaults.standard.set(syncPassword, forKey: "syncPassword")
            // 密码变了，缓存的派生密钥立即失效
            PayloadCipher.invalidateKeyCache()
        }
    }
    /// 是否启用端到端加密（关闭时发明文；服务端 e2ee.require=true 会拒收）
    @Published var e2eeEnabled: Bool {
        didSet { UserDefaults.standard.set(e2eeEnabled, forKey: "e2eeEnabled") }
    }
    /// true=弹窗显示消息内容；false=只显示占位
    @Published var showContent: Bool {
        didSet { UserDefaults.standard.set(showContent, forKey: "showContent") }
    }
    /// true=本机剪贴板变化自动同步到服务端
    @Published var autoSyncClipboard: Bool {
        didSet { UserDefaults.standard.set(autoSyncClipboard, forKey: "autoSyncClipboard") }
    }

    /// 加密实际生效需要同时满足：开关打开 + 密码非空
    var encryptionActive: Bool { e2eeEnabled && !syncPassword.isEmpty }

    /// 已登录 = 本地有 token
    var isLoggedIn: Bool { !token.isEmpty }

    private init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "serverURL") ?? "ws://localhost:8080"
        username = d.string(forKey: "username") ?? ""
        token = d.string(forKey: "token") ?? ""
        syncPassword = d.string(forKey: "syncPassword") ?? ""
        e2eeEnabled = d.object(forKey: "e2eeEnabled") as? Bool ?? true
        showContent = d.object(forKey: "showContent") as? Bool ?? true
        autoSyncClipboard = d.object(forKey: "autoSyncClipboard") as? Bool ?? true
    }
}
