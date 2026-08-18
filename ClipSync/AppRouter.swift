import SwiftUI
import Combine

/// 全局导航路由：让 Toast 弹窗等全局组件能切换主窗口的侧边栏选中项。
///
/// 使用 `@EnvironmentObject var router: AppRouter` 读取，
/// 通过 `router.selection = .sms` 切换；
/// 从外部（非 SwiftUI 上下文）调 `AppRouter.shared.open(.sms)`。
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// 当前侧边栏选中项
    @Published var selection: SidebarItem = .home

    private init() {}

    /// 打开主窗口并切到指定 Tab
    func open(_ item: SidebarItem) {
        selection = item
        // ToastWindow 是 nonactivating panel，点击它不会自动激活 App。
        // 先强制切到 regular 策略并激活，再打开主窗口；用 async 保证当前
        // 事件处理（panel  dismiss / 点击收尾）完成后再执行窗口操作。
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            (NSApp.delegate as? AppDelegate)?.openMainWindow()
        }
    }
}
