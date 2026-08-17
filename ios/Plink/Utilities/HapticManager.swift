import UIKit

// MARK: - Haptic Manager
/// Centralized haptic feedback for key interactions.
enum HapticManager: Sendable {

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // Convenience methods for specific actions

    static func playPressed() { impact(.light) }
    static func pausePressed() { impact(.soft) }
    static func seekPerformed() { impact(.medium) }
    static func roomJoined() { notification(.success) }
    static func errorOccurred() { notification(.error) }
    static func syncCorrected() { selection() }
    static func voiceMuted() { impact(.rigid) }
    static func voiceUnmuted() { impact(.light) }
}
