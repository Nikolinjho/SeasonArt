import AppKit

struct BundledWallpapers {
    let resourceRoot: URL
    let applicationSupportRoot: URL

    init(
        resourceRoot: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL,
        applicationSupportRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) {
        self.resourceRoot = resourceRoot
        self.applicationSupportRoot = applicationSupportRoot
    }

    var sourceURL: URL { resourceRoot.appendingPathComponent("Wallpapers/winter-lake-v1.png") }

    func persistentURL() throws -> URL {
        try WallpaperSelection.validate(sourceURL)
        let sourceData = try Data(contentsOf: sourceURL)
        let directory = applicationSupportRoot.appendingPathComponent("SeasonArt/Wallpapers", isDirectory: true)
        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if (try? Data(contentsOf: destination)) != sourceData {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sourceData.write(to: destination, options: .atomic)
        }
        try WallpaperSelection.validate(destination)
        return destination
    }
}
