import Foundation

// ============================================================
// SmsCodeExtractor：从短信文本中提取验证码
// 覆盖：
//   - Google 专属 G-123456
//   - 中文关键词：验证码 / 校验码 / 动态密码 / 验证代码
//   - 英文关键词：code / verification / OTP / PIN / passcode
//   - 反向表述："123456 是您的验证码"
//   - 兜底：整段短信中只出现一次的 4-8 位纯数字
// ============================================================

enum SmsCodeExtractor {

    static func extract(from body: String) -> String? {
        guard !body.isEmpty else { return nil }

        // 1) Google 专属：G-123456
        if let m = firstMatch(in: body, pattern: #"(?i)G-(\d{4,8})"#, group: 1) {
            return m
        }

        // 2) 关键词 → 附近数字
        let keywordPattern = #"(?i)(?:验证码|校验码|动态密码|验证代码|verification\s*code|verify\s*code|security\s*code|one[-\s]?time\s*password|otp|pin\s*code|passcode|code)[^0-9]{0,12}(\d{4,8})"#
        if let m = firstMatch(in: body, pattern: keywordPattern, group: 1) {
            return m
        }

        // 3) 反向：数字在前 → "是您的验证码"
        let reversePattern = #"(\d{4,8})[^0-9]{0,6}(?:是|为)?[^0-9]{0,4}(?:验证码|校验码|动态密码|is your\s*(?:verification\s*)?code)"#
        if let m = firstMatch(in: body, pattern: reversePattern, group: 1) {
            return m
        }

        // 4) 兜底：整段只有唯一的 4-8 位数字
        let all = matches(in: body, pattern: #"\b(\d{4,8})\b"#, group: 1)
        if all.count == 1 { return all.first }

        return nil
    }

    // MARK: - 私有工具

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func matches(in text: String, pattern: String, group: Int) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > group,
                  let r = Range(m.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }
}
