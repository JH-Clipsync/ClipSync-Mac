import SwiftUI
import UniformTypeIdentifiers

// ============================================================
// HistoryView：消息历史列表（短信 / 剪贴板）
// - 从 WSClient.history 筛出对应类型消息
// - 每行显示图标 + 标题 + 时间 + 内容
// - 短信自动提取验证码，展示"复制验证码"按钮
// ============================================================

struct HistoryView: View {
    let filter: Filter

    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var settings: SettingsStore

    enum Filter { case sms, clipboard }

    private var items: [SyncMessage] {
        switch filter {
        case .sms:       return history.filtered(.sms)
        case .clipboard: return history.filtered(.clipboard)
        }
    }

    var body: some View {
        if items.isEmpty {
            emptyView
        } else {
            List(items) { msg in
                Row(message: msg, showContent: settings.showContent)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .listStyle(.inset)
            .background(TrashInjector {
                history.clear(filter: filter == .sms ? .sms : .clipboard)
            })
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .sms ? "tray" : "doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(filter == .sms ? "暂无短信消息" : "暂无剪贴板消息")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 清空按钮注入标题栏最右

/// SwiftUI 的 ToolbarItem 在 NavigationSplitView 下会跑到中间，
/// 这里直接用 AppKit 把"清空"按钮以 titlebar accessory 钉到标题栏最右。
private struct TrashInjector: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> InjectorView {
        let v = InjectorView()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: InjectorView, context: Context) {
        nsView.action = action
    }
}

private final class InjectorView: NSView {
    var action: (() -> Void)?
    private var accessory: NSTitlebarAccessoryViewController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = window else {
            accessory?.removeFromParent()
            accessory = nil
            return
        }
        if accessory != nil { return }
        // 页面切换重建时会新建 Injector，旧的全局实例要先摘掉，避免重复按钮
        TrashAccessoryController.dropAll()
        let controller = TrashAccessoryController { [weak self] in
            self?.action?()
        }
        controller.layoutAttribute = .trailing
        win.addTitlebarAccessoryViewController(controller)
        accessory = controller
    }

    override func removeFromSuperview() {
        accessory?.removeFromParent()
        accessory = nil
        super.removeFromSuperview()
    }
}

private final class TrashAccessoryController: NSTitlebarAccessoryViewController {
    private let onTrash: () -> Void

    private static var live: [TrashAccessoryController] = []

    static func dropAll() {
        for c in live { c.removeFromParent() }
        live.removeAll()
    }

    init(onTrash: @escaping () -> Void) {
        self.onTrash = onTrash
        super.init(nibName: nil, bundle: nil)
        TrashAccessoryController.live.append(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let base = NSImage(systemSymbolName: "trash", accessibilityDescription: "清空")
        let img = base?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ) ?? base ?? NSImage()
        let btn = NSButton(image: img, target: self, action: #selector(tap))
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.toolTip = "清空历史（仅本机）"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 46, height: 30))
        btn.frame = NSRect(x: 4, y: 2, width: 38, height: 26)
        btn.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        container.addSubview(btn)
        view = container
    }

    @objc private func tap() { onTrash() }
}

// MARK: - 单行

private struct Row: View {
    let message: SyncMessage
    let showContent: Bool

    @EnvironmentObject private var history: HistoryStore

    @State private var codeCopied = false
    @State private var allCopied  = false
    @State private var confirmDelete = false

    private var extractedCode: String? {
        guard message.looksLikeSms, let text = message.payload.text else { return nil }
        return SmsCodeExtractor.extract(from: text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let phone = extractedPhone {
                        Text(phone)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    Spacer()
                    Text(timeString).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                rowBodyContent

                HStack(spacing: 6) {
                    if let code = extractedCode {
                        Button {
                            copyText(code); codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { codeCopied = false }
                        } label: {
                            Label(codeCopied ? "已复制 \(code) ✓" : "复制 \(code)",
                                  systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            ClipboardWriter.apply(payload: message.payload); allCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                        } label: {
                            Label(allCopied ? "✓" : "全文", systemImage: "text.alignleft")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            ClipboardWriter.apply(payload: message.payload); allCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { allCopied = false }
                        } label: {
                            Label(allCopied ? "已复制 ✓" : "复制", systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button {
                        if confirmDelete {
                            history.remove(id: message.id)
                        } else {
                            confirmDelete = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { confirmDelete = false }
                        }
                    } label: {
                        Label(confirmDelete ? "确认删除" : "删除",
                              systemImage: confirmDelete ? "trash.fill" : "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .help("删除这条记录")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - subviews

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemIndigo)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - content helpers

    private var title: String {
        if message.looksLikeSms { return "短信验证码" }
        switch message.kind {
        case MessageKind.image:   return "剪贴板图片"
        case MessageKind.share:   return "分享"
        default:
            return message.type == MessageType.clipboard ? "剪贴板" : "通知"
        }
    }

    private var bodyText: String {
        if !showContent { return "收到一条新消息" }
        // ⚠️ Mac 端本地兜底清洗（与 ToastView 一致，不依赖服务端）
        let raw: String = {
            if let t = message.payload.text, !t.isEmpty { return t }
            if let p = message.payload.preview, !p.isEmpty { return p }
            if let mime = message.payload.mime, mime.hasPrefix("image/") { return "[图片]" }
            return "新消息"
        }()
        let cleaned = message.looksLikeSms
            ? SmsPayloadSanitizer.sanitize(text: raw, sender: message.payload.sender).text
            : raw
        // 手动截断，避免 SwiftUI 在紧凑布局下的头部截断 bug
        if cleaned.count <= 120 { return cleaned }
        return String(cleaned.prefix(120)) + "…"
    }

    @ViewBuilder
    private var rowBodyContent: some View {
        if message.content == MessageContent.image,
           let b64 = message.payload.data,
           let data = Data(base64Encoded: b64),
           let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture { ImagePreviewWindows.show(image: img) }
                .help("点击预览大图")
        } else {
            Text(bodyText)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        f.dateFormat = "MM-dd HH:mm"
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

    private func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        ClipboardMonitor.shared.suppressNext()
        ClipboardMonitor.shared.markSignature("text:\(s.hashValue)")
    }
}

// MARK: - 大图预览窗口

/// 点击历史图片缩略图弹出的独立预览窗：
/// - 默认按原图比例显示（长边适配屏幕后等比缩放，不拉伸）
/// - 窗口可拖动改变大小，图片始终等比 letterbox 居中
/// - 提供复制按钮，Esc 关闭
enum ImagePreviewWindows {
    static func show(image: NSImage) {
        // 落盘成临时文件，供"用预览打开"调系统预览 App 使用
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipSyncPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        let fileData = rep?.representation(using: .png, properties: [:]) ?? Data()
        let filePath = tmpDir.appendingPathComponent("preview_\(Int(Date().timeIntervalSince1970)).png").path
        try? fileData.write(to: URL(fileURLWithPath: filePath))

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        // 默认尺寸：宽不小于 640、高按原图但不超屏幕 80%，
        // 竖长图不再被压成窄条，图片在窗内等比 letterbox 完整显示
        let w = min(screen.width * 0.8, max(image.size.width, 640))
        let h = min(screen.height * 0.8, max(image.size.height, 480))
        // 加上工具栏高度
        let contentSize = NSSize(width: w, height: h + 46)

        // 用 NSPanel + .nonactivatingPanel：从 Toast 点开预览时不激活 App，
        // 否则 AppKit 会连带把主窗口一起带到前台（关掉预览就看见主窗口）。
        let win = ImagePreviewPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let view = ImagePreviewView(image: image, filePath: filePath) { [weak win] in
            win?.close()
        }
        let hosting = NSHostingView(rootView: view)

        win.title = "图片预览"
        win.contentView = hosting
        win.center()
        win.minSize = NSSize(width: 280, height: 200)
        win.isReleasedWhenClosed = false
        // 浮在普通窗口之上，且不参与 App 的窗口循环 / 不随失活隐藏
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = false
        win.hidesOnDeactivate = false
        // 从 Toast 点开时 App 并未激活，普通层级会被压在别的 App 后面看不见，
        // 所以抬到 floating；主窗口里点开则保持普通层级，别赖在其他 App 上面。
        win.level = NSApp.isActive ? .normal : .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let accessory = TitlebarAccessoryController {
            NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
        }
        accessory.layoutAttribute = .trailing
        win.addTitlebarAccessoryViewController(accessory)

        // 保活：NSPanel 默认 isReleasedWhenClosed=false 也仍需有强引用，
        // 否则 hosting 视图连同面板会在闭包结束后被释放。
        live.append(win)
        win.orderFrontRegardless()
        // 只把键盘焦点给面板，不调 NSApp.activate —— 主窗口因此不会被顶出来
        win.makeKey()
    }

    /// 已打开的预览面板，关闭时移除
    private static var live: [NSPanel] = []

    fileprivate static func forget(_ panel: NSPanel) {
        live.removeAll { $0 === panel }
    }
}

/// 预览面板：可成为 key（要接收 ⌘C/⌘S/Esc），但永不成为 main，
/// 这样它出现时 AppKit 不会去唤起 App 的 main window。
private final class ImagePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        ImagePreviewWindows.forget(self)
    }
}

/// 标题栏右侧的"用预览打开"按钮
private final class TitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let onOpen: () -> Void

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let base = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "用预览打开")
        let img = base?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ) ?? base ?? NSImage()
        let btn = NSButton(image: img, target: self, action: #selector(tap))
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.toolTip = "用预览打开"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 46, height: 30))
        btn.frame = NSRect(x: 4, y: 2, width: 38, height: 26)
        btn.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        container.addSubview(btn)
        view = container
    }

    @objc private func tap() { onOpen() }
}

private struct ImagePreviewView: View {
    let image: NSImage
    let filePath: String
    /// 关闭自己所属的面板（不能用 NSApp.keyWindow，App 未激活时会误关主窗口）
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    Color.white
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            HStack(spacing: 12) {
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    ClipboardMonitor.shared.suppressNext()
                    ClipboardMonitor.shared.markSignature("img:\(image.size.width)x\(image.size.height)")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
                Button {
                    saveImage()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("关闭") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask
        ).first
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "ClipSync_\(stamp.string(from: Date())).png"
        panel.canCreateDirectories = true
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
            let ext = url.pathExtension.lowercased()
            let asJpeg = ext == "jpg" || ext == "jpeg"
            let data = rep?.representation(
                using: asJpeg ? .jpeg : .png,
                properties: asJpeg ? [.compressionFactor: 0.9] : [:]
            )
            do {
                try data?.write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = "保存失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
