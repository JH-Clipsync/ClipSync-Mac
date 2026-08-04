import SwiftUI

// ============================================================
// 带"小眼睛"的密码输入框
//
// SwiftUI 没有内置的可切换明文/密文的字段，SecureField 和 TextField
// 是两个独立控件，只能按状态二选一渲染。这里把这套模式收成一个组件，
// 免得登录密码和同步密码各写一份。
// ============================================================
struct RevealPasswordField: View {
    let title: String
    @Binding var text: String
    /// 明文/密文由外部持有，切换页面时状态不会丢
    @Binding var isRevealed: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!isEnabled)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
            .help(isRevealed ? "隐藏\(title)" : "显示\(title)")
        }
    }
}
