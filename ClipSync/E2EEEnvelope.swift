import Foundation
import CryptoKit

// ============================================================
// PayloadCipher：在「业务 payload」和「加密信封」之间来回转换
//
// 发送：MessagePayload(明文) → JSON → AES-GCM → MessagePayload(仅 enc + 占位 preview)
// 接收：MessagePayload(含 enc) → 解密 → MessagePayload(明文)
//
// 密钥由 SettingsStore.syncPassword 派生，并按密码缓存，避免每条消息
// 都跑一次 20 万轮 PBKDF2。
// ============================================================

enum PayloadCipher {
    /// 加密消息在 UI / 日志里的占位文案（不含任何真实内容）
    static let placeholder = "🔒 加密消息"

    // MARK: - 密钥缓存

    /// 密钥缓存最多留几把（够覆盖"连接在用的"+"设置页正在试的"）
    private static let maxCachedKeys = 4

    /// 已派生密钥缓存，key 是同步密码；order 记录使用顺序用于淘汰。
    ///
    /// 用多槽而不是单槽：设置页一边打字算指纹、连接一边在发消息，单槽会被
    /// 打字过程反复挤掉，导致每条消息都重新派生。密钥是密码的纯函数（盐写死
    /// 在 E2EECrypto 里），所以缓存不需要失效，只需要限制条数。
    private static var keyCache: [String: SymmetricKey] = [:]
    private static var keyOrder: [String] = []
    private static let lock = NSLock()

    /// 取当前同步密码对应的密钥；密码为空返回 nil（等于关闭加密）。
    static func currentKey(password: String) -> SymmetricKey? {
        guard !password.isEmpty else { return nil }
        lock.lock()
        if let key = keyCache[password] {
            touch(password)
            lock.unlock()
            return key
        }
        lock.unlock()

        // 派生放在锁外：单次要跑 20 万轮 PBKDF2，持锁会把正在发消息的线程一起
        // 堵住。并发算同一个密码最多白跑一次，无副作用。
        guard let key = E2EECrypto.deriveKey(password: password) else { return nil }

        lock.lock()
        keyCache[password] = key
        touch(password)
        while keyOrder.count > maxCachedKeys {
            keyCache.removeValue(forKey: keyOrder.removeFirst())
        }
        lock.unlock()
        return key
    }

    /// 把密码挪到使用顺序末尾。调用方必须已持锁。
    private static func touch(_ password: String) {
        keyOrder.removeAll { $0 == password }
        keyOrder.append(password)
    }

    /// 清空密钥缓存（仅测试 / 排查用；正常运行不需要，密钥是密码的纯函数）。
    static func invalidateKeyCache() {
        lock.lock()
        keyCache.removeAll()
        keyOrder.removeAll()
        lock.unlock()
    }

    /// 当前密钥指纹，用于设置页展示 / 排查两端密码不一致
    static func fingerprint(password: String) -> String? {
        guard let key = currentKey(password: password) else { return nil }
        return E2EECrypto.fingerprint(of: key)
    }

    // MARK: - 发送方向

    /// 把明文 payload 封成密文 payload。
    /// 未设置同步密码时返回原文（保持向后兼容，服务端 e2ee.require=false 才允许）。
    static func encrypt(_ payload: MessagePayload, password: String) -> MessagePayload {
        guard let key = currentKey(password: password) else { return payload }
        guard let plain = try? JSONEncoder().encode(payload),
              let env = E2EECrypto.seal(plaintext: plain, key: key) else {
            NSLog("[E2EE] ⚠ 加密失败，退回明文发送")
            return payload
        }
        // 只保留信封 + 占位预览；kind 保留以便收端在解密前做分类
        return MessagePayload(
            text: nil, mime: nil, data: nil,
            preview: placeholder, kind: payload.kind,
            sender: nil, enc: env
        )
    }

    // MARK: - 接收方向

    /// 解密结果：区分"本来就是明文"、"解开了"、"解不开"三种情况，
    /// 让 UI 能给出准确提示而不是笼统地失败。
    enum DecryptOutcome {
        case plaintext(MessagePayload)   // 对端没加密
        case decrypted(MessagePayload)   // 解密成功
        case failed(fingerprint: String) // 密码不一致或数据损坏
    }

    static func decrypt(_ payload: MessagePayload, password: String) -> DecryptOutcome {
        guard let env = payload.enc else { return .plaintext(payload) }
        guard let key = currentKey(password: password),
              let plain = E2EECrypto.open(envelope: env, key: key),
              var decoded = try? JSONDecoder().decode(MessagePayload.self, from: plain) else {
            return .failed(fingerprint: env.fp)
        }
        decoded.enc = nil
        return .decrypted(decoded)
    }
}
