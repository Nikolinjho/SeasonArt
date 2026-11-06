import AppKit

enum WallpaperSelectionError: Error, Equatable, LocalizedError {
    case notLocalFile
    case missingFile
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notLocalFile: return "Выберите изображение на этом Mac."
        case .missingFile: return "Выбранный файл больше не существует."
        case .invalidImage: return "Не удалось прочитать изображение. Выберите PNG, JPEG, HEIC или TIFF."
        }
    }
}

struct WallpaperApplyFailure {
    let screenName: String
    let message: String
}

enum WallpaperSelection {
    static func validate(_ url: URL) throws {
        guard url.isFileURL else { throw WallpaperSelectionError.notLocalFile }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw WallpaperSelectionError.missingFile
        }
        guard !isDirectory.boolValue, let image = NSImage(contentsOf: url), image.isValid else {
            throw WallpaperSelectionError.invalidImage
        }
    }

    static func apply<Screen>(
        _ url: URL?,
        to screens: [Screen],
        name: (Screen) -> String,
        setImage: (URL, Screen) throws -> Void
    ) throws -> [WallpaperApplyFailure] {
        guard let url else { return [] }
        try validate(url)
        var failures: [WallpaperApplyFailure] = []
        for screen in screens {
            do {
                try setImage(url, screen)
            } catch {
                failures.append(WallpaperApplyFailure(screenName: name(screen), message: error.localizedDescription))
            }
        }
        return failures
    }
}
