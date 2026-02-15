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
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        })
        navigationItem.leftBarButtonItem = close
        navigationItem.title = "Make QR Code"

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
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            imageView.widthAnchor.constraint(equalToConstant: 240),
            imageView.heightAnchor.constraint(equalToConstant: 240),
        ])
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
        guard let renderedImage, let png = renderedImage.pngData() else { return }
        let activity = UIActivityViewController(activityItems: [png], applicationActivities: nil)
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
