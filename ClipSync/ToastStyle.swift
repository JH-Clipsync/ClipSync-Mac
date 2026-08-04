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

    /// 主按钮底色：靛蓝。
    ///
    /// 近白底 + 中性灰文字的画面里只留这一处彩色，靛蓝的明度够低，白字对比
    /// 足够；色相偏冷，跟中性灰是同族关系，不会像纯蓝那样跳出来抢戏。
    static let accentFill = Color(red: 0.29, green: 0.36, blue: 0.60)
    /// 主按钮完成态：同色压暗一档，作为"已复制"的反馈
    static let accentFillStrong = Color(red: 0.22, green: 0.28, blue: 0.49)
    /// 次要按钮底色：极浅的靛蓝调白，跟主按钮同族但退到背景层
    static let secondaryFill = Color(red: 0.95, green: 0.96, blue: 0.98)
    /// 次要按钮描边：淡靛蓝，比中性灰边更协调
    static let secondaryStroke = Color(red: 0.29, green: 0.36, blue: 0.60).opacity(0.28)

    /// 图标兜底底色：拿不到 App 图标时用靛蓝渐变，跟主按钮呼应
    static let iconGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.45, blue: 0.69),
            Color(red: 0.25, green: 0.31, blue: 0.53)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 图片卡底色：比卡片底亮一档，用来托住图片
    static let imageCardFill = Color(red: 0.95, green: 0.96, blue: 0.98)

    /// App 图标的衬底。
    ///
    /// 图标本身是白底浅色设计，卡片底提亮到近白后，纯白衬底就分不出来了，
    /// 改用极淡的靛蓝调，既能托住图标又跟按钮同族。
    static let iconPlateFill = Color(red: 0.93, green: 0.95, blue: 0.98)

    /// 弹窗外描边：底色提亮后需要稍重一点的边，才能从浅色桌面上分离出来
    static let borderColor = Color(white: 0.66).opacity(0.60)
    /// 内部小卡片描边
    static let innerBorderColor = Color.black.opacity(0.10)
    /// 阴影：中性黑，柔和扩散
    static let shadowColor = Color.black.opacity(0.20)

    /// 背板染色：近白。
    ///
    /// 系统通知实测是 RGB(223,223,223)，但那张参考图整体偏暗；这里取 0.965
    /// （≈246）更亮一档，配合靛蓝按钮画面更透气。仍不用纯白：留一点灰才有
    /// "卡片"的质感，也让底下的模糊能透出来。
    static let backdropTint = Color(white: 0.965).opacity(0.90)
}
