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

    @State private var password = ""
    @State private var revealSyncPassword = false
    @State private var busy = false
    @State private var message: StatusMessage?

    /// 操作结果提示，成功和失败用不同颜色
    private struct StatusMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

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
                .disabled(settings.isLoggedIn)

            if settings.isLoggedIn {
                LabeledContent("已登录", value: settings.username)
                HStack(spacing: 10) {
                    Button {
                        ws.start(server: settings.serverURL, token: settings.token)
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
                    .disabled(ws.state != .disconnected)

                    Button {
                        ws.stop()
                    } label: {
                        Label("断开", systemImage: "xmark.circle")
                    }
                    .disabled(ws.state == .disconnected)

                    Spacer()

                    Button(role: .destructive) {
                        Task { await logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(busy)
                }
            } else {
                TextField("用户名", text: $settings.username)
                SecureField("密码", text: $password)

                HStack(spacing: 10) {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack(spacing: 6) {
                            if busy {
                                ProgressView().controlSize(.small).scaleEffect(0.7)
                            } else {
                                Image(systemName: "person.badge.key")
                            }
                            Text("登录")
                        }
                        .frame(minWidth: 80)
                    }
                    .disabled(busy || settings.username.isEmpty || password.isEmpty)

                    Button {
                        Task { await register() }
                    } label: {
                        Label("注册", systemImage: "person.badge.plus")
                    }
                    .disabled(busy || settings.username.isEmpty || password.isEmpty)
                }
            }

            if let authError = ws.authError {
                Label(authError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let message {
                Label(message.text, systemImage: message.isError
                      ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .green)
            }
        }
    }

    // MARK: - 加密

    @ViewBuilder
    private var encryptionSection: some View {
        Section("端到端加密") {
            Toggle("启用端到端加密", isOn: $settings.e2eeEnabled)

            HStack(spacing: 6) {
                Group {
                    if revealSyncPassword {
                        TextField("同步密码", text: $settings.syncPassword)
                    } else {
                        SecureField("同步密码", text: $settings.syncPassword)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .disabled(!settings.e2eeEnabled)

                Button {
                    revealSyncPassword.toggle()
                } label: {
                    Image(systemName: revealSyncPassword ? "eye.slash.fill" : "eye.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(revealSyncPassword ? "隐藏同步密码" : "显示同步密码")
            }

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

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            let session = try await AuthClient.shared.login(
                server: settings.serverURL,
                username: settings.username,
                password: password
            )
            settings.token = session.token
            settings.username = session.username
            password = ""
            message = StatusMessage(
                text: session.reused
                    ? "登录成功：已有 \(session.onlineDevices) 台设备在线，复用同一 Token"
                    : "登录成功：已为本次登录签发新 Token",
                isError: false
            )
            ws.start(server: settings.serverURL, token: session.token)
        } catch {
            message = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }

    private func register() async {
        busy = true
        defer { busy = false }
        do {
            try await AuthClient.shared.register(
                server: settings.serverURL,
                username: settings.username,
                password: password
            )
            message = StatusMessage(text: "注册成功，请点「登录」", isError: false)
        } catch {
            message = StatusMessage(text: error.localizedDescription, isError: true)
        }
    }

    private func logout() async {
        busy = true
        defer { busy = false }
        let server = settings.serverURL
        let token = settings.token
        ws.stop()
        settings.token = ""
        message = StatusMessage(text: "已退出登录", isError: false)
        // 通知服务端作废会话；失败也不影响本地已登出的事实
        try? await AuthClient.shared.logout(server: server, token: token)
    }
}
