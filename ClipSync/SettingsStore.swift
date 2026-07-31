import Foundation
import Combine

// ============================================================
// 设置存储：服务器地址、token、显示内容、自动同步剪贴板
// 用 UserDefaults 持久化，@Published 让 SwiftUI 自动感知
// ============================================================

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    /// true=弹窗显示消息内容；false=只显示占位
    @Published var showContent: Bool {
        didSet { UserDefaults.standard.set(showContent, forKey: "showContent") }
    }
    /// true=本机剪贴板变化自动同步到服务端
    @Published var autoSyncClipboard: Bool {
        didSet { UserDefaults.standard.set(autoSyncClipboard, forKey: "autoSyncClipboard") }
    }

    private init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "serverURL") ?? "ws://localhost:8080"
        token = d.string(forKey: "token") ?? ""
        showContent = d.object(forKey: "showContent") as? Bool ?? true
        autoSyncClipboard = d.object(forKey: "autoSyncClipboard") as? Bool ?? true
    }
}
