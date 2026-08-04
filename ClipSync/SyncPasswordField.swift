import SwiftUI

// ============================================================
// 同步密码输入框（带「确定」按钮）
//
// 保存同步密码的代价很高：会触发 20 万轮 PBKDF2 派生密钥（Mac 上约 40ms，
// 手机端实测 2.8 秒）。所以输入先落在本地草稿里，用户点「确定」或按回车
// 才真正写入 SettingsStore。
//
// 主界面和设置页各有一个同步密码输入框，共用这个组件，避免两处逻辑走偏。
// 对应 Android 端 FuncSettingsActivity 里 passwordRow(onConfirm:) 的行为。
// ============================================================
struct SyncPasswordField: View {
    @ObservedObject var settings: SettingsStore
    /// 明文/密文由外部持有，切换页面时状态不会丢
    @Binding var isRevealed: Bool
    /// 提示文字的字号，主界面和设置页各有各的排版
    var captionSize: CGFloat = 11

    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RevealPasswordField(
                    title: "同步密码（留空则用内置默认密码）",
                    text: $draft,
                    isRevealed: $isRevealed
                )
                .onSubmit(apply)

                Button("确定", action: apply)
                    .disabled(!isDirty)
                    .help("保存同步密码并重新派生密钥")
            }

            if isDirty {
                Text("同步密码已修改，点「确定」后生效")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.orange)
            }
        }
        // 首次出现时把已保存的密码填进草稿
        .task {
            guard !loaded else { return }
            draft = settings.syncPassword
            loaded = true
        }
        // 已保存值被改动时跟着更新草稿。
        //
        // 主界面和设置页各有一个实例、各持一份草稿：在一边保存后，另一边的
        // 草稿若还留着旧值，就会一直显示"已修改"，用户点确定反而把密码改回去。
        .onChange(of: settings.syncPassword) { _, newValue in
            draft = newValue
        }
    }

    private var isDirty: Bool { draft != settings.syncPassword }

    /// 提交同步密码：这一步才会写 UserDefaults 并触发密钥派生
    private func apply() {
        guard isDirty else { return }
        settings.syncPassword = draft
    }
}
