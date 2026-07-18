import Foundation

enum AuthorizationContext {
    private static let autofillTerms = [
        "自动填充", "autofill", "auto-fill", "auto fill"
    ]

    private static let codeTerms = [
        "验证码", "verification code"
    ]

    static func isApplePasswordAuthorization(_ text: String) -> Bool {
        let value = text.lowercased()
        return autofillTerms.contains(where: value.contains)
            && codeTerms.contains(where: value.contains)
    }

    static func isBrowserExtensionAuthorization(title: String?, text: String) -> Bool {
        let combined = [title ?? "", text].joined(separator: "\n").lowercased()
        let hasExtensionIdentity = combined.contains("icloud 密码")
            || combined.contains("icloud passwords")
            || combined.contains("moz-extension://")
            || combined.contains("chrome-extension://")
        return hasExtensionIdentity && isApplePasswordAuthorization(combined)
    }

    static func isBrowserExtensionPopup(title: String?, text: String) -> Bool {
        let normalizedText = text.lowercased()
        let hasExtensionURL = normalizedText.contains("moz-extension://")
            || normalizedText.contains("chrome-extension://")
        let hasPopupURL = hasExtensionURL
            && normalizedText.contains("/page_popup.html")
        return isICloudPasswordWindowTitle(title) && hasPopupURL
    }

    static func isICloudPasswordWindowTitle(_ title: String?) -> Bool {
        let normalized = (title ?? "").lowercased()
        return normalized.contains("icloud")
            && (normalized.contains("密码") || normalized.contains("password"))
    }
}

enum VerificationCodeParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![0-9])(?:[0-9][\s\-]?){6}(?![0-9])"#
    )

    static func extract(from text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let digits = text[swiftRange].filter(\.isNumber)
            if digits.count == 6 {
                return String(digits)
            }
        }
        return nil
    }
}

enum CodeSource: String {
    case accessibility = "辅助功能"
    case vision = "本地 OCR"
}

struct CapturedCode: Equatable {
    let value: String
    let capturedAt: Date
    let source: CodeSource

    func isFresh(at date: Date = Date(), lifetime: TimeInterval = 45) -> Bool {
        date.timeIntervalSince(capturedAt) >= 0 && date.timeIntervalSince(capturedAt) <= lifetime
    }
}
