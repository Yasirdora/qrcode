#if DEBUG
import SwiftUI

/// A scripted tour for the README's demo clip, enabled by the -ui-demo launch
/// hook. It moves the same model state the UI moves when you tap — content,
/// tab and design — so the recording exercises the real rendering path rather
/// than a mock. DEBUG-only: release builds compile it away.
@MainActor
enum UIDemo {
    static func run(_ model: AppModel) {
        Task { @MainActor in
            // Start from an empty code so the first thing the clip shows is the
            // code building itself, keystroke by keystroke.
            model.content.url = ""
            try? await Task.sleep(for: .seconds(1.2))

            let address = "https://github.com/yasirdora"
            for end in stride(from: 2, through: address.count, by: 2) {
                model.content.url = String(address.prefix(end))
                try? await Task.sleep(for: .milliseconds(95))
            }
            try? await Task.sleep(for: .milliseconds(900))

            // Into the studio and through two looks: dots first, then fluid
            // with a gradient — the scanability score reacts honestly to the
            // second one, which is the product telling the truth.
            model.tab = .design
            try? await Task.sleep(for: .milliseconds(1100))

            withAnimation(.snappy(duration: 0.35)) {
                model.design.dotType = .dots
                model.design.cornerSquareType = .dot
                model.design.cornerDotType = .dot
            }
            try? await Task.sleep(for: .milliseconds(1600))

            withAnimation(.snappy(duration: 0.45)) {
                model.design.dotType = .fluid
                model.design.cornerSquareType = .extraRounded
                model.design.cornerDotType = .dot
                model.design.fgHex = "#0A84FF"
                model.design.gradientColor2Hex = "#22D3EE"
                model.design.gradientEnabled = true
            }
            try? await Task.sleep(for: .milliseconds(1900))

            // Back to the create surface for the finished code, and hold.
            model.tab = .create
            try? await Task.sleep(for: .seconds(3.0))
        }
    }
}
#endif
