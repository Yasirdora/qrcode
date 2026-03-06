import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage
import Vision

/// Three input paths, one decode pipeline — live camera (AVFoundation
/// metadata) and photo library / paste (Vision). Both frameworks recognize
/// every symbology the studio writes, plus Data Matrix which we only read.
struct ScanView: View {
    @Bindable var model: AppModel
    @State private var result: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraDenied = false
    @State private var lastHandled: String?
    @State private var lastCaptureDate = Date.distantPast
    @State private var duplicateNotified = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    cameraCell
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        if let img = UIPasteboard.general.image, let data = img.pngData() {
                            decodeStill(data)
                        } else {
                            Haptics.error()
                            model.showToast("No image on the clipboard")
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Result") {
                    resultRows
                }
            }
            .listStyle(.insetGrouped)
            // Presented over the app, so it carries its own way out: there is no
            // tab bar behind it to fall back to.
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.lightImpact()
                        model.scanPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close the scanner")
                }
            }
            .task { await resolveCameraAuthorization() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        decodeStill(data)
                    }
                }
            }
        }
        // A viewfinder is dark whatever the system appearance is: every camera
        // experience on this platform is, and a white sheet in front of a lens
        // is the wrong thing to hold up at night.
        .preferredColorScheme(.dark)
    }

    /// Without this, a user who taps "Don't Allow" once gets a black
    /// rectangle forever — AVCaptureDeviceInput just fails silently.
    private func resolveCameraAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            cameraDenied = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraDenied = !granted
        default:
            cameraDenied = false
        }
    }

    private var cameraCell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black)
                .aspectRatio(4 / 3, contentMode: .fit)
            if cameraDenied {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.title)
                    Text("Camera access is off — enable it in Settings, or decode an image below.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                CameraPreview { payload in handleCameraDecode(payload) }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                // After a capture the user needs two things: to KNOW the code
                // was captured, and a way to reset. Without this overlay the
                // scanner felt broken — pointing did nothing, silently.
                if result != nil {
                    VStack {
                        Spacer()
                        Button {
                            resetScanner()
                        } label: {
                            Label("Scan Again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.snappy(duration: 0.25), value: result != nil)
                }
            }
        }
    }

    /// Debounce + duplicate feedback. The metadata delegate fires every
    /// frame while a code is in frame: a NEW payload captures instantly;
    /// the SAME payload after a grace period gets one "already scanned"
    /// notice instead of silence. Reset clears both, so re-pointing at the
    /// same code captures it fresh.
    private func handleCameraDecode(_ payload: String) {
        let now = Date()
        if payload == lastHandled {
            if !duplicateNotified && now.timeIntervalSince(lastCaptureDate) > 2.5 {
                duplicateNotified = true
                Haptics.lightImpact()
                model.showToast("Already scanned this code")
            }
            return
        }
        lastHandled = payload
        lastCaptureDate = now
        duplicateNotified = false
        result = payload
        Haptics.success()
    }

    private func resetScanner() {
        result = nil
        lastHandled = nil
        duplicateNotified = false
        Haptics.lightImpact()
    }

    @ViewBuilder
    private var resultRows: some View {
        if let result {
            Text(result)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = result
                model.showToast("Copied to clipboard")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if let url = URL(string: result), url.scheme?.hasPrefix("http") == true {
                Link(destination: url) {
                    Label("Open Link", systemImage: "safari")
                }
            }
        } else {
            Text("Point the camera at a barcode, pick a photo, or paste one — QR, Aztec, PDF417, Code 128, EAN and Data Matrix all decode on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func decodeStill(_ data: Data) {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            Haptics.error()
            model.showToast("Could not read that image")
            return
        }
        // Vision detects every symbology we write (QR, Aztec, PDF417,
        // Code 128, EAN-13/8) and several we only read, like Data Matrix.
        // Orientation matters: camera-roll photos carry rotation in EXIF
        // and cgImage is the raw sensor buffer — without this, ordinary
        // portrait photos fail to decode (review C7).
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: cgImage, orientation: exifOrientation(uiImage.imageOrientation)).perform([request])
        if let code = request.results?.first?.payloadStringValue {
            Haptics.success()
            lastHandled = code
            lastCaptureDate = Date()
            result = code
        } else {
            Haptics.error()
            model.showToast("No barcode found in that image")
        }
    }

    /// UIImage.Orientation and CGImagePropertyOrientation number their cases
    /// differently; map by name, not by raw value.
    private func exifOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// AVCaptureSession wrapper — continuous QR detection via metadata output.
/// Debounce lives in ScanView (it owns the reset); this just reports.
private struct CameraPreview: UIViewControllerRepresentable {
    let onDecode: (String) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onDecode = { payload in
            DispatchQueue.main.async { onDecode(payload) }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

private final class CameraViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onDecode: ((String) -> Void)?
    /// startRunning/stopRunning are documented thread-safe; the property is
    /// only touched from the session's own start/stop calls.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .aztec, .pdf417, .code128, .ean13, .ean8, .dataMatrix]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    /// AVCaptureSession start/stop are documented thread-safe; box it so it can
    /// cross into the detached task without Swift 6 sending-closure diagnostics.
    private struct SessionBox: @unchecked Sendable { let session: AVCaptureSession }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let box = SessionBox(session: session)
        Task.detached(priority: .userInitiated) { box.session.startRunning() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let box = SessionBox(session: session)
        Task.detached(priority: .userInitiated) { box.session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = object.stringValue else { return }
        onDecode?(payload)
    }
}
