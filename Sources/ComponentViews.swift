import SwiftUI

/// Shared components. Same rule as the handoff: colors come from the asset
/// catalog tokens (`AccentColor`), never hard-coded — light, dark and tinted
/// appearances stay consistent for free.

/// Flat grouped-content surface: the iOS 26 inset-grouped idiom — a plain
/// fill on the grouped background, no shadow, no stroke. Shadows and
/// hairlines were what made the app read as a web page.
struct PanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func panel(cornerRadius: CGFloat = 20) -> some View {
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

/// Global toast — announced to VoiceOver, auto-dismissed by AppModel.
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
