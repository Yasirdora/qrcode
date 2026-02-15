import UIKit
import UniformTypeIdentifiers

/// Share-sheet entry point: "turn this page/text into a QR code" from any
/// app — the workflow competitor apps force through copy → open → paste.
///
/// A plain UIViewController (not SLComposeServiceViewController) so the
/// preview matches QRFlow's design language. Rendering reuses the app's
/// exact QRRenderer pipeline — the shared sources are compiled into this
/// target, so there is no second implementation to drift.
@MainActor
final class ShareViewController: UIViewController {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private var renderedImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        extractSharedContent()
    }

    // MARK: - UI

    private func buildUI() {
        // A real button in the view hierarchy, not a
        // `navigationItem.leftBarButtonItem`. The extension is launched with
        // `NSExtensionPrincipalClass` and no storyboard, so there is no
        // navigation controller and no navigation bar — the item never
        // rendered, and the sheet could not be dismissed at all.
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .secondaryLabel
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = "Share QR Code"
        config.cornerStyle = .capsule
        shareButton.configuration = config
        shareButton.isHidden = true
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addAction(UIAction { [weak self] _ in self?.shareRendered() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, shareButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            imageView.widthAnchor.constraint(equalToConstant: 240),
            imageView.heightAnchor.constraint(equalToConstant: 240),
        ])
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    // MARK: - Extraction

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return showError()
        }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        let text = (data as? URL)?.absoluteString
                        Task { @MainActor in
                            if let text { self.render(payload: text) } else { self.showError() }
                        }
                    }
                    return
                }
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        let text = data as? String
                        Task { @MainActor in
                            if let text { self.render(payload: text) } else { self.showError() }
                        }
                    }
                    return
                }
            }
        }
        showError()
    }

    // MARK: - Render & share

    private func render(payload: String) {
        var design = DesignOptions()
        design.exportSize = 1024
        guard let image = QRRenderer.image(payload: payload, design: design) else {
            return showError()
        }
        renderedImage = image
        imageView.image = image
        titleLabel.text = QRRenderer.destinationLabel(payload: payload)
        shareButton.isHidden = false
    }

    private func shareRendered() {
        // A file URL rather than raw Data: Data reaches Mail and Messages as an
        // unnamed, sometimes untyped attachment, while a .png on disk keeps
        // both its name and its type.
        guard let renderedImage, let png = renderedImage.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qr.Code-\(UUID().uuidString.prefix(8)).png")
        try? png.write(to: url)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard completed, let self else { return }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
        present(activity, animated: true)
    }

    private func showError() {
        titleLabel.text = "Couldn't read the shared content."
        imageView.image = UIImage(systemName: "exclamationmark.triangle")
        imageView.tintColor = .secondaryLabel
    }
}
