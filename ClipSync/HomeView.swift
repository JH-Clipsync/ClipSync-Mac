import SwiftUI
import AppKit

// ============================================================
// HomeView：主页 —— 集中式控制台
// - 顶部：大号连接状态卡（图标 + 状态文字 + 服务器地址）
// - 中部：服务器/Token 配置（合并自设置页）
// - 同步开关：自动同步剪贴板 + 接收弹窗
// - 统计 + 最近消息
// ============================================================

struct HomeView: View {
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore

    @State private var revealToken = false
    @State private var pushToast: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                serverCard
                syncCard
                infoGrid
                latestSection
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 17, weight: .semibold))
                Text(settings.serverURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            VStack(spacing: 6) {
                if ws.state == .connecting {
                    Button {
                        ws.stop()
                    } label: {
                        Label("取消", systemImage: "xmark")
                            .font(.system(size: 12))
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.bordered)
                } else if ws.state == .connected {
                    Button {
                        ws.stop()
                    } label: {
                        Label("断开", systemImage: "bolt.slash")
                            .font(.system(size: 12))
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        ws.start(server: settings.serverURL, token: settings.token)
                    } label: {
                        Label("连接", systemImage: "bolt.fill")
                            .font(.system(size: 12))
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(settings.token.isEmpty)
                }

                if let toast = pushToast {
                    Text(toast)
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 服务器 / Token 配置

    private var serverCard: some View {
        cardSection(title: "服务器", color: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    TextField("服务器地址 (ws://...)", text: $settings.serverURL)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Group {
                        if revealToken {
                            TextField("Token", text: $settings.token)
                        } else {
                            SecureField("Token", text: $settings.token)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button {
                        revealToken.toggle()
                    } label: {
                        Image(systemName: revealToken ? "eye.slash.fill" : "eye.fill")
                            .frame(width: 16)
                    }
                    .buttonStyle(.borderless)
                    .help(revealToken ? "隐藏 Token" : "显示 Token")
                }
            }
        }
    }

    // MARK: - 同步开关

    private var syncCard: some View {
        cardSection(title: "同步", color: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.autoSyncClipboard) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(.indigo)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动同步剪贴板")
                                .font(.system(size: 13, weight: .medium))
                            Text("电脑复制的内容实时推送到手机")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $settings.showContent) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示消息内容")
                                .font(.system(size: 13, weight: .medium))
                            Text("关闭后弹窗只显示占位提示")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: - 通用卡片容器

    private func cardSection<Content: View>(
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - 状态样式

    private var statusText: String {
        switch ws.state {
        case .connected:    return "已连接"
        case .connecting:   return "连接中…"
        case .disconnected: return "未连接"
        }
    }

    private var statusColor: Color {
        switch ws.state {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .gray
        }
    }

    private var statusIcon: String {
        switch ws.state {
        case .connected:    return "checkmark.circle.fill"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .disconnected: return "bolt.slash.fill"
        }
    }

    // MARK: - 统计 / 最近消息

    private var infoGrid: some View {
        HStack(spacing: 10) {
            statTile(title: "短信", value: "\(history.filtered(.sms).count)", color: .blue, icon: "message.fill")
            statTile(title: "剪贴板", value: "\(history.filtered(.clipboard).count)", color: .indigo, icon: "doc.on.clipboard")
        }
    }

    private func statTile(title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("最近消息")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let latest = history.allMessages.first {
                latestRow(latest)
            } else {
                HStack {
                    Text("暂无消息")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
    }

    private func latestRow(_ msg: SyncMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: msg.isSms ? "message.fill" : "doc.on.clipboard")
                .font(.system(size: 13))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(msg.isSms ? "短信" : "剪贴板")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(timeString(msg.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if isImage(msg) {
                    if let img = imageOf(msg) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onTapGesture { ImagePreviewWindows.show(image: img) }
                            .help("点击预览大图")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(previewText(msg))
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                } else {
                    Text(previewText(msg))
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let code = extractedCode(msg) {
                        Button {
                            copyText(code)
                        } label: {
                            Label("复制 \(code)", systemImage: "number.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button {
                        ClipboardWriter.apply(payload: msg.payload)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if isImage(msg), let img = imageOf(msg) {
                        Button {
                            ImagePreviewWindows.show(image: img)
                        } label: {
                            Label("预览", systemImage: "eye")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func isImage(_ msg: SyncMessage) -> Bool {
        msg.content == MessageContent.image && msg.payload.data != nil
    }

    private func imageOf(_ msg: SyncMessage) -> NSImage? {
        guard let b64 = msg.payload.data,
              let data = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: data)
    }

    private func extractedCode(_ msg: SyncMessage) -> String? {
        guard msg.isSms, let text = msg.payload.text else { return nil }
        return SmsCodeExtractor.extract(from: text)
    }

    private func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        ClipboardMonitor.shared.suppressNext()
        ClipboardMonitor.shared.markSignature("text:\(s.hashValue)")
    }

    private func previewText(_ msg: SyncMessage) -> String {
        if let t = msg.payload.text, !t.isEmpty { return t }
        if let p = msg.payload.preview, !p.isEmpty { return p }
        if msg.payload.mime?.hasPrefix("image/") == true { return "[图片]" }
        return "新消息"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
