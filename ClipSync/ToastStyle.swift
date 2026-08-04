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

    /// 主按钮底色：中性深灰，在白底上作为唯一的重色，突出但不花
    static let accentFill = Color(red: 0.26, green: 0.27, blue: 0.29)
    /// 主按钮完成态：再压暗一档，作为"已复制"的反馈
    static let accentFillStrong = Color(red: 0.16, green: 0.17, blue: 0.19)
    /// 次要按钮底色：白底上的浅灰填充
    static let secondaryFill = Color(red: 0.93, green: 0.93, blue: 0.94)
    /// 次要按钮描边，让浅灰填充在白底上有边界
    static let secondaryStroke = Color.black.opacity(0.10)

    /// 图标底色：中性深灰渐变，白底上的视觉锚点
    static let iconGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.39, blue: 0.42),
            Color(red: 0.24, green: 0.25, blue: 0.27)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 图片卡底色：比白底略深一档的浅灰，用来托住图片
    static let imageCardFill = Color(red: 0.96, green: 0.96, blue: 0.97)

    /// 弹窗外描边：白底需要一道淡灰边把自己从桌面上"切"出来
    static let borderColor = Color.black.opacity(0.10)
    /// 内部小卡片描边
    static let innerBorderColor = Color.black.opacity(0.08)
    /// 阴影：系统通知那种柔和的中性阴影
    static let shadowColor = Color.black.opacity(0.18)

    /// 背板染色：在毛玻璃上盖一层近白，做出系统通知的亮底质感。
    ///
    /// 留一点透明度让底下的模糊透出来，不至于变成一块死板的纯白色块。
    static let backdropTint = Color.white.opacity(0.82)
}
