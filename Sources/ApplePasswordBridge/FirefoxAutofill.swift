import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

enum AutofillFailure: LocalizedError {
    case noEligibleApplicationRunning
    case authorizationWindowNotFound
    case inputNotFound
    case focusFailed
    case eventCreationFailed
    case unsupportedDigit

    var errorDescription: String? {
        switch self {
        case .noEligibleApplicationRunning: return "没有符合应用规则的浏览器正在运行"
        case .authorizationWindowNotFound: return "未在允许的应用中找到 iCloud 密码授权窗口"
        case .inputNotFound: return "授权窗口中未找到验证码输入框"
        case .focusFailed: return "无法聚焦验证码输入框"
        case .eventCreationFailed: return "无法创建键盘输入事件"
        case .unsupportedDigit: return "验证码包含不支持的字符"
        }
    }
}

final class BrowserAutofill {
    struct WindowIdentity: Hashable {
        let processIdentifier: pid_t
        let windowNumber: CGWindowID
    }

    struct Candidate {
        let identity: WindowIdentity
        let application: NSRunningApplication
    }

    struct Target {
        let identity: WindowIdentity
        let application: NSRunningApplication
        let window: AXUIElement
        let fields: [AccessibilityNode]
    }

    func authorizationWindowCandidates(policy: ApplicationRulePolicy) -> [Candidate] {
        let applications = eligibleApplicationsByPID(policy: policy)
        guard !applications.isEmpty else { return [] }

        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        var candidates: [Candidate] = []
        var seen = Set<WindowIdentity>()
        for info in windowInfo {
            let title = info[kCGWindowName as String] as? String
            guard AuthorizationContext.isICloudPasswordWindowTitle(title),
                  let rawPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let rawWindowNumber = info[kCGWindowNumber as String] as? NSNumber else {
                continue
            }
            let identity = WindowIdentity(
                processIdentifier: rawPID.int32Value,
                windowNumber: CGWindowID(rawWindowNumber.uint32Value)
            )
            guard !seen.contains(identity),
                  let application = applications[identity.processIdentifier] else {
                continue
            }
            seen.insert(identity)
            candidates.append(Candidate(identity: identity, application: application))
            if candidates.count == 4 { break }
        }
        return candidates
    }

    func prepareAccessibility(for candidates: [Candidate]) {
        var preparedProcesses = Set<pid_t>()
        for candidate in candidates where preparedProcesses.insert(
            candidate.application.processIdentifier
        ).inserted {
            let application = AXUIElementCreateApplication(
                candidate.application.processIdentifier
            )
            AccessibilityTree.enableEnhancedUserInterface(application)
        }
    }

    func locateTarget(candidates: [Candidate]) throws -> Target {
        guard !candidates.isEmpty else {
            throw AutofillFailure.noEligibleApplicationRunning
        }

        let groupedCandidates = Dictionary(grouping: candidates, by: { $0.application.processIdentifier })
        for (_, applicationCandidates) in groupedCandidates {
            guard let application = applicationCandidates.first?.application else { continue }
            let accessibilityApplication = AXUIElementCreateApplication(application.processIdentifier)
            AccessibilityTree.enableEnhancedUserInterface(accessibilityApplication)

            for window in AccessibilityTree.windows(of: accessibilityApplication) {
                let nodes = AccessibilityTree.collect(from: window)
                let title = AccessibilityTree.title(of: window)
                let text = nodes.map(\.text).joined(separator: "\n")
                let fields = nodes.filter(\.isTextInput).sorted {
                    ($0.position?.x ?? 0) < ($1.position?.x ?? 0)
                }
                let hasStablePopupSignature = AuthorizationContext.isBrowserExtensionPopup(
                    title: title,
                    text: text
                ) && fields.count >= 6
                let hasAuthorizationContext = AuthorizationContext.isBrowserExtensionAuthorization(
                    title: title,
                    text: text
                )
                guard hasStablePopupSignature || hasAuthorizationContext else { continue }
                guard !fields.isEmpty else { throw AutofillFailure.inputNotFound }
                return Target(
                    identity: applicationCandidates[0].identity,
                    application: application,
                    window: window,
                    fields: fields
                )
            }
        }
        throw AutofillFailure.authorizationWindowNotFound
    }

    func fill(code: String, target: Target, speed: FillSpeed) async throws {
        target.application.activate(options: [])
        AccessibilityTree.raise(target.window)
        try await Task.sleep(nanoseconds: 180_000_000)

        if target.fields.count >= code.count {
            for (field, digit) in zip(target.fields, code) {
                guard AccessibilityTree.focus(field.element) else { throw AutofillFailure.focusFailed }
                if let value = field.value, !value.isEmpty {
                    try postKey(CGKeyCode(kVK_Delete), processIdentifier: target.application.processIdentifier)
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
                try postDigit(digit, processIdentifier: target.application.processIdentifier)
                try await Task.sleep(nanoseconds: speed.keyDelayNanoseconds)
            }
        } else {
            guard let first = target.fields.first, AccessibilityTree.focus(first.element) else {
                throw AutofillFailure.focusFailed
            }
            for digit in code {
                try postDigit(digit, processIdentifier: target.application.processIdentifier)
                try await Task.sleep(nanoseconds: speed.keyDelayNanoseconds)
            }
        }
    }

    private func eligibleApplicationsByPID(
        policy: ApplicationRulePolicy
    ) -> [pid_t: NSRunningApplication] {
        var unique: [String: NSRunningApplication] = [:]
        let runningApplications: [NSRunningApplication]
        switch policy.mode {
        case .allowlist:
            runningApplications = policy.allowlist.flatMap {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0)
            }
        case .denylist:
            runningApplications = NSWorkspace.shared.runningApplications
        }

        for application in runningApplications {
            guard application.activationPolicy == .regular,
                  let bundleIdentifier = application.bundleIdentifier,
                  policy.permits(bundleIdentifier: bundleIdentifier),
                  unique[bundleIdentifier] == nil else {
                continue
            }
            unique[bundleIdentifier] = application
        }

        return Dictionary(
            unique.values.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func postDigit(_ digit: Character, processIdentifier: pid_t) throws {
        let keyCodes: [Character: CGKeyCode] = [
            "0": CGKeyCode(kVK_ANSI_0),
            "1": CGKeyCode(kVK_ANSI_1),
            "2": CGKeyCode(kVK_ANSI_2),
            "3": CGKeyCode(kVK_ANSI_3),
            "4": CGKeyCode(kVK_ANSI_4),
            "5": CGKeyCode(kVK_ANSI_5),
            "6": CGKeyCode(kVK_ANSI_6),
            "7": CGKeyCode(kVK_ANSI_7),
            "8": CGKeyCode(kVK_ANSI_8),
            "9": CGKeyCode(kVK_ANSI_9)
        ]
        guard let keyCode = keyCodes[digit] else { throw AutofillFailure.unsupportedDigit }
        try postKey(keyCode, processIdentifier: processIdentifier)
    }

    private func postKey(_ keyCode: CGKeyCode, processIdentifier: pid_t) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw AutofillFailure.eventCreationFailed
        }
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
    }
}
