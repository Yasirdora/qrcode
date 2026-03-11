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
    /// Whether the keyboard is up. A custom bar must not ride above it: the
    /// system's own bars are covered by the keyboard, and the field being typed
    /// into needs that space far more than the destinations do.
    @State private var typing = false

    var body: some View {
        // The bar is custom rather than a TabView's: the system only draws its
        // floating capsule for a search-role item, and this needs three
        // destinations beside a camera action.
        Group {
            switch model.tab {
            case .create:
                CreateView(model: model)
            case .design:
                DesignView(model: model)
            case .library:
                LibraryView(model: model)
            }
        }
        .transition(.opacity)
        // No `.id(model.tab)`: a fresh identity on every switch reset the
        // surface, so returning to Create re-rendered the preview and lost
        // scroll position and focus.
        .animation(.snappy(duration: 0.25), value: model.tab)
        // Edge-to-edge swipe walks the destinations in order — the gesture
        // people try before hunting for a button.
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let order = AppModel.Tab.allCases
                    guard let index = order.firstIndex(of: model.tab) else { return }
                    if value.translation.width < 0, index + 1 < order.count {
                        Haptics.selection()
                        model.tab = order[index + 1]
                    } else if value.translation.width > 0, index > 0 {
                        Haptics.selection()
                        model.tab = order[index - 1]
                    }
                }
        )
        // safeAreaInset, not overlay: the bar floats over the content, so an
        // overlay let it sit on top of the last row. An inset reserves the space,
        // and withdrawing the bar while typing reserves it for the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typing {
                BottomBar(model: model)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy(duration: 0.2), value: typing)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            typing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            typing = false
        }
        // A camera is somewhere you go and come back from, so it covers the app
        // rather than claiming a share of the destinations.
        .fullScreenCover(isPresented: $model.scanPresented) {
            ScanView(model: model)
        }
    }
}

/// The bottom bar: the three destinations in one glass capsule, the camera on
/// the other side. It sits 10pt into the home-indicator zone, where the system
/// puts its own capsule.
private struct BottomBar: View {
    @Bindable var model: AppModel
    @Namespace private var tabPill

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(AppModel.Tab.allCases, id: \.self) { tab in
                    TabButton(title: tab.title, image: tab.image,
                              isSelected: model.tab == tab, namespace: tabPill) {
                        select(tab)
                    }
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            CameraButton(model: model)
        }
        .animation(.snappy(duration: 0.25), value: model.tab)
        .padding(.horizontal, Theme.gutter)
        // A positive inset, never a negative offset: this bar is reserved as a
        // safe-area inset, and its measured height is what keeps the content
        // clear of it. A negative padding reserved less than the bar occupies,
        // which clipped the scanability row and the theme swatches.
        .padding(.bottom, 6)
    }

    private func select(_ tab: AppModel.Tab) {
        guard model.tab != tab else { return }
        Haptics.selection()
        model.tab = tab
    }
}

/// One capsule tab: icon over label. The selection pill is ONE view moving
/// between tabs via matchedGeometryEffect — it slides to its new home instead of
/// blinking out and in, which is what makes this read as a tab switch rather
/// than three buttons.
private struct TabButton: View {
    let title: String
    let image: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    // Scales with the label it contains: a fixed capsule clipped the text at the
    // larger Dynamic Type sizes. Three tabs and the camera share one row, so the
    // base is 64 rather than the 72 two tabs could afford.
    @ScaledMetric(relativeTo: .caption2) private var width = 64
    @ScaledMetric(relativeTo: .caption2) private var height = 50

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: image).font(.body.weight(.medium))
                Text(title).font(.caption2)
            }
            .foregroundStyle(isSelected ? Theme.accent : .primary)
            .frame(width: width, height: height)
            .contentShape(.capsule)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.accent.opacity(0.14))
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Opens the scanner. A camera is somewhere you go and come back from, so it
/// presents over everything rather than claiming a share of the destinations.
private struct CameraButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            Haptics.lightImpact()
            model.scanPresented = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 54, height: 54)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Scan a code")
        .accessibilityHint("Opens the camera")
    }
}
