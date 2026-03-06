import SwiftUI

/// Shared components. Same rule as the handoff: colors come from the asset
/// catalog tokens (`AccentColor`), never hard-coded — light, dark and tinted
/// appearances stay consistent for free.

/// Visual constants, and the one rule that governs them: the chrome follows the
/// system appearance, the paper never does. A code is printed on white in both
/// appearances — a symbol on a dark surface is a scanability problem, not a
/// style choice.
enum Theme {
    // Radii
    static let card: CGFloat = 22
    static let control: CGFloat = 14

    // Spacing
    static let gutter: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let tight: CGFloat = 8

    // Chrome, all adaptive
    static var page: Color { Color(.systemGroupedBackground) }
    static var surface: Color { Color(.secondarySystemGroupedBackground) }
    static var surfaceRaised: Color { Color(.tertiarySystemGroupedBackground) }
    static var hairline: Color { Color(.separator).opacity(0.45) }
    static var accent: Color { .accentColor }

    /// The one colour that does not follow the appearance.
    static let paper = Color.white
    static let ink = Color(red: 0.067, green: 0.094, blue: 0.153)
}

/// Flat grouped-content surface: a plain fill on the grouped background, no
/// shadow and no stroke, so a card reads as paper rather than as a web panel.
struct PanelModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.card

    func body(content: Content) -> some View {
        content
            .background(Theme.surface,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func panel(cornerRadius: CGFloat = Theme.card) -> some View {
        modifier(PanelModifier(cornerRadius: cornerRadius))
    }
}

/// A list row in Apple's own pattern: plain tinted glyph, no circle wrap.
struct PanelRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .panel(cornerRadius: 20)
    }
}

/// Global toast. The VoiceOver announcement is posted by `AppModel.showToast`,
/// so the same message spoken twice is still spoken the second time.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.top, 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Scanability ring + grade, mirroring the web meter's visual language.
struct ScoreRing: View {
    let score: Int
    let grade: String

    private var color: Color {
        score >= 90 ? .green : score >= 70 ? Color(red: 0.4, green: 0.64, blue: 0.05) : score >= 45 ? .orange : .red
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.5), value: score)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(grade).font(.subheadline.weight(.medium)).foregroundStyle(color)
                Text("Scanability score").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanability score \(score) of 100, \(grade)")
    }
}

/// The mini ring for the inline score row — same visual language as
/// ScoreRing at list-accessory size.
struct MiniScoreRing: View {
    let score: Int

    private var color: Color {
        score >= 90 ? .green : score >= 70 ? Color(red: 0.4, green: 0.64, blue: 0.05) : score >= 45 ? .orange : .red
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.5), value: score)
            Text("\(score)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(width: 30, height: 30)
    }
}

/// A single scanability finding with its status glyph.
struct CheckRow: View {
    let check: Scanability.Check

    private var icon: (name: String, color: Color) {
        switch check.status {
        case .pass: ("checkmark.circle.fill", .green)
        case .warn: ("exclamationmark.triangle.fill", .orange)
        case .fail: ("xmark.circle.fill", .red)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon.name)
                .foregroundStyle(icon.color)
                .font(.subheadline)
            Text("\(Text(check.label + ": ").font(.footnote.weight(.medium)).foregroundStyle(.primary))\(Text(check.detail).font(.footnote).foregroundStyle(.secondary))")
        }
        .accessibilityElement(children: .combine)
    }
}
