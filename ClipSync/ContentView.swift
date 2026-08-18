import SwiftUI

// ============================================================
// ClipSync-Mac 主窗口
// 左侧：侧边栏（主页 / 短信 / 剪贴板 / 设置）
// 右侧：详情区
// 顶部无横幅（状态信息在主页大号卡片里）
// ============================================================

struct ContentView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ws: WSClient
    @EnvironmentObject var router: AppRouter

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $router.selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .navigationTitle("ClipSync")
        } detail: {
            detail
                .navigationTitle(router.selection.title)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection {
        case .home:      HomeView()
        case .sms:       HistoryView(filter: .sms)
        case .clipboard: HistoryView(filter: .clipboard)
        case .settings:  SettingsView()
        }
    }
}

// MARK: - 侧边栏项

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, sms, clipboard, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:      return "主页"
        case .sms:       return "短信"
        case .clipboard: return "剪贴板"
        case .settings:  return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .sms:       return "message.badge"
        case .clipboard: return "doc.on.clipboard"
        case .settings:  return "gearshape"
        }
    }
}
