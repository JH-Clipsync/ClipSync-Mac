import SwiftUI

// ============================================================
// SettingsView：设置页（服务器 / Token / 剪贴板同步 / 消息显示）
// ============================================================

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ws: WSClient

    /// 是否显示 Token 明文
    @State private var revealToken = false

    var body: some View {
        Form {
            Section("连接") {
                TextField("服务器地址", text: $settings.serverURL)

                HStack(spacing: 6) {
                    // 用 Group 切换 Secure/Plain，两种状态都能编辑
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
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(revealToken ? "隐藏 Token" : "显示 Token")
                }

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
                    .disabled(settings.token.isEmpty || ws.state != .disconnected)

                    Button {
                        ws.stop()
                    } label: {
                        Label("断开", systemImage: "xmark.circle")
                    }
                    .disabled(ws.state == .disconnected)
                }
            }

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
}
