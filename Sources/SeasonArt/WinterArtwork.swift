import AppKit

enum WinterArtwork {
    static let snow = load("PackedSnow")
    static let shovel = load("Shovel")
    static let tree = load("Evergreen")
    static let sleigh = load("Sleigh")
    static let reindeer = load("Reindeer")
    static let clothing = load("SnowmanClothing")

    private static let snowGradient = NSGradient(starting: .white,
        ending: NSColor(calibratedRed: 0.65, green: 0.79, blue: 0.87, alpha: 1))

    static func drawSnow(in path: NSBezierPath, bounds: CGRect) {
        snowGradient?.draw(in: path, angle: -50)
        guard let snow else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        path.addClip()
        let material = bounds.insetBy(dx: -bounds.width * 0.055, dy: -bounds.height * 0.055)
        snow.draw(in: material, from: .zero, operation: .sourceOver, fraction: 0.93)
    }

    private static func load(_ name: String) -> NSImage? {
        let subdirectory = "WinterArt"
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
        return url.flatMap(NSImage.init(contentsOf:))
    }
}
