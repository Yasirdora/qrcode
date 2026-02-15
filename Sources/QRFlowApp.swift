import SwiftUI

@main
struct QRFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Onboarding ↔ shell switch plus the global toast overlay — the handoff's
/// RootContent pattern, minus the catalog preload (this app has no heavy
/// startup work; CoreImage renders on demand in milliseconds).
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            if model.onboardingComplete {
                ShellView(model: model)
                    .transition(.opacity)
            } else {
                OnboardingView(model: model)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(message: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.onboardingComplete)
        .animation(.smooth(duration: 0.3), value: model.toast)
    }
}

struct ShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        // LiD geometry: capsule leading, orb trailing. The system only
        // left-aligns its capsule for a search-role orb — ours is custom, so
        // the whole bar is custom and content switches directly (no TabView
        // bar to fight with).
        Group {
            switch model.tab {
            case .create:
                CreateView(model: model)
            case .scan:
                ScanView(model: model)
            }
        }
        .transition(.opacity)
        // No `.id(model.tab)`: a fresh identity on every switch reset the
        // studio, so returning from Scan re-rendered the preview and lost
        // scroll position and focus.
        .animation(.snappy(duration: 0.25), value: model.tab)
        // Edge-to-edge horizontal swipe switches tabs — the gesture every
        // iOS user tries before hunting for a button.
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0, model.tab == .create {
                        Haptics.selection()
                        model.tab = .scan
                    } else if value.translation.width > 0, model.tab == .scan {
                        Haptics.selection()
                        model.tab = .create
                    }
                }
        )
        // safeAreaInset, not overlay: the bar floats over the content, so an
        // overlay let it sit on top of the scanability ring at the foot of the
        // Create surface. An inset reserves the space instead.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(model: model)
        }
    }
}

/// The bottom bar: leading tab capsule (Create / Scan) + trailing design
/// orb. Sits 10pt into the home-indicator zone, matching the system
/// capsule's resting place measured from screenshots.
private struct BottomBar: View {
    @Bindable var model: AppModel
    @Namespace private var tabPill

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                TabButton(title: "Create", image: "qrcode",
                          isSelected: model.tab == .create, namespace: tabPill) { select(.create) }
                TabButton(title: "Scan", image: "qrcode.viewfinder",
                          isSelected: model.tab == .scan, namespace: tabPill) { select(.scan) }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            // The design orb is contextual to the Create surface.
            if model.tab == .create {
                DesignOrb(model: model)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.tab)
        .padding(.horizontal, 16)
        .padding(.bottom, -10)
    }

    private func select(_ tab: AppModel.Tab) {
        guard model.tab != tab else { return }
        Haptics.selection()
        model.tab = tab
    }
}

/// One capsule tab: icon + label. The selection pill is ONE view moving
/// between tabs via matchedGeometryEffect — it slides to its new home
/// instead of blinking out and in, which is what makes this read as a
/// tab switch rather than two buttons.
private struct TabButton: View {
    let title: String
    let image: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    // Scales with the label it contains: a fixed 72×50 capsule clipped the
    // text at the larger Dynamic Type sizes. The default still meets the
    // 44pt minimum touch target.
    @ScaledMetric(relativeTo: .caption2) private var width = 72
    @ScaledMetric(relativeTo: .caption2) private var height = 50

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: image).font(.body.weight(.medium))
                Text(title).font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(width: width, height: height)
            .contentShape(.capsule)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Floating glass button opening the design sheet.
private struct DesignOrb: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            Haptics.lightImpact()
            model.designSheetPresented = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 54, height: 54)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Design settings")
        .accessibilityHint("Opens colors, logo and reliability options")
    }
}
