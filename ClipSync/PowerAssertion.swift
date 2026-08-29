import Foundation
import IOKit.pwr_mgt

// ============================================================
// 电源断言：阻止系统睡眠，保证 WebSocket 长连接常驻
// ============================================================
//
// 背景：
//   NSAppSleepDisabled（Info.plist）只能阻止 App Nap 和"空闲睡眠"，
//   管不了合盖（clamshell）与系统级睡眠。Mac 一旦进入系统睡眠：
//     - CPU / Wi-Fi 全部挂起，WebSocket 心跳停发；
//     - 服务端 60s 读超时后判其下线；
//     - Power Nap 每 ~15 分钟 DarkWake 几十秒 → 客户端重连上线 →
//       DarkWake 结束又睡 → 下线，表现为"每 15 分钟上下线一次"。
//
// 方案：
//   App 运行期间持有一把 kIOPMAssertionTypePreventSystemSleep 断言
//   （等价于 `caffeinate -s`）。
//     - 接入电源时：可阻止系统睡眠，包含合盖（clamshell）场景；
//     - 电池供电时：出于续航/温控，macOS 仍可能强制睡眠（合盖必然睡），
//       这是系统硬件级限制，任何 App 都无法绕过。
//   用户退出 App 时释放断言，系统恢复正常睡眠策略。
// ============================================================

final class PowerAssertion {
    static let shared = PowerAssertion()

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isAcquired = false

    private init() {}

    /// 持有"阻止系统睡眠"断言。重复调用安全（已持有时直接返回）。
    func acquire() {
        guard !isAcquired else { return }

        let reason = "ClipSync 保持 WebSocket 长连接以实时同步剪贴板与短信验证码" as CFString
        // PreventSystemSleep：阻止系统级睡眠（合盖/空闲），比 PreventUserIdleSystemSleep 更强。
        // 它不会阻止显示器睡眠——屏幕照常熄灭省电，只是主机和网络保持运行。
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isAcquired = true
            NSLog("[Power] ✅ 已持有 PreventSystemSleep 断言（id=\(assertionID)），系统睡眠将被阻止")
        } else {
            NSLog("[Power] ❌ 创建电源断言失败，错误码 \(result)")
        }
    }

    /// 释放断言，系统恢复正常睡眠。
    func release() {
        guard isAcquired else { return }
        IOPMAssertionRelease(assertionID)
        isAcquired = false
        NSLog("[Power] ⏹ 已释放 PreventSystemSleep 断言（id=\(assertionID)）")
    }

    deinit {
        release()
    }
}
