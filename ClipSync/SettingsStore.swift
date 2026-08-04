import Foundation
import Combine

// ============================================================
// 设置存储：服务器地址、账号、同步密码、显示内容、自动同步剪贴板
//
// token 不再手填，也没有「登录」按钮：账号密码存在本地，
// 连接时自动换 token。账号由管理员在服务端创建。
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
    /// 登录密码。连接时用它换 token，所以要持久化。
    /// 注意与 syncPassword 区分：这个要发给服务端校验，那个永不出本机。
    @Published var password: String {
        didSet {
            UserDefaults.standard.set(password, forKey: "password")
            // 改了密码，本地 token 可能已经对不上账号，作废让它重新换
            if !password.isEmpty { token = "" }
        }
    }
    /// 服务端签发的 token（登录后自动写入，不需要用户手填）
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    /// 端到端加密用的同步密码。只存本机，两端填一致才能互相解密。
    @Published var syncPassword: String {
        didSet {
            // 值没变就别动缓存：边打字边触发时，无脑清缓存会让每次输入都重新跑
            // 20 万轮 PBKDF2（手机端实测 2.8 秒，Mac 端约 50ms）
            guard syncPassword != oldValue else { return }
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

    /// 实际用来派生密钥的密码。
    ///
    /// 开关关闭 → 空串（明文传输）；
    /// 开关打开但用户没填 → 内置默认密码，避免「开了加密却在发明文」；
    /// 开关打开且填了 → 用户自己的密码。
    var effectiveSyncPassword: String {
        guard e2eeEnabled else { return "" }
        return syncPassword.isEmpty ? E2EECrypto.builtinSyncPassword : syncPassword
    }

    /// 当前是否在用内置默认密码（界面据此提示用户）
    var usingBuiltinSyncPassword: Bool { e2eeEnabled && syncPassword.isEmpty }

    /// 加密是否生效。开关打开就一定生效——没填密码时走内置默认密码。
    var encryptionActive: Bool { e2eeEnabled }

    /// 已登录 = 本地有 token
    var isLoggedIn: Bool { !token.isEmpty }

    /// 账号密码都填了才能连接（连接时自动换 token）
    var hasCredentials: Bool { !username.isEmpty && !password.isEmpty }

    private init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "serverURL") ?? "ws://localhost:8080"
        username = d.string(forKey: "username") ?? ""
        password = d.string(forKey: "password") ?? ""
        token = d.string(forKey: "token") ?? ""
        syncPassword = d.string(forKey: "syncPassword") ?? ""
        e2eeEnabled = d.object(forKey: "e2eeEnabled") as? Bool ?? true
        showContent = d.object(forKey: "showContent") as? Bool ?? true
        autoSyncClipboard = d.object(forKey: "autoSyncClipboard") as? Bool ?? true
    }
}
