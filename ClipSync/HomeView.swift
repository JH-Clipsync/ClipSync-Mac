import SwiftUI

// ============================================================
// HomeView：主页 —— 连接状态一览
// - 大号状态卡（图标 + 状态文字 + 服务器地址）
// - 快速统计（短信条数 / 剪贴板条数 / 设备 ID）
// - 最近一条消息预览
// ============================================================

struct HomeView: View {
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                infoGrid
                latestSection
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 大号状态卡

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 20) {
            // 左侧：状态圆
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: statusIcon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            // 右侧：状态文字
            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(statusDesc)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if ws.state == .disconnected {
                        Button {
                            ws.start(server: settings.serverURL, token: settings.token)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.horizontal.fill")
                                Text("立即连接")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(settings.token.isEmpty)
                    } else if ws.state == .connecting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).scaleEffect(0.75)
                            Text("正在连接…").font(.system(size: 12))
                        }
                    } else {
                        Button {
                            ws.stop()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("断开连接")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(statusColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 信息网格

    private var infoGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            infoCard(icon: "server.rack",
                     label: "服务器",
                     value: settings.serverURL.isEmpty ? "（未设置）" : settings.serverURL,
                     tint: .blue)

            infoCard(icon: "key.fill",
                     label: "Token",
                     value: settings.token.isEmpty ? "（未设置）" : maskToken(settings.token),
                     tint: .purple,
                     secret: true)

            infoCard(icon: "desktopcomputer",
                     label: "设备 ID",
                     value: ws.deviceID,
                     tint: .teal,
                     monospaced: true)

            infoCard(icon: "arrow.left.arrow.right",
                     label: "自动同步剪贴板",
                     value: settings.autoSyncClipboard ? "已开启" : "已关闭",
                     tint: settings.autoSyncClipboard ? .green : .gray)

            infoCard(icon: "message.badge",
                     label: "短信消息",
                     value: "\(smsCount) 条",
                     tint: .orange)

            infoCard(icon: "doc.on.clipboard",
                     label: "剪贴板消息",
                     value: "\(clipboardCount) 条",
                     tint: .pink)
        }
    }

    private func infoCard(icon: String, label: String, value: String,
                          tint: Color, monospaced: Bool = false,
                          secret: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Group {
                    if secret {
                        // Token / 密文：不可选、不可复制
                        Text(value)
                            .textSelection(.disabled)
                    } else {
                        Text(value)
                            .textSelection(.enabled)
                    }
                }
                .font(monospaced
                      ? .system(size: 12, design: .monospaced)
                      : .system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        // 对密文字段整体禁用 hit-testing 里的文本选择行为
        .allowsHitTesting(true)
    }

    // MARK: - 最近消息

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近消息")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !history.messages.isEmpty {
                    Text("共 \(history.messages.count) 条")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if let msg = history.messages.first {
                latestRow(msg)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("暂无消息，等待手机端推送…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    private func latestRow(_ msg: SyncMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: msg.isSms ? "message.fill" : "doc.on.clipboard")
                .font(.system(size: 14))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(msg.isSms ? "短信" : "剪贴板")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(timeString(msg.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(previewText(msg))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - helpers

    private var statusColor: Color {
        switch ws.state {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .red
        }
    }

    private var statusIcon: String {
        switch ws.state {
        case .connected:    return "bubble.left.and.bubble.right.fill"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .disconnected: return "bubble.left.and.bubble.right"
        }
    }

    private var statusTitle: String {
        switch ws.state {
        case .connected:    return "已连接"
        case .connecting:   return "连接中…"
        case .disconnected: return "未连接"
        }
    }

    private var statusDesc: String {
        switch ws.state {
        case .connected:
            return "正在与服务器 \(settings.serverURL) 保持长连接，消息将实时同步。"
        case .connecting:
            return "正在与 \(settings.serverURL) 握手，请稍候…"
        case .disconnected:
            if settings.token.isEmpty {
                return "尚未配置 Token。请到「设置」填写服务器地址和 Token 后再连接。"
            }
            return "已断开与服务器的连接，可点右边按钮重新连接。"
        }
    }

    private var smsCount: Int       { history.smsCount }
    private var clipboardCount: Int { history.clipboardCount }

    /// Token 完全用 • 遮蔽，不显示前缀后缀（相当于密码）
    private func maskToken(_ s: String) -> String {
        let n = min(max(s.count, 4), 12)   // 至少 4 个点，至多 12 个点
        return String(repeating: "•", count: n)
    }

    private func previewText(_ msg: SyncMessage) -> String {
        if !settings.showContent { return "收到一条新消息" }
        if let t = msg.payload.text, !t.isEmpty { return t }
        if let p = msg.payload.preview, !p.isEmpty { return p }
        if let mime = msg.payload.mime, mime.hasPrefix("image/") { return "[图片]" }
        return "新消息"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
