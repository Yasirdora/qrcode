import SwiftUI

/// One-screen onboarding in the handoff's visual language: icon, promise,
/// three tinted feature rows, single primary action, honest disclaimer.
struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "qrcode")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 24, y: 8)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Qr.Code")
                        .font(.largeTitle.weight(.bold))
                    Text("Design QR codes that actually scan — private, offline, on your device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 0) {
                    FeatureRow(
                        title: "Scanability score",
                        subtitle: "Contrast, density, quiet zone and logo occlusion — graded live.",
                        systemImage: "checkmark.shield",
                        tint: .green
                    )
                    Divider().padding(.leading, 56)
                    FeatureRow(
                        title: "11 content types",
                        subtitle: "Wi-Fi, contacts, events, WhatsApp — plus raw custom payloads.",
                        systemImage: "square.grid.3x3",
                        tint: .accentColor
                    )
                    Divider().padding(.leading, 56)
                    FeatureRow(
                        title: "Private on device",
                        subtitle: "No account, no ads, no upload. Everything stays here.",
                        systemImage: "lock.shield",
                        tint: .orange
                    )
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    Haptics.lightImpact()
                    withAnimation { model.onboardingComplete = true }
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, 24)

                Text("Open source · no tracking · works offline")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}
