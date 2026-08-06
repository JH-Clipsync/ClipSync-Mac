import Foundation
import Combine

// ============================================================
// HistoryStore：本地消息历史持久化
//
// 存储位置：
//   ~/Library/Application Support/ClipSync/history.json
//
// 特性：
//   - @Published messages 供 SwiftUI 直接使用
//   - append(_:) 自动去重（按 id）+ 按时间倒序 + 上限裁剪
//   - 每次变更立即写盘（debounce 200ms）
//   - 提供 sms / clipboard 过滤视图
// ============================================================

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// 全部历史消息（时间倒序，最新在前）
    @Published private(set) var messages: [SyncMessage] = []

    /// 最多保留多少条（避免文件无限增长）
    private let maxCount = 500

    /// 存盘 URL
    private let fileURL: URL

    /// 写盘的 debounce 定时器
    private var saveTimer: Timer?

    private init() {
        // ~/Library/Application Support/ClipSync/history.json
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appDir = dir.appendingPathComponent("ClipSync", isDirectory: true)
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("history.json")

        NSLog("[History] 存储路径: \(fileURL.path)")

        load()
    }

    // MARK: - 增

    /// 追加一条消息；已存在（同 id）则替换到最前
    func append(_ msg: SyncMessage) {
        DispatchQueue.main.async {
            // 去重：如果同 id 已存在，先移除
            self.messages.removeAll { $0.id == msg.id }
            self.messages.insert(msg, at: 0)
            // 裁剪
            if self.messages.count > self.maxCount {
                self.messages.removeLast(self.messages.count - self.maxCount)
            }
            self.scheduleSave()
        }
    }

    // MARK: - 删

    /// 清空全部
    func clear() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.scheduleSave()
        }
    }

    /// 按类型清空（.sms / .clipboard）
    func clear(filter: Filter) {
        DispatchQueue.main.async {
            switch filter {
            case .sms:       self.messages.removeAll { $0.looksLikeSms }
            case .clipboard: self.messages.removeAll { $0.isClipboard }
            }
            self.scheduleSave()
        }
    }

    /// 删除单条
    func remove(id: String) {
        DispatchQueue.main.async {
            self.messages.removeAll { $0.id == id }
            self.scheduleSave()
        }
    }

    // MARK: - 查

    enum Filter { case sms, clipboard }

    func filtered(_ filter: Filter) -> [SyncMessage] {
        switch filter {
        case .sms:       return messages.filter { $0.looksLikeSms }
        case .clipboard: return messages.filter { $0.isClipboard }
        }
    }

    /// 全部消息（按时间倒序，最新在前）
    var allMessages: [SyncMessage] { messages }

    var smsCount: Int       { messages.lazy.filter { $0.looksLikeSms }.count }
    var clipboardCount: Int { messages.lazy.filter { $0.isClipboard }.count }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[History] 无历史文件，从空开始")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let list = try JSONDecoder().decode([SyncMessage].self, from: data)
            self.messages = list
            NSLog("[History] 已加载 \(list.count) 条历史")
        } catch {
            NSLog("[History] 加载失败: \(error.localizedDescription)")
        }
    }

    /// 200ms debounce 后写盘
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[History] 保存失败: \(error.localizedDescription)")
        }
    }
}
