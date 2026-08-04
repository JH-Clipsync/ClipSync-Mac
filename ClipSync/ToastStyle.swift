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

    /// 图片卡底色：比卡片底亮一档的近白，用来托住图片。
    ///
    /// 卡片底改成 0.915 的浅灰后，托底必须往**亮**的方向走，否则两块灰糊在一起。
    static let imageCardFill = Color(white: 0.98)

    /// App 图标的衬底。
    ///
    /// 图标本身是白底浅色设计，衬底要和卡片底（0.915）留足明度差才分得开。
    /// 卡片底变灰后改用近白，让图标像放在一张小白卡上。
    static let iconPlateFill = Color(white: 0.99)

    /// 弹窗外描边：一圈比卡片底略亮的高光。
    ///
    /// 参考图实测：卡片主体 RGB≈231/234，最外一圈是 241 —— 比主体只**亮 7 档**，
    /// 是收敛的高光而不是深色描边。边界感主要来自外侧阴影，这圈只负责给玻璃面
    /// 一点厚度。透明度压到 0.35 后实测约 241，正好和参考图对齐；给到 0.75 会
    /// 冲到 250+，亮得像一道白线。
    static let borderColor = Color(white: 1.0).opacity(0.35)

    /// 外描边宽度。
    ///
    /// 必须是整数 1 而不是 0.5：在非 Retina 屏（scale = 1）上，0.5pt 的线得靠
    /// 抗锯齿摊到相邻像素，而左右两条竖边的亚像素对齐并不一样 —— 一侧被摊成
    /// 几乎纯白（看着就是"边框中间断了"），另一侧却留下清晰的灰线。1pt 正好
    /// 落满一个整像素，四条边粗细一致。
    static let borderWidth: CGFloat = 1

    /// 卡片底色：参考图实测 RGB≈231/234 的浅灰玻璃面
    static let cardTint = Color(white: 0.915)
    /// 内部小卡片描边
    static let innerBorderColor = Color.black.opacity(0.10)
    /// 阴影：中性黑，柔和扩散。
    ///
    /// 边界不再靠描边，全靠这层阴影跟桌面分开，所以要比之前明显一点。
    static let shadowColor = Color.black.opacity(0.28)

    /// 背板染色：浅灰玻璃面。
    ///
    /// 对齐参考图实测的 RGB≈231：不再是近纯白，而是能看出是一块半透玻璃的浅
    /// 灰。留一点不透明度，让底下的模糊仍透得出来。
    static let backdropTint = cardTint.opacity(0.90)
}
