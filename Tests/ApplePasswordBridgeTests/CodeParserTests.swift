import XCTest
@testable import ApplePasswordBridge

final class CodeParserTests: XCTestCase {
    func testExtractsSpacedVerificationCode() {
        XCTAssertEqual(VerificationCodeParser.extract(from: "验证码 630 955"), "630955")
    }

    func testExtractsSeparatedDigits() {
        XCTAssertEqual(VerificationCodeParser.extract(from: "1 2 3 4 5 6"), "123456")
    }

    func testRejectsLongerNumbers() {
        XCTAssertNil(VerificationCodeParser.extract(from: "订单号 1234567"))
    }

    func testRequiresAuthorizationContext() {
        XCTAssertTrue(AuthorizationContext.isApplePasswordAuthorization(
            "Mac 已生成验证码。请输入该验证码以继续。启用密码自动填充"
        ))
        XCTAssertFalse(AuthorizationContext.isApplePasswordAuthorization("请输入短信验证码"))
    }

    func testFirefoxContextRequiresExtensionIdentity() {
        XCTAssertTrue(AuthorizationContext.isBrowserExtensionAuthorization(
            title: "iCloud 密码",
            text: "启用密码自动填充 请输入验证码"
        ))
        XCTAssertFalse(AuthorizationContext.isBrowserExtensionAuthorization(
            title: "银行登录",
            text: "启用自动填充 请输入验证码"
        ))
    }

    func testFirefoxPopupUsesStableTitleAndURLSignature() {
        XCTAssertTrue(AuthorizationContext.isBrowserExtensionPopup(
            title: "iCloud 密码",
            text: "moz-extension://dynamic-id/page_popup.html?popupWindow=1"
        ))
        XCTAssertTrue(AuthorizationContext.isBrowserExtensionPopup(
            title: "iCloud Passwords",
            text: "chrome-extension://stable-id/page_popup.html?popupWindow=1"
        ))
        XCTAssertFalse(AuthorizationContext.isBrowserExtensionPopup(
            title: "iCloud 密码",
            text: "https://example.com/page_popup.html"
        ))
    }

    func testICloudPasswordWindowTitleMatching() {
        XCTAssertTrue(AuthorizationContext.isICloudPasswordWindowTitle("iCloud 密码"))
        XCTAssertTrue(AuthorizationContext.isICloudPasswordWindowTitle("iCloud Passwords"))
        XCTAssertFalse(AuthorizationContext.isICloudPasswordWindowTitle("iCloud 云盘"))
        XCTAssertFalse(AuthorizationContext.isICloudPasswordWindowTitle("银行密码"))
    }

    func testCapturedCodeExpires() {
        let now = Date()
        let code = CapturedCode(value: "123456", capturedAt: now, source: .vision)
        XCTAssertTrue(code.isFresh(at: now.addingTimeInterval(44)))
        XCTAssertFalse(code.isFresh(at: now.addingTimeInterval(46)))
    }
}
