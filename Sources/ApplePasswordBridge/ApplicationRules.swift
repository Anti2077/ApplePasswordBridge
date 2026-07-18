import Foundation

enum FillSpeed: String, CaseIterable, Identifiable {
    case compatible
    case reliable
    case extreme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compatible: return "兼容"
        case .reliable: return "稳健"
        case .extreme: return "极速"
        }
    }

    var keyDelayNanoseconds: UInt64 {
        switch self {
        case .compatible: return 140_000_000
        case .reliable: return 80_000_000
        case .extreme: return 40_000_000
        }
    }
}

enum ApplicationRuleMode: String, CaseIterable, Identifiable {
    case allowlist
    case denylist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowlist: return "白名单"
        case .denylist: return "黑名单"
        }
    }
}

struct TargetApplication: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }

    static let firefox = TargetApplication(
        bundleIdentifier: "org.mozilla.firefox",
        displayName: "Firefox"
    )
}

struct ApplicationRulePolicy {
    let mode: ApplicationRuleMode
    let allowlist: Set<String>
    let denylist: Set<String>

    func permits(bundleIdentifier: String) -> Bool {
        switch mode {
        case .allowlist:
            return allowlist.contains(bundleIdentifier)
        case .denylist:
            return !denylist.contains(bundleIdentifier)
                && bundleIdentifier != "com.anti.ApplePasswordBridge"
                && bundleIdentifier != PasswordCodeReader.extensionHelperBundleIdentifier
                && bundleIdentifier != PasswordCodeReader.passwordBundleIdentifier
        }
    }
}
