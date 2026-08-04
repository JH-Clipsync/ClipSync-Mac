import SwiftUI

// ============================================================
// Toast 视觉样式集中定义
//
// 圆角半径要在三个地方保持一致：SwiftUI 的 clipShape、NSVisualEffectView 的
// layer、NSHostingView 的 layer。散着写迟早对不上，于是收到这里。
//
// 配色对齐 macOS 系统通知：以白色为主，灰色只承担次要角色。
//
// 底板用近白的亮面，文字靠 .primary/.secondary 的黑灰分级，分隔和描边用极淡
// 的灰。整体明快，不再是一整块灰。
//
// 材质必须用 .popover 而不是 .hudWindow —— 后者是深灰 HUD 风格，底子就是暗
// 的，叠多少浅色染色都压不住，这是之前"太灰"的根因。
// ============================================================
enum ToastStyle {
    /// 弹窗圆角
    static let cornerRadius: CGFloat = 12
    /// 内部小卡片（图片卡、胶囊）的圆角
    static let innerCornerRadius: CGFloat = 10

    /// 主按钮底色：中性深灰，浅灰底上唯一的重色
    static let accentFill = Color(white: 0.28)
    /// 主按钮完成态：再压暗一档，作为"已复制"的反馈
    static let accentFillStrong = Color(white: 0.18)
    /// 次要按钮底色：比卡片底亮一档，靠描边区分
    static let secondaryFill = Color(white: 0.97)
    /// 次要按钮描边（取自系统通知的间隙灰 177/255≈0.69）
    static let secondaryStroke = Color(white: 0.69)

    /// 图标兜底底色：拿不到 App 图标时用中性深灰渐变
    static let iconGradient = LinearGradient(
        colors: [Color(white: 0.40), Color(white: 0.26)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 图片卡底色：比卡片底亮一档，用来托住图片
    static let imageCardFill = Color(white: 0.97)

    /// 弹窗外描边：取系统通知的间隙灰，把卡片从桌面上分离出来
    static let borderColor = Color(white: 0.69).opacity(0.55)
    /// 内部小卡片描边
    static let innerBorderColor = Color.black.opacity(0.10)
    /// 阴影：中性黑，柔和扩散
    static let shadowColor = Color.black.opacity(0.20)

    /// 背板染色：盖一层中性浅灰，对齐系统通知实测的 RGB(223,223,223)。
    ///
    /// 用 0.875 而不是纯白：参考图里卡片亮度是 223 而非 255，略暗一档才有
    /// "卡片"的质感。留一点透明度让底下的模糊透出来。
    static let backdropTint = Color(white: 0.875).opacity(0.86)
}
