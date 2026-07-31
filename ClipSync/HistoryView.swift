import SwiftUI

// ============================================================
// HistoryView：消息历史列表（短信 / 剪贴板）
// - 从 WSClient.history 筛出对应类型消息
// - 每行显示图标 + 标题 + 时间 + 内容
// - 短信自动提取验证码，展示"复制验证码"按钮
// ============================================================

struct HistoryView: View {
    let filter: Filter

    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore

    enum Filter { case sms, clipboard }

    private var items: [SyncMessage] {
        switch filter {
        case .sms:       return history.filtered(.sms)
        case .clipboard: return history.filtered(.clipboard)
        }
    }

    var body: some View {
        if items.isEmpty {
            emptyView
        } else {
            List(items) { msg in
                Row(message: msg, showContent: settings.showContent)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .listStyle(.inset)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        history.clear(filter: filter == .sms ? .sms : .clipboard)
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .help("清空历史（仅本机）")
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .sms ? "tray" : "doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(filter == .sms ? "暂无短信消息" : "暂无剪贴板消息")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 单行

private struct Row: View {
    let message: SyncMessage
    let showContent: Bool

    @State private var codeCopied = false
    @State private var allCopied  = false

    private var extractedCode: String? {
        guard message.isSms, let text = message.payload.text else { return nil }
        return SmsCodeExtractor.extract(from: text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let phone = extractedPhone {
                        Text(phone)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    Spacer()
                    Text(timeString).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Text(bodyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let code = extractedCode {
                        Button {
                            copyText(code); codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { codeCopied = false }
                        } label: {
                            Label(codeCopied ? "已复制 \(code) ✓" : "复制 \(code)",
                                  systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            ClipboardWriter.apply(payload: message.payload); allCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                        } label: {
                            Label(allCopied ? "✓" : "全文", systemImage: "text.alignleft")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            ClipboardWriter.apply(payload: message.payload); allCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                        } label: {
                            Label(allCopied ? "已复制 ✓" : "复制", systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - subviews

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemIndigo)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - content helpers

    private var title: String {
        switch message.kind {
        case MessageKind.smsCode: return "短信验证码"
        case MessageKind.image:   return "剪贴板图片"
        case MessageKind.share:   return "分享"
        default:
            return message.type == MessageType.clipboard ? "剪贴板" : "通知"
        }
    }

    private var bodyText: String {
        if !showContent { return "收到一条新消息" }
        // 服务端已清洗完
        let raw: String = {
            if let t = message.payload.text, !t.isEmpty { return t }
            if let p = message.payload.preview, !p.isEmpty { return p }
            if let mime = message.payload.mime, mime.hasPrefix("image/") { return "[图片]" }
            return "新消息"
        }()
        // 手动截断，避免 SwiftUI 在紧凑布局下的头部截断 bug
        if raw.count <= 120 { return raw }
        return String(raw.prefix(120)) + "…"
    }

    /// 发件人：直接用服务端塞进来的 payload.sender
    private var extractedPhone: String? {
        message.payload.sender
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: message.date)
    }

    private var iconName: String {
        switch message.kind {
        case MessageKind.smsCode: return "message.fill"
        case MessageKind.image:   return "photo.fill"
        case MessageKind.share:   return "square.and.arrow.up.fill"
        default:                  return "doc.on.clipboard"
        }
    }

    private func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        ClipboardMonitor.shared.suppressNext()
        ClipboardMonitor.shared.markSignature("text:\(s.hashValue)")
    }
}
