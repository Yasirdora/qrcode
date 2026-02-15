import UIKit

/// Central haptic feedback. Small, consistent vocabulary: selection ticks for
/// navigation, light impact for toggles, and notification feedback for
/// outcomes. (Adopted verbatim from the handoff's Haptics.swift pattern.)
@MainActor
enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
