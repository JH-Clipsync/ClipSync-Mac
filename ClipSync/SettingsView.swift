import SwiftUI

// ============================================================
// SettingsView：设置页
//   账号   —— 用户名 + 密码登录换 token（token 不再手填）
//   加密   —— 同步密码，端到端加密的密钥来源，只留本机
//   同步 / 弹窗 / 关于
// ============================================================

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ws: WSClient

    @State private var revealSyncPassword = false
    @State private var revealLoginPassword = false

    var body: some View {
        Form {
            connectionSection
            encryptionSection

            Section("同步") {
                Toggle("自动同步本机剪贴板到手机", isOn: $settings.autoSyncClipboard)
            }

            Section("弹窗") {
                Toggle("显示消息内容（关闭时只显示占位提示）",
                       isOn: $settings.showContent)
            }

            Section("关于") {
                LabeledContent("设备 ID", value: ws.deviceID)
                    .font(.system(.body, design: .monospaced))
                Text("ClipSync · 短信验证码 / 剪贴板同步")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - 账号

    @ViewBuilder
    private var connectionSection: some View {
        Section("账号") {
            labeledField(label: "服务器地址", icon: "network") {
                TextField("", text: $settings.serverURL)
                    .textFieldStyle(.plain)
            }
            .disabled(ws.state != .disconnected)

            labeledField(label: "用户名", icon: "person.fill") {
                TextField("", text: $settings.username)
                    .textFieldStyle(.plain)
            }
            .disabled(ws.state != .disconnected)

            labeledField(label: "密码", icon: "lock.fill") {
                RevealPasswordField(
                    title: "",
                    text: $settings.password,
                    isRevealed: $revealLoginPassword,
                    isEnabled: ws.state == .disconnected,
                    showLabel: false
                )
            }

            // 快速操作：连接 / 断开。设置是实时绑定的，点「连接」即按当前填写的值生效。
            HStack(spacing: 10) {
                Button {
                    Task { await ws.connect(settings: settings) }
                } label: {
                    HStack(spacing: 6) {
                        if ws.state == .connecting {
                            ProgressView().controlSize(.small)
                            Text("连接中…")
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                            Text(settings.isLoggedIn ? "重新连接" : "保存并连接")
                        }
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(ws.state == .connecting || !settings.hasCredentials)

                Button {
                    ws.disconnect()
                } label: {
                    Label("断开", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(ws.state == .disconnected)

                Spacer()

                if settings.isLoggedIn {
                    Label("Token 已签发", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.top, 4)

            if let authError = ws.authError {
                Label(authError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 统一的「短标签 + 图标 + 带边框输入框」行，让输入区域明显可点。
    @ViewBuilder
    private func labeledField<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(alignment: .leading)
            Spacer(minLength: 16)
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                content()
            }
            .padding(.horizontal, 8)
            .frame(width: 300, height: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
    }

    // MARK: - 加密

    @ViewBuilder
    private var encryptionSection: some View {
        Section("端到端加密") {
            Toggle("启用端到端加密", isOn: $settings.e2eeEnabled)

            // 关闭加密时整行隐藏：明文传输下这个输入框没有意义
            if settings.e2eeEnabled {
                // 密码要点「确定」才保存：派生密钥很贵，不能跟着每次按键跑
                SyncPasswordField(
                    settings: settings,
                    isRevealed: $revealSyncPassword
                )
            }

            encryptionStatusText

            if let failure = ws.decryptFailure {
                Label(failure, systemImage: "lock.trianglebadge.exclamationmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 说清当前加密状态：明文 / 内置默认密码 / 自设密码
    @ViewBuilder
    private var encryptionStatusText: some View {
        if !settings.e2eeEnabled {
            Text("加密已关闭：消息以明文传输")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if settings.usingBuiltinSyncPassword {
                Label(
                    "未填同步密码，正在使用内置默认密码（各端通用，强度低于自设密码）",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            // 指纹在后台算，不阻塞 body 求值
            FingerprintLabel(password: settings.effectiveSyncPassword)
        }
    }

    // MARK: - 动作

}
