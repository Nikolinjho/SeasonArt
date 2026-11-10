import AppKit
import ApplicationServices

/// Пассивная геометрия Dock. Дополнительных разрешений и системных диалогов не запрашивает.
final class DockIconGeometry {
    private var refreshedAt: CFTimeInterval = -10
    private var settings = DockMagnificationSettings.disabled
    private var frames: [DockSnowIcon]?
    private var nearAt: CFTimeInterval = -10
    private var presentationFrame: CGRect?
    private var sampledAt: CFTimeInterval = -10
    /// AX-ответ Dock может идти десятки миллисекунд: опрос идёт в фоне, кадр берёт последний готовый снимок.
    private let queue = DispatchQueue(label: "dev.nikoko.SeasonArt.dock-geometry", qos: .userInteractive)
    private let lock = NSLock()
    private var sampling = false
    private var sampled: (icons: [DockSnowIcon]?, dock: CGRect?)?
    /// Профили крыш меняются только в фоновой очереди.
    private var queueProfiles: [String: [Float]] = [:]

    static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Реальная область наведения включает увеличенные иконки выше обычной полки.
    var interactionFrame: CGRect? {
        guard let presentationFrame, let frames, !frames.isEmpty else { return nil }
        return frames.reduce(presentationFrame) { partial, icon in
            partial.union(icon.frame).union(icon.badge?.frame ?? icon.frame)
        }
    }

    func update(now: CFTimeInterval, screen: CGRect, primaryHeight: CGFloat, dock: CGRect?, cursor: CGPoint)
        -> (settings: DockMagnificationSettings, icons: [DockSnowIcon]?, dock: CGRect?) {
        if now - refreshedAt > 1 {
            refreshedAt = now
            let defaults = UserDefaults(suiteName: "com.apple.dock")
            let normal = defaults?.double(forKey: "tilesize") ?? 0
            let large = defaults?.double(forKey: "largesize") ?? 0
            settings = DockMagnificationSettings(enabled: defaults?.bool(forKey: "magnification") ?? false,
                normalSize: normal > 0 ? normal : 48, largeSize: large > 0 ? large : 128)
        }
        guard let dock else {
            frames = nil
            presentationFrame = nil
            lock.withLock { sampled = nil }
            return (settings, nil, nil)
        }
        if let ready = lock.withLock({ () -> (icons: [DockSnowIcon]?, dock: CGRect?)? in
            defer { sampled = nil }
            return sampled
        }) {
            frames = ready.icons?.filter {
                $0.frame.width <= settings.largeSize * 1.8 && $0.frame.width > 0
                    && $0.frame.maxX >= dock.minX && $0.frame.minX <= dock.maxX
            }
            presentationFrame = ready.dock
        }
        if cursor.x >= dock.minX - settings.largeSize, cursor.x <= dock.maxX + settings.largeSize,
           cursor.y >= dock.minY - 4, cursor.y <= dock.maxY + settings.largeSize - settings.normalSize + 12 {
            nearAt = now
        }
        let stillMagnified = frames?.contains { $0.frame.width > settings.normalSize + 0.5 } ?? false
        if !settings.isActive || (now - nearAt >= 0.4 && !stillMagnified), now - sampledAt < 0.5 {
            return (settings, frames, presentationFrame)
        }
        // Новый запрос уходит, только когда предыдущий ответ уже получен: очередь не копит устаревшие опросы.
        guard !lock.withLock({ sampling }) else { return (settings, frames, presentationFrame) }
        sampledAt = now
        lock.withLock { sampling = true }
        queue.async { [weak self] in
            guard let self else { return }
            let result = sample(screen: screen, primaryHeight: primaryHeight, dock: dock)
            lock.withLock {
                self.sampled = result
                self.sampling = false
            }
        }
        return (settings, frames, presentationFrame)
    }

    /// Дожидается фонового опроса. Нужен проверкам, кадр никогда не ждёт.
    func finishPendingSample() { queue.sync {} }

    /// Dock обновляет размеры значков раньше части AXPosition. Их текущая раскладка задаётся рамкой списка.
    static func laidOutFrames(in list: CGRect, items: [CGRect]) -> [CGRect] {
        let total = items.reduce(CGFloat(0)) { $0 + $1.width }
        guard total.isFinite, total > 0, list.width.isFinite else { return items }
        var left = list.minX + (list.width - total) / 2
        return items.map { item in
            defer { left += item.width }
            return CGRect(x: left, y: item.minY, width: item.width, height: item.height)
        }
    }

    private func sample(screen: CGRect, primaryHeight: CGFloat, dock: CGRect) -> (icons: [DockSnowIcon]?, dock: CGRect?) {
        var presentationFrame: CGRect?
        let icons = iconFrames(screen: screen, primaryHeight: primaryHeight, dock: dock, presentationFrame: &presentationFrame)
        return (icons, presentationFrame)
    }

    private func iconFrames(screen: CGRect, primaryHeight: CGFloat, dock: CGRect, presentationFrame: inout CGRect?) -> [DockSnowIcon]? {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.02)
        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
            return value as? [AXUIElement] ?? []
        }
        var result: [DockSnowIcon] = []
        for list in children(app).prefix(4) {
            var listPosition: CFTypeRef?
            var listSize: CFTypeRef?
            var origin = CGPoint.zero
            var span = CGSize.zero
            guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &listPosition) == .success,
                  AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &listSize) == .success,
                  let listPosition, let listSize,
                  CFGetTypeID(listPosition) == AXValueGetTypeID(), CFGetTypeID(listSize) == AXValueGetTypeID(),
                  AXValueGetValue(listPosition as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(listSize as! AXValue, .cgSize, &span),
                  span.width > 0, span.width.isFinite, origin.x.isFinite else { continue }
            var items: [(frame: CGRect, url: URL?, badge: String?, subrole: String?)] = []
            for icon in children(list).prefix(100) {
                let keys = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXURLAttribute, "AXStatusLabel", kAXSubroleAttribute] as CFArray
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(icon, keys, [], &values) == .success,
                      let values = values as? [Any], values.count == 6,
                      values[0] as? String == "AXDockItem",
                      CFGetTypeID(values[1] as CFTypeRef) == AXValueGetTypeID(),
                      CFGetTypeID(values[2] as CFTypeRef) == AXValueGetTypeID() else { continue }
                var point = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(values[1] as! AXValue, .cgPoint, &point),
                      AXValueGetValue(values[2] as! AXValue, .cgSize, &size),
                      point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
                      size.width > 0, size.height > 0 else { continue }
                items.append((CGRect(origin: point, size: size), values[3] as? URL, values[4] as? String, values[5] as? String))
            }
            guard !items.isEmpty else { continue }
            let laidOut = Self.laidOutFrames(in: CGRect(origin: origin, size: span), items: items.map(\.frame))
            presentationFrame = CGRect(x: origin.x - screen.minX, y: dock.minY, width: span.width, height: dock.height)
            for (item, bounds) in zip(items, laidOut) {
                guard bounds.width > 4 else { continue }
                let key: String
                let loadImage: () -> NSImage?
                if item.subrole == "AXTrashDockItem" {
                    key = "AXTrashDockItem"
                    loadImage = { NSImage(named: NSImage.trashEmptyName) }
                } else if let url = item.url, url.isFileURL {
                    key = url.path
                    loadImage = { NSWorkspace.shared.icon(forFile: url.path) }
                } else {
                    continue
                }
                let profile: [Float]
                if let existing = queueProfiles[key] {
                    profile = existing
                } else {
                    guard let image = loadImage(), let measured = Self.roofProfile(of: image) else { continue }
                    queueProfiles[key] = measured
                    profile = measured
                }
                // AXDockItem включает строку индикатора и свободное место над изображением.
                let side = bounds.width - 2
                let image = CGRect(x: bounds.minX - screen.minX + 1,
                    y: primaryHeight - bounds.maxY - screen.minY + 6, width: side, height: side)
                result.append(DockSnowIcon(frame: image, roof: profile,
                    badge: DockSnowBadge(label: item.badge, iconFrame: image)))
            }
        }
        return result
    }

    static func roofProfile(of image: NSImage) -> [Float]? {
        var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
        return (0..<64).map { column in
            let x = min(bitmap.pixelsWide - 1, column * bitmap.pixelsWide / 64)
            for y in 0..<bitmap.pixelsHigh {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                    return 1 - Float(y) / Float(bitmap.pixelsHigh)
                }
            }
            return 0
        }
    }
}
