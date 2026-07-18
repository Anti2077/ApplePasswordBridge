import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

final class PasswordCodeReader {
    static let passwordBundleIdentifier = "com.apple.Passwords"
    static let extensionHelperBundleIdentifier = "com.apple.PasswordManagerBrowserExtensionHelper"

    func readUsingAccessibility() -> CapturedCode? {
        guard let (_, application) = AccessibilityTree.application(
            bundleIdentifier: Self.passwordBundleIdentifier
        ) else {
            return nil
        }

        for window in AccessibilityTree.windows(of: application) {
            let text = AccessibilityTree.collect(from: window)
                .map(\.text)
                .joined(separator: "\n")
            guard AuthorizationContext.isApplePasswordAuthorization(text),
                  let code = VerificationCodeParser.extract(from: text) else {
                continue
            }
            return CapturedCode(value: code, capturedAt: Date(), source: .accessibility)
        }
        return nil
    }

    func readUsingVision() async -> CapturedCode? {
        guard CGPreflightScreenCaptureAccess() else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let candidates = content.windows
                .filter(isAppleAuthorizationCandidate)
                .sorted { lhs, rhs in
                    let lhsIsPasswords = lhs.owningApplication?.bundleIdentifier == Self.passwordBundleIdentifier
                    let rhsIsPasswords = rhs.owningApplication?.bundleIdentifier == Self.passwordBundleIdentifier
                    return lhsIsPasswords && !rhsIsPasswords
                }
            for window in candidates {
                guard let image = try await capture(window: window) else { continue }
                let text = try recognizeText(in: image)
                let isDedicatedHelper = window.owningApplication?.bundleIdentifier
                    == Self.extensionHelperBundleIdentifier
                guard (isDedicatedHelper || AuthorizationContext.isApplePasswordAuthorization(text)),
                      let code = VerificationCodeParser.extract(from: text) else {
                    continue
                }
                return CapturedCode(value: code, capturedAt: Date(), source: .vision)
            }
        } catch {
            return nil
        }
        return nil
    }

    private func isAppleAuthorizationCandidate(_ window: SCWindow) -> Bool {
        guard window.frame.width >= 420,
              window.frame.width <= 1_300,
              window.frame.height >= 180,
              window.frame.height <= 800 else {
            return false
        }
        guard let bundleIdentifier = window.owningApplication?.bundleIdentifier else {
            return false
        }
        return bundleIdentifier == Self.passwordBundleIdentifier
            || bundleIdentifier == Self.extensionHelperBundleIdentifier
    }

    private func capture(window: SCWindow) async throws -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = displayScale(for: window.frame)
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func recognizeText(in image: CGImage) throws -> String {
        try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false

            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
    }

    private func displayScale(for frame: CGRect) -> CGFloat {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}
