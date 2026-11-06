import AppKit
import UniformTypeIdentifiers

final class WallpaperController {
    func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Выбрать обои"
        panel.prompt = "Применить"
        panel.message = "Выбранное изображение станет обоями на всех подключённых экранах."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
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
        Self.errorAlert(message).runModal()
    }

    static func errorAlert(_ message: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось установить обои"
        alert.informativeText = message
        alert.addButton(withTitle: "Понятно")
        return alert
    }
}
