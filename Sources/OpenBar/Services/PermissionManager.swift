import ApplicationServices

@MainActor
final class PermissionManager {
    private var hasPromptedAccessibility = false
    private var hasPromptedScreenRecording = false

    func requirePermissions() throws {
        try requireAccessibility()
        try requireScreenCapture()
    }

    func requireAccessibility() throws {
        let accessibilityGranted: Bool
        if hasPromptedAccessibility {
            accessibilityGranted = AXIsProcessTrusted()
        } else {
            hasPromptedAccessibility = true
            accessibilityGranted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        guard accessibilityGranted else { throw OpenBarError.accessibilityPermission }
    }

    func requireScreenCapture() throws {
        var captureGranted = CGPreflightScreenCaptureAccess()
        if !captureGranted && !hasPromptedScreenRecording {
            hasPromptedScreenRecording = true
            captureGranted = CGRequestScreenCaptureAccess()
        }
        guard captureGranted else { throw OpenBarError.screenRecordingPermission }
    }
}
