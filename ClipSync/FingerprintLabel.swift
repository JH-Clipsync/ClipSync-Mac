import SwiftUI

// ============================================================
// 密钥指纹显示
//
// 派生一次密钥要跑 20 万轮 PBKDF2（手机上实测约 2.8 秒，Mac 上约 50ms）。
// SwiftUI 的 body 会被反复求值，直接在里面同步调 fingerprint() 会让整个
// 视图跟着卡，所以挪到后台任务。密码只在用户点「确定」时变化，不需要防抖。
// ============================================================
struct FingerprintLabel: View {
    let password: String
    /// 指纹前面的说明文字，和指纹拼在同一行
    var prefix: String = "密钥指纹"

    @State private var fingerprint: String?
    @State private var computing = false

    var body: some View {
        Group {
            if let fingerprint {
                Text("\(prefix) \(fingerprint)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if computing {
                Text("\(prefix) 计算中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        // password 变化时重跑：task(id:) 会自动取消上一次还没完成的任务
        .task(id: password) {
            fingerprint = nil
            guard !password.isEmpty else {
                computing = false
                return
            }
            computing = true
            let pwd = password
            let result = await Task.detached(priority: .utility) {
                PayloadCipher.fingerprint(password: pwd)
            }.value
            if Task.isCancelled { return }
            fingerprint = result
            computing = false
        }
    }
}
