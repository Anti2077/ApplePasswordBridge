import XCTest
@testable import ApplePasswordBridge

final class ApplicationRulesTests: XCTestCase {
    func testFillSpeedsAreOrderedFastestToSlowest() {
        XCTAssertLessThan(FillSpeed.extreme.keyDelayNanoseconds, FillSpeed.reliable.keyDelayNanoseconds)
        XCTAssertLessThan(FillSpeed.reliable.keyDelayNanoseconds, FillSpeed.compatible.keyDelayNanoseconds)
        XCTAssertEqual(FillSpeed.extreme.keyDelayNanoseconds, 40_000_000)
    }

    func testAllowlistOnlyPermitsListedApplications() {
        let policy = ApplicationRulePolicy(
            mode: .allowlist,
            allowlist: ["org.mozilla.firefox"],
            denylist: []
        )
        XCTAssertTrue(policy.permits(bundleIdentifier: "org.mozilla.firefox"))
        XCTAssertFalse(policy.permits(bundleIdentifier: "app.zen-browser.zen"))
    }

    func testDenylistPermitsUnlistedApplications() {
        let policy = ApplicationRulePolicy(
            mode: .denylist,
            allowlist: [],
            denylist: ["app.zen-browser.zen"]
        )
        XCTAssertTrue(policy.permits(bundleIdentifier: "org.mozilla.firefox"))
        XCTAssertFalse(policy.permits(bundleIdentifier: "app.zen-browser.zen"))
    }

    func testDenylistAlwaysExcludesBridgeAndCodeSources() {
        let policy = ApplicationRulePolicy(mode: .denylist, allowlist: [], denylist: [])
        XCTAssertFalse(policy.permits(bundleIdentifier: "com.anti.ApplePasswordBridge"))
        XCTAssertFalse(policy.permits(
            bundleIdentifier: PasswordCodeReader.extensionHelperBundleIdentifier
        ))
        XCTAssertFalse(policy.permits(bundleIdentifier: PasswordCodeReader.passwordBundleIdentifier))
    }
}
