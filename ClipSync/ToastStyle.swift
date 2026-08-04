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

    /// 主按钮底色：系统强调色。
    ///
    /// 用 .accentColor 而不是自己调色 —— 它跟随用户在「系统设置 > 外观」里
    /// 选的强调色，默认蓝，天然是"系统按钮该有的颜色"。
    static let accentFill = Color.accentColor
    /// 完成态：系统绿，表示操作成功（"已复制 ✓"）
    static let accentFillStrong = Color(nsColor: .systemGreen)
    /// 次要按钮底色：借强调色的极低透明度，自动跟着强调色走
    static let secondaryFill = Color.accentColor.opacity(0.10)
    /// 次要按钮描边
    static let secondaryStroke = Color.accentColor.opacity(0.30)

    /// 图标兜底底色：拿不到 App 图标时用系统蓝渐变
    static let iconGradient = LinearGradient(
        colors: [
            Color(nsColor: .systemBlue),
            Color(nsColor: .systemBlue).opacity(0.78)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 图片卡底色：比卡片底暗一档的中性灰，用来托住图片
    static let imageCardFill = Color(white: 0.90)

    /// App 图标的衬底。
    ///
    /// 图标本身是白底浅色设计，卡片底又接近纯白，衬底得压得够暗才分得开 ——
    /// 和底色至少留 10% 明度差，否则两块灰糊在一起。
    static let iconPlateFill = Color(white: 0.88)

    /// 弹窗外描边：底色接近纯白后必须再重一点，否则在浅色桌面上没有边界
    static let borderColor = Color(white: 0.60).opacity(0.70)
    /// 内部小卡片描边
    static let innerBorderColor = Color.black.opacity(0.10)
    /// 阴影：中性黑，柔和扩散
    static let shadowColor = Color.black.opacity(0.20)

    /// 背板染色：近纯白。
    ///
    /// 系统通知实测是 RGB(223,223,223)，但那张参考图整体偏暗。这里取 0.99
    /// （≈252），让底色跟图标衬底（0.88）拉开足够反差。留一丝不透明度是为了
    /// 让底下的模糊仍能透出来，不至于变成一块死板的色块。
    static let backdropTint = Color(white: 0.99).opacity(0.94)
}
