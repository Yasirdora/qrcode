# QRFlow Studio for iOS — Developer Handoff

**Date:** 9 August 2026 · **Stack:** SwiftUI, iOS 26 · **Patterned after:** `EinbürgerungLiD-Handoff`

A native iOS edition of the QRFlow Studio web app, built to the same quality bar as the
reference handoff: single `@Observable` model, pure testable logic, token colors,
shared components, haptic vocabulary, privacy manifest — **no third-party dependencies**.

## What shipped verified

The pure logic core (`Models`, `PayloadBuilder`, `Scanability`) was compiled and executed
with `swiftc` against a 15-assertion runtime harness before any UI was written:

```
PASS — wifi escaping        PASS — vcard structure        PASS — contrast b/w = 21.0
PASS — scheme passthrough   PASS — event validation       PASS — default score 100
PASS — whatsapp digits      PASS — version bounds         PASS — quiet zone flagged
… 15/15 ALL TESTS PASSED
```

The XCTest suites in `Tests/` pin the same behavior inside Xcode.
**The SwiftUI/UIKit layer is written against documented iOS APIs but has NOT been compiled —
this machine has no iOS SDK. First build in Xcode is the moment of truth; treat it as such.**

## Architecture in one paragraph

Single `@Observable AppModel` (all state, tabs, toast, UserDefaults persistence). Pure
Foundation core: `PayloadBuilder` (11 content types → QR payloads, ISO/IEC 18004 version
estimation) and `Scanability` (WCAG contrast, density, logo-occlusion-vs-EC, quiet-zone
scoring). `QRRenderer` is 100% platform: `CIQRCodeGenerator` + `CIFalseColor` +
CoreGraphics compositing (quiet zone, logo knockout, Context Band, PDF via
`UIGraphicsPDFRenderer`). Shared components in `ComponentViews` (`panel`, `PanelRow`,
`ScoreRing`, `CheckRow`, `ToastView`). History persists via UserDefaults (privacy
manifest reason `CA92.1`).

## File map

| File | Role |
|---|---|
| `Sources/QRFlowApp.swift` | `@main`, RootView (onboarding ↔ shell + toast), TabView shell |
| `Sources/AppModel.swift` | `@Observable` state, history persistence, toast lifecycle |
| `Sources/Models.swift` | `ContentType`, `ContentState`, `DesignOptions`, `HistoryEntry` — Codable, SwiftUI-free |
| `Sources/PayloadBuilder.swift` | Payloads for 11 content types + summaries + version estimation |
| `Sources/Scanability.swift` | The 0–100 scanability engine |
| `Sources/QRRenderer.swift` | CoreImage QR → colored, quiet-zoned, logo, Context Band, PNG/PDF |
| `Sources/ComponentViews.swift` | Shared panel/rows/score ring/toast |
| `Sources/CreateViews.swift` | Studio screen: preview card, type grid, export |
| `Sources/CreateFormViews.swift` | Per-type forms + Design sheet |
| `Sources/ScanViews.swift` | Camera (AVFoundation) + PhotosPicker + paste (CIDetector) |
| `Sources/HistoryViews.swift` | Saved designs grid, re-edit, delete |
| `Sources/OnboardingViews.swift` | One-screen onboarding |
| `Tests/` | XCTest suites for both pure modules |
| `PrivacyInfo.xcprivacy` | No tracking, no collected data, UserDefaults CA92.1 |

## Xcode setup (10 minutes)

1. Xcode → **Create New Project** → iOS → **App** → SwiftUI, Swift, name `QRFlow`,
   deployment target **iOS 26.0**.
2. Delete the template's `ContentView.swift` and `@main` file; drag `Sources/*.swift`
   into the app target; drag `Tests/*.swift` into the test target.
3. Add `PrivacyInfo.xcprivacy` to the app target (Build Phases → Copy Bundle Resources).
4. Asset catalog: create an `AccentColor` set (signature color, light/dark variants).
5. Info settings: add `NSCameraUsageDescription` = "Scan QR codes with your camera."
   Add `ITSAppUsesNonExemptEncryption` = NO.
6. ⌘U — both test suites should pass. ⌘R on an iPhone simulator.

## Known honest limitations (roadmap, not hidden)

- **Dot styles** (rounded/dots/classy) don't exist in `CIQRCodeGenerator` — native v1
  renders classic square modules with full color/EC/quiet-zone control. Custom module
  shapes need a hand-rolled matrix renderer (roadmap item, ~day of work).
- PDF embeds a 2048px raster rather than true vector paths — indistinguishable in print,
  but SVG-equivalent purity is a roadmap item.
- Batch generation from the web app is not ported (mobile-first scope decision).
- Drag-and-drop from the web scanner doesn't apply to iOS; paste + PhotosPicker cover it.
- Verify camera + paste flows on real hardware, not only the simulator.

## App Store checklist (when you get there)

- [ ] Age rating 4+ · privacy policy URL (even with "no data collected")
- [ ] `ITSAppUsesNonExemptEncryption = NO` — already noted above
- [ ] Privacy manifest bundled — done (`PrivacyInfo.xcprivacy`)
- [ ] Screenshots 6.9″ + 6.5″ · description with "no account, offline, open source"
- [ ] Real-device pass: camera scan, paste decode, PDF export, history restore
