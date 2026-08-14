import SwiftUI

// ============================================================
// 带"小眼睛"的密码输入框
//
// 布局：[标签] [固定宽度输入框] [眼睛按钮]
// 明文/密文两个输入框都用空标题、放在固定 frame 的 ZStack 里，
// 眼睛按钮在输入框外部独立占位，切换时光标和边框都不会跳动。
// ============================================================
struct RevealPasswordField: View {
    let title: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            // 输入框区域：明文/密文两个字段同时存在、叠在一起，
            // 用透明度切换可见性。它们共享同一个 frame，切换时尺寸位置完全不变。
            ZStack {
                if !isEnabled && !isRevealed {
                    SecureField("", text: .constant(text))
                        .disabled(true)
                } else if !isEnabled {
                    Text(text.isEmpty ? "未设置" : text)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                } else {
                    // 可编辑态：明文/密文两个字段叠在一起，同时存在于视图树
                    TextField("", text: $text)
                        .opacity(isRevealed ? 1 : 0)
                        .allowsHitTesting(isRevealed)
                    SecureField("", text: $text)
                        .opacity(isRevealed ? 0 : 1)
                        .allowsHitTesting(!isRevealed)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .frame(height: 22)

            // 眼睛按钮在输入框外部，独立占位
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "隐藏\(title)" : "显示\(title)")
        }
    }
}
