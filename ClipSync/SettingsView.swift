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
            TextField("服务器地址", text: $settings.serverURL)
                .disabled(ws.state != .disconnected)

            // 账号密码常驻显示：连接时才做校验，所以没有单独的「登录」按钮。
            // 账号由管理员在服务端创建，客户端不提供注册入口。
            TextField("用户名", text: $settings.username)
                .disabled(ws.state != .disconnected)
            RevealPasswordField(
                title: "密码",
                text: $settings.password,
                isRevealed: $revealLoginPassword,
                isEnabled: ws.state == .disconnected
            )

            HStack(spacing: 10) {
                Button {
                    Task { await ws.connect(settings: settings) }
                } label: {
                    HStack(spacing: 6) {
                        if ws.state == .connecting {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                            Text("连接中…")
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                            Text("连接")
                        }
                    }
                    .frame(minWidth: 80)
                }
                .disabled(ws.state != .disconnected || !settings.hasCredentials)

                Button {
                    ws.stop()
                } label: {
                    Label("断开", systemImage: "xmark.circle")
                }
                .disabled(ws.state == .disconnected)

                Spacer()

                if settings.isLoggedIn {
                    Label("Token 已签发", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !settings.hasCredentials {
                Text("请填写用户名和密码（账号由管理员创建）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let authError = ws.authError {
                Label(authError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 加密

    @ViewBuilder
    private var encryptionSection: some View {
        Section("端到端加密") {
            Toggle("启用端到端加密", isOn: $settings.e2eeEnabled)

            RevealPasswordField(
                title: "同步密码",
                text: $settings.syncPassword,
                isRevealed: $revealSyncPassword,
                isEnabled: settings.e2eeEnabled
            )

            if settings.encryptionActive,
               let fp = PayloadCipher.fingerprint(password: settings.syncPassword) {
                LabeledContent("密钥指纹", value: fp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let failure = ws.decryptFailure {
                Label(failure, systemImage: "lock.trianglebadge.exclamationmark.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 动作

}
