import AppKit

struct FinderGarlandLayout: Equatable {
    let frame: CGRect
    let visibleRanges: [Range<CGFloat>]
    let strandWidth: CGFloat
    let scroll: CGFloat

    init?(surface: WindowSurface, screen: CGRect) {
        guard surface.isFinder else { return nil }
        let band = CGRect(x: surface.frame.minX + surface.cornerRadius, y: surface.frame.maxY - 24,
                          width: surface.frame.width - 2 * surface.cornerRadius, height: 24)
        let visible = band.intersection(CGRect(origin: .zero, size: screen.size))
        guard band.width >= 25, visible.width >= 10, !visible.isEmpty else { return nil }
        var ranges = [visible.minX..<visible.maxX]
        for blocker in surface.cover where blocker.intersects(visible) {
            ranges = ranges.flatMap { range -> [Range<CGFloat>] in
                let lower = max(range.lowerBound, blocker.minX)
                let upper = min(range.upperBound, blocker.maxX)
                guard lower < upper else { return [range] }
                var result: [Range<CGFloat>] = []
                if range.lowerBound < lower { result.append(range.lowerBound..<lower) }
                if upper < range.upperBound { result.append(upper..<range.upperBound) }
                return result
            }
        }
        guard !ranges.isEmpty else { return nil }
        frame = visible.offsetBy(dx: screen.minX, dy: screen.minY)
        visibleRanges = ranges.map { ($0.lowerBound - visible.minX)..<($0.upperBound - visible.minX) }
        strandWidth = band.width
        scroll = visible.minX - band.minX
    }

    func draw(in rect: CGRect) {
        let clip = NSBezierPath()
        for range in visibleRanges {
            clip.appendRect(NSRect(x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound, height: rect.height))
        }
        clip.addClip()
        let spans = max(1, Int(strandWidth / 96))
        let period = strandWidth / CGFloat(spans)
        func y(_ x: CGFloat) -> CGFloat {
            let sag = 6 * pow(sin((x + scroll) * .pi / period), 2)
            return rect.maxY - 3 - sag
        }
        let wire = NSBezierPath()
        wire.move(to: CGPoint(x: 0, y: y(0)))
        for x in stride(from: CGFloat(3), through: rect.width + 3, by: 3) {
            wire.line(to: CGPoint(x: x, y: y(x)))
        }
        NSColor(calibratedRed: 0.19, green: 0.28, blue: 0.23, alpha: 0.84).setStroke()
        wire.lineWidth = 1
        wire.stroke()
        let spacing: CGFloat = 14
        let first = Int((scroll / spacing).rounded(.down))
        let last = Int(((scroll + rect.width) / spacing).rounded(.up))
        for index in first...last {
            let x = CGFloat(index) * spacing - scroll
            WinterLights.bulb(at: CGPoint(x: x, y: y(x) - 3.7), radius: 2.35, colorIndex: index)
        }
    }
}

final class FinderGarlands {
    private var windows: [CGWindowID: WinterToyWindow] = [:]
    private var previous: [CGWindowID: FinderGarlandLayout] = [:]
    var showsInScreenshots = false {
        didSet { for window in windows.values { window.showsInScreenshots = showsInScreenshots } }
    }

    func display(_ surfaces: [WindowSurface], on screen: CGRect) {
        let layouts = Dictionary(uniqueKeysWithValues: surfaces.compactMap { surface in
            FinderGarlandLayout(surface: surface, screen: screen).map { (surface.id, $0) }
        })
        guard layouts != previous else { return }
        for id in Array(windows.keys) where layouts[id] == nil { windows.removeValue(forKey: id)?.close() }
        for (id, layout) in layouts where previous[id] != layout {
            if let window = windows[id] {
                window.setFrame(layout.frame, display: false)
                window.updateArtwork(layout.draw(in:))
            } else {
                let window = WinterToyWindow(frame: layout.frame, interactive: false, draw: layout.draw(in:))
                window.title = "SeasonArt · гирлянда Finder"
                window.showsInScreenshots = showsInScreenshots
                window.orderFrontRegardless()
                windows[id] = window
            }
        }
        previous = layouts
    }

    func close() {
        for window in windows.values { window.close() }
        windows.removeAll()
        previous.removeAll()
    }
}
