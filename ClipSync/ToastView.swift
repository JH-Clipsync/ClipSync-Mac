import SwiftUI
import AppKit

// ============================================================
// ToastView：右上角通知横幅
// - 短信类 + 提取到验证码 → 显示"复制 xxxxxx"和"全文"按钮
// - 其他 → 显示单个"复制"按钮
// - 用 onTapGesture 而非 Button：Button 会走 AppKit 的按钮响应链并激活 App。
//   但真正保证"点击不激活、不带出主窗口"的是承载窗口 ToastWindow —— 它必须
//   是 NSPanel + .nonactivatingPanel（见 ToastManager.swift）。
// ============================================================

struct ToastView: View {
    let message: SyncMessage
    let showContent: Bool
    /// 已提取到的验证码；nil 表示没有
    let extractedCode: String?
    let onCopyCode: () -> Void   // 只复制验证码
    let onCopyAll: () -> Void    // 复制全文/剪贴板整体
    let onPreviewImage: () -> Void  // 图片消息：预览大图
    let onClose: () -> Void
    /// 点击弹窗内容区（非按钮区域）时：打开主窗口并跳到对应 Tab
    let onOpen: () -> Void

    @State private var codeCopied = false
    @State private var allCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                iconView

                VStack(alignment: .leading, spacing: 4) {
                    titleRow
                    if !isImage {
                        rowBody
                        // 文字/短信：始终保留按钮（复制 / 复制验证码+全文）
                        actionRow
                    }
                }
                // 关键：让 VStack 撑满 HStack 剩余空间，Text 才能拿到宽度并换行
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 图片：固定卡片尺寸，内部等比缩放作为缩略图；
            // 下方按钮区：复制 + 预览，跟文字消息的胶囊按钮风格一致。
            if isImage {
                VStack(alignment: .center, spacing: 8) {
                    imageThumbnail
                    imageActionRow
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: windowWidth, alignment: .topLeading)
        .background(
            ZStack {
                VisualEffectBlur(
                    // .popover 是亮面材质；.hudWindow 底子是深灰，会把整块弹窗压暗
                    material: .popover,
                    blendingMode: .behindWindow,
                    cornerRadius: ToastStyle.cornerRadius
                )
                // 盖一层近白，做出系统通知那种亮底
                ToastStyle.backdropTint
            }
            .clipShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous)
                .strokeBorder(ToastStyle.borderColor, lineWidth: ToastStyle.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        .shadow(color: ToastStyle.shadowColor, radius: 20, y: 6)
        // 点击弹窗主体区域（标题/正文/图标）→ 打开主窗口跳到对应 Tab。
        // 复制按钮和关闭按钮都有自己的 onTapGesture，SwiftUI 里子视图的手势
        // 会优先消费掉点击，不会冒泡到这里。
        .contentShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var isImage: Bool {
        message.content == MessageContent.image && message.payload.data != nil
    }

    private var decodedImage: NSImage? {
        guard isImage,
              let b64 = message.payload.data,
              let data = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: data)
    }

    /// 弹窗宽度：所有类型统一 360，图片卡片固定在内容区内居中，
    /// 不再随图片比例变化 —— 小图小卡会让弹窗忽宽忽窄，多个 Toast
    /// 上下堆叠时对不齐，视觉上是"跳动"的。
    var windowWidth: CGFloat { 360 }

    /// 缩略图卡片的固定尺寸。
    ///
    /// 16:9 的 280×158 能同时容下横图和竖图：
    /// - 横图：长边贴边，短边 letterbox
    /// - 竖图：短边贴边，长边 letterbox
    /// 卡片高度固定，整个 Toast 高度就稳定了。
    private let thumbSize = CGSize(width: 280, height: 158)

    // MARK: - subviews

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            if let phone = extractedPhone {
                Text(phone)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.08))
                    )
            }

            Spacer(minLength: 4)
            Text(timeString)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
                .onTapGesture { onClose() }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 6) {
            if let code = extractedCode {
                pill(title: codeCopied ? "已复制 \(code) ✓" : "复制 \(code)",
                     primary: true, done: codeCopied) {
                    onCopyCode()
                    codeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { codeCopied = false }
                }
                pill(title: allCopied ? "✓" : "全文", primary: false, done: allCopied) {
                    onCopyAll()
                    allCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                }
            } else {
                pill(title: allCopied ? "已复制 ✓" : "复制", primary: true, done: allCopied) {
                    onCopyAll()
                    allCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    /// 胶囊按钮（用 onTapGesture 而非 Button，避免 SwiftUI 自动激活 App）
    private func pill(
        title: String,
        primary: Bool,
        done: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: 12, weight: primary ? .semibold : .medium))
            // 次要按钮用强调色文字配淡色底，跟主按钮构成"实心/描边"的常规组合
            .foregroundStyle(primary ? Color.white : Color.accentColor)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(
                // 复制完成时压暗一档，给操作一个即时的视觉回执
                Capsule().fill(
                    primary
                        ? (done ? ToastStyle.accentFillStrong : ToastStyle.accentFill)
                        : ToastStyle.secondaryFill
                )
            )
            .overlay(
                // 次要按钮靠一道描边跟背板分开，不然淡底色在毛玻璃上会糊
                Capsule().strokeBorder(
                    primary ? Color.clear : ToastStyle.secondaryStroke,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .onTapGesture { action() }
    }

    /// 左侧图标：跟系统通知一致，主体是本 App 的图标，右下角挂一个表示消息
    /// 类型的小角标（短信 / 图片 / 分享 / 剪贴板）。
    private var iconView: some View {
        appIconLayer
            // 角标叠在右下角。用 overlay 而不是放大 ZStack：overlay 不参与布局
            // 尺寸计算，角标溢出一点也不会被裁，图标本身仍占 34x34。
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ToastStyle.accentFill)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(ToastStyle.innerBorderColor, lineWidth: 0.5))
                    .offset(x: 3, y: 3)
            }
    }

    /// App 图标本体。取不到就退回符号图标，保证任何情况下都有东西可显示。
    @ViewBuilder
    private var appIconLayer: some View {
        if let appIcon = Self.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 34, height: 34)
                // App 图标本身是白底浅色设计，卡片底又是近白，垫一层略暗的
                // 中性灰把它从背景里分出来
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ToastStyle.iconPlateFill)
                )
                // 先裁形，再描边：反过来描边会被裁掉一半
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ToastStyle.innerBorderColor, lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ToastStyle.iconGradient)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
        }
    }

    /// 本 App 的图标，只取一次。
    ///
    /// NSImage(named: NSImage.applicationIconName) 拿的是 Assets 里的 AppIcon，
    /// 比自己拼路径去读 icon_64x64.png 稳妥。
    private static let appIcon: NSImage? = {
        if let icon = NSImage(named: NSImage.applicationIconName) { return icon }
        return NSApplication.shared.applicationIconImage
    }()

    // MARK: - content helpers

    /// 内容区：图片消息不在这里渲染（见 imageThumbnail），其余显示文字
    @ViewBuilder
    private var rowBody: some View {
        Text(bodyText)
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(3)
            .truncationMode(.tail)             // 末尾省略
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 让 Text 垂直方向按内容自撑，配合外层容器自适应高度
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 图片缩略图卡片：固定尺寸，图片等比缩放，点击预览大图
    @ViewBuilder
    private var imageThumbnail: some View {
        if let img = decodedImage {
            ZStack {
                RoundedRectangle(cornerRadius: ToastStyle.innerCornerRadius, style: .continuous)
                    .fill(ToastStyle.imageCardFill)
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
            .frame(width: thumbSize.width, height: thumbSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: ToastStyle.innerCornerRadius, style: .continuous)
                    .strokeBorder(ToastStyle.innerBorderColor, lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                // 右下角浮一个放大镜角标，提示点击可预览
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToastStyle.innerCornerRadius, style: .continuous))
            .onTapGesture { onPreviewImage() }
            .help("点击预览大图（Esc 关闭）")
        } else {
            RoundedRectangle(cornerRadius: ToastStyle.innerCornerRadius, style: .continuous)
                .fill(ToastStyle.imageCardFill)
                .frame(width: thumbSize.width, height: thumbSize.height)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                )
        }
    }

    /// 图片消息的按钮行：复制 + 预览
    @ViewBuilder
    private var imageActionRow: some View {
        HStack(spacing: 6) {
            pill(title: allCopied ? "已复制 ✓" : "复制", primary: true, done: allCopied) {
                onCopyAll()
                allCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
            }
            pill(title: "预览", primary: false) {
                onPreviewImage()
            }
            Spacer()
        }
        .frame(width: thumbSize.width)
    }

    private var title: String {
        if message.looksLikeSms {
            // 只有真的抽到了验证码才叫"短信验证码"；
            // 普通通知类/个人短信只叫"短信"
            return extractedCode != nil ? "短信验证码" : "短信"
        }
        switch message.kind {
        case MessageKind.image:   return "剪贴板图片"
        case MessageKind.share:   return "分享"
        default:
            return message.type == MessageType.clipboard ? "剪贴板" : "通知"
        }
    }

    private var bodyText: String {
        if !showContent { return "收到一条新消息" }
        // ⚠️ Mac 端本地兜底清洗（服务端可能没升级或清洗漏配，这里保证 UI 一致）：
        //   1) 去掉所有前导【xxx】块
        //   2) 去掉 [N条] / [xN] 合并提示
        //   3) 去掉开头省略号
        let raw: String = {
            if let t = message.payload.text, !t.isEmpty { return t }
            if let p = message.payload.preview, !p.isEmpty { return p }
            if let mime = message.payload.mime, mime.hasPrefix("image/") { return "[图片]" }
            return "新消息"
        }()
        let cleaned = message.looksLikeSms
            ? SmsPayloadSanitizer.sanitize(text: raw, sender: message.payload.sender).text
            : raw
        // ⚠️ SwiftUI 的 .truncationMode(.tail) 在某些布局下会 bug 性退化为头部截断，
        // 干脆自己手动做末尾截断，保证一定是"从后面省略"
        return truncatedTail(cleaned, maxChars: 80)
    }

    /// 严格的末尾截断：超过 maxChars 字符就截取前 maxChars 个，再拼上 …
    private func truncatedTail(_ s: String, maxChars: Int) -> String {
        if s.count <= maxChars { return s }
        return String(s.prefix(maxChars)) + "…"
    }

    /// 发件人：优先用服务端塞的 payload.sender；否则本地从【】里抽取（兜底）
    private var extractedPhone: String? {
        guard message.looksLikeSms else { return nil }
        if let s = message.payload.sender, !s.isEmpty { return s }
        guard let raw = message.payload.text, !raw.isEmpty else { return nil }
        return SmsPayloadSanitizer.sanitize(text: raw, sender: nil).sender
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: message.date)
    }

    private var iconName: String {
        switch message.kind {
        case MessageKind.smsCode: return "message.fill"
        case MessageKind.image:   return "photo.fill"
        case MessageKind.share:   return "square.and.arrow.up.fill"
        default:                  return "doc.on.clipboard"
        }
    }
}

// MARK: - 简洁通知（设备上下线等状态提示）

/// 只有「图标 + 标题 + 正文 + 关闭」的轻量通知横幅，样式与 ToastView 一致。
struct InfoToastView: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let onClose: () -> Void
    var onOpen: (() -> Void)? = nil

    private let width: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                        .onTapGesture { onClose() }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: width, alignment: .topLeading)
        .background(
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow, cornerRadius: ToastStyle.cornerRadius)
                ToastStyle.backdropTint
            }
            .clipShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous)
                .strokeBorder(ToastStyle.borderColor, lineWidth: ToastStyle.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        .shadow(color: ToastStyle.shadowColor, radius: 20, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: ToastStyle.cornerRadius, style: .continuous))
        .onTapGesture { onOpen?() }
    }
}

// MARK: - 磨砂玻璃背景

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    /// 圆角半径。
    ///
    /// NSVisualEffectView 是 AppKit 视图，SwiftUI 的 .clipShape 只裁 SwiftUI
    /// 自己的绘制，管不住它 —— 材质会溢到方形的四个角上，于是弹窗看起来
    /// "有时圆角有时方角"。必须让这个视图自己带圆角遮罩。
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
    }
}
