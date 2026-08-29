import Cocoa
import SwiftUI
import Combine

// ============================================================
// ClipSync-Mac —— 阶段 7
// 增量：加 WebSocket 客户端 WSClient
// - 启动时若 token 已配置就自动连接
// - 图标随连接状态变（空心/带刷新/填充）
// ============================================================

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var mainWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[ClipSync] 阶段7 启动")

        // 持有"阻止系统睡眠"断言：合盖/空闲也保持长连接在线（插电时有效，等价 caffeinate -s）。
        // 不阻止显示器睡眠，屏幕照常熄灭省电。
        PowerAssertion.shared.acquire()

        // 创建主菜单，让 ⌘Q / ⌘W / ⌘M 之类标准快捷键生效
        installMainMenu()

        _ = SettingsStore.shared
        let ws = WSClient.shared

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            applyIcon(state: ws.state)
            btn.toolTip = "ClipSync（左键开主窗口 / 右键菜单）"
            btn.sendAction(on: [.leftMouseDown, .rightMouseDown])
            btn.target = self
            btn.action = #selector(onStatusClick)
        }
        NSLog("[ClipSync] 图标已配置")

        // 状态变化 → 更新图标
        ws.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.applyIcon(state: state)
            }
            .store(in: &cancellables)

        // 收到新消息 → 自动写剪贴板 + 弹 Toast + 存历史
        ws.$lastMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { msg in
                // 1) 落盘到本地历史（重启不丢）
                HistoryStore.shared.append(msg)
                // 2) 剪贴板类：自动写入本机剪贴板
                if msg.isClipboard {
                    ClipboardWriter.apply(payload: msg.payload)
                }
                // 3) 弹 Toast
                Task { @MainActor in ToastManager.shared.show(message: msg) }
            }
            .store(in: &cancellables)

        // 剪贴板监听
        ClipboardMonitor.shared.bind(ws)
        ClipboardMonitor.shared.isEnabled = SettingsStore.shared.autoSyncClipboard
        if SettingsStore.shared.autoSyncClipboard {
            ClipboardMonitor.shared.start()
        }
        SettingsStore.shared.$autoSyncClipboard
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { enabled in
                ClipboardMonitor.shared.isEnabled = enabled
                if enabled { ClipboardMonitor.shared.start() }
                else       { ClipboardMonitor.shared.stop() }
            }
            .store(in: &cancellables)

        // 账号密码已填 → 自动连接（没有 token 时会先自动登录换一个）
        let s = SettingsStore.shared
        if s.hasCredentials || !s.token.isEmpty {
            Task { await ws.connect(settings: s) }
        }

        // 启动时直接打开主窗口
        DispatchQueue.main.async { [weak self] in
            self?.openMainWindow()
        }
    }

    // MARK: - 图标

    /// 三态菜单栏图标（模板渲染，与系统菜单栏图标风格一致）
    private func applyIcon(state: WSClient.ConnectionState) {
        guard let btn = statusItem.button else { return }

        let symbolName: String
        let accessibility: String

        switch state {
        case .connected:
            symbolName = "bubble.left.and.bubble.right.fill"
            accessibility = "ClipSync 已连接"
        case .connecting:
            symbolName = "arrow.triangle.2.circlepath"
            accessibility = "ClipSync 连接中"
        case .disconnected:
            symbolName = "bubble.left.and.bubble.right"
            accessibility = "ClipSync 未连接"
        }

        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility) else {
            return
        }

        // 三个图标统一用相同的 pointSize / weight / 画布，
        // 连接中的箭头图标之前比气泡大一圈就是因为它的 SF Symbol 边界更大。
        // 直接使用系统标准菜单栏字号(17)，并交给 NSStatusItem 按标准宽度布局，
        // 避免之前自绘 18×18 画布导致图标偏小、左右留白过大。
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let icon = base.withSymbolConfiguration(cfg) ?? base
        icon.isTemplate = true

        btn.image = icon
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleProportionallyDown
        btn.contentTintColor = nil

        NSLog("[ClipSync] 图标切换 → \(state.rawValue) (\(symbolName))")
    }

    // MARK: - 点击

    @objc func onStatusClick() {
        guard let event = NSApp.currentEvent else {
            openMainWindow()
            return
        }
        if event.type == .rightMouseDown {
            NSLog("[ClipSync] 右键 → 弹菜单")
            showMenu()
        } else {
            NSLog("[ClipSync] 左键 → 打开主窗口")
            openMainWindow()
        }
    }

    // MARK: - 主窗口

    @objc func openMainWindow() {
        // 让主窗口作为常规 App 出现（顶部主菜单栏显示 ClipSync/编辑/窗口）
        NSApp.setActivationPolicy(.regular)

        if let w = mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClipSync"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let root = ContentView()
            .environmentObject(SettingsStore.shared)
            .environmentObject(WSClient.shared)
            .environmentObject(HistoryStore.shared)
            .environmentObject(AppRouter.shared)
        win.contentView = NSHostingView(rootView: root)

        self.mainWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - 右键菜单

    func showMenu() {
        let ws = WSClient.shared
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: statusTitle(ws.state), action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: ""))
        if ws.state == .disconnected {
            let it = NSMenuItem(title: "重新连接", action: #selector(reconnect), keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        } else {
            let it = NSMenuItem(title: "断开连接", action: #selector(disconnect), keyEquivalent: "")
            it.target = self
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func statusTitle(_ state: WSClient.ConnectionState) -> String {
        switch state {
        case .connected:    return "✅ 已连接"
        case .connecting:   return "🔄 连接中…"
        case .disconnected: return "⚠️ 未连接"
        }
    }

    @objc func reconnect() {
        let s = SettingsStore.shared
        Task { await WSClient.shared.connect(settings: s) }
    }

    @objc func disconnect() {
        Task { @MainActor in WSClient.shared.disconnect() }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 主菜单
    // LSUIElement 应用默认没有屏幕顶部主菜单，⌘Q 等快捷键就没地方响应。
    // 手工构造一个"App菜单 + 窗口菜单 + 编辑菜单（含复制粘贴撤销）"

    private func installMainMenu() {
        let main = NSMenu()

        // 1. App 菜单：关于 / 退出
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 ClipSync",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 ClipSync",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 ClipSync",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu

        // 2. 编辑菜单：撤销/重做/剪切/复制/粘贴/全选（输入框里能用这些快捷键）
        let editMenuItem = NSMenuItem()
        main.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")),      keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")),     keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)),  keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)),keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // 3. 窗口菜单：最小化 / 关闭窗口
        let winMenuItem = NSMenuItem()
        main.addItem(winMenuItem)
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(withTitle: "最小化",
                        action: #selector(NSWindow.performMiniaturize(_:)),
                        keyEquivalent: "m")
        winMenu.addItem(withTitle: "关闭",
                        action: #selector(NSWindow.performClose(_:)),
                        keyEquivalent: "w")
        winMenuItem.submenu = winMenu
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出时释放电源断言，系统恢复正常睡眠
        PowerAssertion.shared.release()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock / Finder 重新打开本 App 时不自动恢复窗口。
    ///
    /// 主窗口只应由用户显式操作（点菜单栏图标、菜单项）打开。Toast 上的
    /// 复制按钮不该把它带出来，那会挡住用户正在输验证码的窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

// MARK: - NSWindowDelegate：关闭 = 隐藏

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            sender.orderOut(nil)
            NSLog("[ClipSync] 主窗口已隐藏")
            // 主窗口关掉 → 立刻回到纯菜单栏应用（隐藏 Dock 图标 & 顶部菜单）。
            //
            // 这里不能延迟：留在 .regular 的那段窗口期里，只要 App 被激活
            // （比如点 Toast 上的复制按钮），AppKit 就会把主窗口重新带出来。
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        return true
    }
}

// ============================================================
// 入口（纯 AppKit）
// ============================================================

// 单实例守卫。
//
// LaunchServices 只在"同一路径的同一 App"之间去重，从不同目录启动同一个
// bundle（比如 Xcode 的 DerivedData 和 xcodebuild 的 -derivedDataPath）会
// 被放行成两个进程。两份都连服务端、都监听剪贴板、都弹 Toast，消息会重复。
// 这里按 bundle ID 自查：已经有一个在跑就把它叫到前台，自己退出。
func terminateIfAlreadyRunning() {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    guard let running = others.first else { return }

    NSLog("[ClipSync] 已有实例在运行（pid \(running.processIdentifier)），本进程退出")
    running.activate(options: [.activateAllWindows])
    exit(0)
}

terminateIfAlreadyRunning()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory：不在 Dock 里显示图标，纯菜单栏常驻应用
app.setActivationPolicy(.accessory)
app.activate(ignoringOtherApps: true)
app.run()
