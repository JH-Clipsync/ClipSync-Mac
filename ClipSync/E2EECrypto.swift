import Foundation
import CryptoKit
import CommonCrypto

// ============================================================
// E2EECrypto：端到端隧道加密
//
// 密钥来自「用户在本端设置的同步密码」，服务端从不接触密码和密钥。
//
// 派生：PBKDF2-HMAC-SHA256(password, salt, iter) → 32 字节 AES 密钥
//   - salt 固定为 SHA-256("clipsync-e2ee-v1")，两端写死同一个值，
//     这样"同一个密码"在不同设备上派生出同一把密钥，无需交换任何材料。
//   - iter = 200000
// 加密：AES-256-GCM，每条消息随机 12 字节 nonce
// 指纹：SHA-256(key) 的前 16 个 hex 字符，用来快速判断两端密码是否一致
//
// 三端必须完全一致：Server 只校验信封格式（e2ee.go），
// Android 侧对应 E2EECrypto.kt。
// ============================================================

enum E2EECrypto {
    static let version = 1
    static let algorithm = "AES-256-GCM"
    static let kdfName = "PBKDF2-HMAC-SHA256"
    static let iterations = 200_000

    /// 固定盐的来源字符串。改动它等于让所有历史密文无法解开。
    private static let saltSeed = "clipsync-e2ee-v1"

    /// 派生用的固定盐：SHA-256(saltSeed)，32 字节
    static var salt: Data {
        Data(SHA256.hash(data: Data(saltSeed.utf8)))
    }

    // MARK: - 密钥派生

    /// 用同步密码派生 AES-256 密钥。CommonCrypto 的 PBKDF2 是这里唯一的系统依赖。
    static func deriveKey(password: String) -> SymmetricKey? {
        guard !password.isEmpty else { return nil }
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)

        let status = saltBytes.withUnsafeBufferPointer { saltPtr -> Int32 in
            derived.withUnsafeMutableBufferPointer { outPtr -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, password.utf8.count,
                    saltPtr.baseAddress, saltPtr.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    outPtr.baseAddress, outPtr.count
                )
            }
        }
        guard status == kCCSuccess else {
            NSLog("[E2EE] ✗ 密钥派生失败 status=\(status)")
            return nil
        }
        return SymmetricKey(data: Data(derived))
    }

    /// 密钥指纹：SHA-256(key) 前 16 位 hex。用于提示"两端密码不一致"。
    static func fingerprint(of key: SymmetricKey) -> String {
        let raw = key.withUnsafeBytes { Data($0) }
        let digest = SHA256.hash(data: raw)
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: - 加解密

    /// 把明文 payload 加密成信封。
    static func seal(plaintext: Data, key: SymmetricKey) -> EncEnvelope? {
        do {
            let nonce = AES.GCM.Nonce() // 12 字节随机
            let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
            // ct = 密文 + 16 字节 tag（combined 去掉前置 nonce）
            guard let combined = sealed.combined else { return nil }
            let ciphertextAndTag = combined.dropFirst(nonce.withUnsafeBytes { $0.count })
            return EncEnvelope(
                v: version,
                alg: algorithm,
                kdf: kdfName,
                iter: iterations,
                salt: salt.base64EncodedString(),
                iv: Data(nonce).base64EncodedString(),
                ct: Data(ciphertextAndTag).base64EncodedString(),
                fp: fingerprint(of: key)
            )
        } catch {
            NSLog("[E2EE] ✗ 加密失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 解开信封拿回明文。密码不对时 GCM 校验失败 → 返回 nil。
    static func open(envelope: EncEnvelope, key: SymmetricKey) -> Data? {
        guard envelope.v == version, envelope.alg == algorithm,
              let iv = Data(base64Encoded: envelope.iv),
              let ct = Data(base64Encoded: envelope.ct) else {
            NSLog("[E2EE] ✗ 信封格式不支持 v=\(envelope.v) alg=\(envelope.alg)")
            return nil
        }
        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let box = try AES.GCM.SealedBox(combined: Data(nonce) + ct)
            return try AES.GCM.open(box, using: key)
        } catch {
            // 最常见原因就是两端同步密码不一致
            NSLog("[E2EE] ✗ 解密失败（密码可能不一致）: \(error.localizedDescription)")
            return nil
        }
    }
}
