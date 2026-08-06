import Foundation

// ============================================================
// SmsPayloadSanitizer：本地兜底清洗短信格式（不依赖服务端清洗）
//
// 服务端 sanitizeSmsPayload 可能没启动/版本旧或清洗正则漏匹配时，
// Mac 端自己做同样的处理，保证 UI 显示一致。
//
// 功能：
//   - 剥离所有前导的【xxx】块（如 【+86xxx】【测试】）
//   - 剥离 [N条] / [xN] 合并提示
//   - 剥离开头 "..." / "…"
//   - 从【】里找第一个像号码的填进 sender（3+ 位连续数字，支持 +86 前缀）
//
// 结果：(cleanedText, extractedSender)
// ============================================================

enum SmsPayloadSanitizer {

    /// 文本是否带有短信特征标记：【号码】/ [N条] / 开头省略号。
    /// 手机端经常不带 payload.kind，isSms 判不出来，
    /// 只要文本长得像短信就按短信清洗（普通剪贴板文本不会命中这些特征）。
    static func hasSmsMarkers(_ text: String) -> Bool {
        if firstMatch(in: text, pattern: #"【[^】]*\d{3,}[^】]*】"#, group: 0) != nil { return true }
        if firstMatch(in: text, pattern: #"\[\s*\d+\s*条\s*\]"#, group: 0) != nil { return true }
        if firstMatch(in: text, pattern: #"(?i)\[x\s*\d+\s*\]"#, group: 0) != nil { return true }
        if firstMatch(in: text, pattern: #"^\s*(?:\.{3,}|…+)"#, group: 0) != nil { return true }
        return false
    }

    /// 返回 (清洗后的正文, 提取的发件人号码或服务号)
    /// 若原 payload.sender 已非空，直接沿用它，不再二次抽取；但 text 仍按规则清洗。
    static func sanitize(text: String, sender originalSender: String?) -> (text: String, sender: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ("", originalSender) }

        // 1) 先抽 sender（从原文里抽，清洗后的 text 里【】已被去掉）
        var sender = originalSender
        if sender == nil || sender!.isEmpty {
            // 找所有【xxx】块
            let allBrackets = matches(in: t, pattern: #"【([^】]*)】"#, group: 1)
            for content in allBrackets {
                var cand = content.trimmingCharacters(in: .whitespaces)
                // 去掉 +86 / 86 前缀
                if cand.hasPrefix("+") { cand.removeFirst() }
                if cand.hasPrefix("86") {
                    let rest = cand.dropFirst(2)
                    if rest.first?.isNumber == true { cand = String(rest) }
                }
                cand = cand.trimmingCharacters(in: .whitespaces)
                // 至少 3 位连续数字才视为号码/服务号
                if firstMatch(in: cand, pattern: #"\d{3,}"#, group: 0) != nil {
                    sender = cand
                    break
                }
            }
        }

        // 2) 清洗正文：只剥离前导里【内容】含号码/服务号的前缀块（保留【招商银行】等签名）
        var cleaned = t
        while true {
            guard let m = firstMatch(in: cleaned, pattern: #"^\s*【([^】]*)】\s*"#, group: 1),
                  let full = firstMatchRange(in: cleaned, pattern: #"^\s*【[^】]*】\s*"#, group: 0) else { break }
            let content = m.trimmingCharacters(in: .whitespaces)
            // 内容里含 3+ 位连续数字（含 +86xxx 前缀的手机号 / 95xxx 服务号等）→ 视为号码前缀，删掉；
            // 否则是服务商签名（【招商银行】【支付宝】等）→ 保留
            if firstMatch(in: content, pattern: #"\d{3,}"#, group: 0) != nil {
                cleaned.removeSubrange(full)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        // [N条] / [xN]
        cleaned = cleaned.replacingOccurrences(
            of: #"\[\s*\d+\s*条\s*\]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\[x\s*\d+\s*\]"#,
            with: "",
            options: .regularExpression
        )
        // 开头残留省略号
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*(?:\.{3,}|…+)\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, sender)
    }

    // MARK: - 私有工具（与 SmsCodeExtractor 同款，避免互相独立，互不依赖）

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func firstMatchRange(in text: String, pattern: String, group: Int) -> Range<String.Index>? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return r
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
