import SwiftUI

// ============================================================
// 带"小眼睛"的密码输入框
//
// 布局：[可选标签] [输入框] [眼睛按钮]
// 明文/密文两个输入框同时存在、叠在一起，用透明度切换，
// 切换时输入框大小位置完全不变。
//
// showLabel=false 时不画左侧标签、也不画自带边框（交给外部容器统一画
// 带图标的边框），用于设置页统一的输入框外观。
// ============================================================
struct RevealPasswordField: View {
    let title: String
    @Binding var text: String
    @Binding var isRevealed: Bool
    var isEnabled: Bool = true
    var showLabel: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showLabel {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            inputLayer
                .frame(maxWidth: .infinity)

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

    @ViewBuilder
    private var inputLayer: some View {
        if showLabel {
            inputFields.textFieldStyle(.roundedBorder)
        } else {
            inputFields.textFieldStyle(.plain)
        }
    }

    @ViewBuilder
    private var inputFields: some View {
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
                TextField("", text: $text)
                    .opacity(isRevealed ? 1 : 0)
                    .allowsHitTesting(isRevealed)
                SecureField("", text: $text)
                    .opacity(isRevealed ? 0 : 1)
                    .allowsHitTesting(!isRevealed)
            }
        }
    }
}
