import SwiftUI

// ============================================================
// Toast 视觉样式集中定义
//
// 圆角半径要在三个地方保持一致：SwiftUI 的 clipShape、NSVisualEffectView 的
// layer、NSHostingView 的 layer。散着写迟早对不上，于是收到这里。
//
// 配色走"冷调石墨灰"：弹窗出现频率高，纯彩色看久了发闷、也容易跟系统强调色
// 打架；但零饱和度的纯灰（Color(white:)）会灰得发死，像一块水泥。
//
// 所以统一给灰色掺一点蓝，把色相压在 220° 附近、饱和度留 8%~14%。眼睛仍然
// 读作"灰"，却有冷调的通透感，也跟 macOS 自身的石墨色系对得上。
// 层级只靠明度拉开，不引入第二个色相。
// ============================================================
enum ToastStyle {
    /// 弹窗圆角
    static let cornerRadius: CGFloat = 12
    /// 内部小卡片（图片卡、胶囊）的圆角
    static let innerCornerRadius: CGFloat = 10

    /// 主按钮底色：冷调石墨，比背板明显但不刺眼
    static let accentFill = Color(red: 0.30, green: 0.33, blue: 0.38)
    /// 主按钮完成态：再压暗一档，作为"已复制"的反馈
    static let accentFillStrong = Color(red: 0.24, green: 0.27, blue: 0.32)
    /// 次要按钮底色：借前景色的低透明度，自动适配深浅色模式
    static let secondaryFill = Color.primary.opacity(0.10)

    /// 图标底色：冷调石墨的浅→深渐变，避免大色块显得死板
    static let iconGradient = LinearGradient(
        colors: [
            Color(red: 0.42, green: 0.46, blue: 0.52),
            Color(red: 0.28, green: 0.31, blue: 0.37)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 图片卡底色：带一丝冷调的浅灰，比纯白柔和，跟毛玻璃背板过渡自然
    static let imageCardFill = Color(red: 0.90, green: 0.91, blue: 0.93)

    /// 描边与阴影
    static let borderColor = Color.white.opacity(0.12)
    static let innerBorderColor = Color.black.opacity(0.10)
    /// 阴影也带一点冷调，纯黑阴影在浅色背景上会显脏
    static let shadowColor = Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.26)

    /// 背板染色。
    ///
    /// .hudWindow 毛玻璃本身是零饱和度的纯灰（实测 saturation≈0.009），单靠它
    /// 整块弹窗会灰得发死。叠一层极淡的冷调，把背板也拉进同一个色系。
    static let backdropTint = Color(red: 0.34, green: 0.40, blue: 0.52).opacity(0.20)
}
