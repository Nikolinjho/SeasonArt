import AppKit

final class WallpaperGalleryController: NSWindowController {
    private let wallpapers: BundledWallpapers

    init(wallpapers: BundledWallpapers = BundledWallpapers()) {
        self.wallpapers = wallpapers
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        do {
            try WallpaperSelection.validate(wallpapers.sourceURL)
            guard let image = NSImage(contentsOf: wallpapers.sourceURL) else {
                throw WallpaperSelectionError.invalidImage
            }
            if window == nil { window = makeWindow(image: image) }
            NSApp.activate()
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func makeWindow(image: NSImage) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Сезонные обои"
        window.minSize = NSSize(width: 540, height: 420)
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView()
        window.contentView = content
        let title = NSTextField(labelWithString: "Зимнее озеро")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let preview = NSImageView()
        preview.image = image
        preview.imageScaling = .scaleProportionallyUpOrDown
        // Размер исходной иллюстрации не должен увеличивать окно превью.
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.setAccessibilityLabel("Зимнее озеро, превью обоев")
        let explanation = NSTextField(wrappingLabelWithString: "Изображение станет обоями на всех подключённых экранах.")
        explanation.textColor = .secondaryLabelColor
        let apply = NSButton(title: "Применить на всех экранах", target: self, action: #selector(applyWallpaper))
        apply.bezelStyle = .rounded
        apply.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [title, preview, explanation, apply] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            preview.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            preview.bottomAnchor.constraint(equalTo: explanation.topAnchor, constant: -20),
            explanation.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            explanation.trailingAnchor.constraint(equalTo: apply.leadingAnchor, constant: -16),
            explanation.centerYAnchor.constraint(equalTo: apply.centerYAnchor),
            apply.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            apply.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        return window
    }

    @objc private func applyWallpaper() {
        do {
            let url = try wallpapers.persistentURL()
            let failures = try WallpaperSelection.apply(url, to: NSScreen.screens, name: { $0.localizedName }) { url, screen in
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            if !failures.isEmpty {
                showError(failures.map { "\($0.screenName): \($0.message)" }.joined(separator: "\n"))
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        NSApp.activate()
        let alert = WallpaperController.errorAlert(message)
        if let window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
