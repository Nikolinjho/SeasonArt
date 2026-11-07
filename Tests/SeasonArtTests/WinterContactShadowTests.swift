import AppKit
import XCTest
@testable import SeasonArt

final class WinterContactShadowTests: XCTestCase {
    private func object(_ radii: [CGFloat], x: CGFloat = 100, y: CGFloat = 28) -> WinterObject {
        WinterObject(id: UUID(), radii: radii, center: CGPoint(x: x, y: y), velocity: .zero,
                     support: nil, parked: false, isDragged: false)
    }

    private func render(_ object: WinterObject, among objects: [WinterObject], shadows: Bool = true) throws -> NSBitmapImageRep {
        let view = WinterObjectView(object: object)
        view.display(object: object, shadows: shadows ? WinterContactShadow.shadows(on: object, among: objects) : [])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(object.presentationFrame.width * 2)), pixelsHigh: Int(ceil(object.presentationFrame.height * 2)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = object.presentationFrame.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        view.draw(view.bounds)
        NSGraphicsContext.current?.flushGraphics()
        return bitmap
    }

    private func darkenedPixels(_ before: NSBitmapImageRep, _ after: NSBitmapImageRep) throws -> Int {
        var count = 0
        for y in 0..<before.pixelsHigh {
            for x in 0..<before.pixelsWide {
                let a = try XCTUnwrap(before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(a.alphaComponent, b.alphaComponent, accuracy: 0.015,
                               "Тень не выходит за силуэт шара и не меняет его прозрачность")
                if a.redComponent - b.redComponent > 0.025 { count += 1 }
            }
        }
        return count
    }

    func testСтыкиСнеговикаЗатемняютсяБезИзмененияСилуэта() throws {
        for radii: [CGFloat] in [[28, 21], [28, 21, 14], [6, 36, 10], [36, 6, 36]] {
            let snowman = object(radii)
            let before = try render(snowman, among: [], shadows: false)
            let after = try render(snowman, among: [])
            XCTAssertGreaterThan(try darkenedPixels(before, after), 12)
        }
    }

    func testОтдельныйШарИСнеговикОтбрасываютТеньНаНижнийШар() throws {
        let base = object([28])
        for radii: [CGFloat] in [[14], [21, 14, 10]] {
            let upper = object(radii, y: 56 + radii[0])
            let before = try render(base, among: [], shadows: false)
            let after = try render(base, among: [base, upper])
            XCTAssertGreaterThan(try darkenedPixels(before, after), 12)
        }
    }

    func testБоковыеУдалённыеИСкрытыеШарыНеДаютКонтактнойТени() {
        let base = object([28])
        var hidden = object([14], y: 70)
        hidden.parked = true
        var dragged = object([14], y: 70)
        dragged.isDragged = true
        for other in [object([14], x: 142), object([14], y: 100), hidden, dragged] {
            XCTAssertTrue(WinterContactShadow.shadows(on: base, among: [base, other]).isEmpty)
        }
    }

    func testПеремещениеВерхнегоШараОбновляетТеньНеподвижногоНижнего() throws {
        _ = NSApplication.shared
        let base = object([28])
        let upper = object([14], y: 70)
        let window = WinterObjectWindow(object: base, screenFrame: .zero)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? WinterObjectView)
        view.display(object: base, shadows: WinterContactShadow.shadows(on: base, among: [upper]))
        view.needsDisplay = false
        view.display(object: base, shadows: [])
        XCTAssertTrue(view.needsDisplay, "Уход верхнего шара перерисовывает нижний даже без его движения")
    }

    func testСравнениеОтрисовкиДоИПосле() throws {
        guard let path = ProcessInfo.processInfo.environment["SEASONART_SHADOW_PREVIEW"] else { return }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1680, pixelsHigh: 990,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        let context = try XCTUnwrap(NSGraphicsContext.current?.cgContext)
        context.scaleBy(x: 3, y: 3)
        NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.27, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 560, height: 330)).fill()
        let scenes = [[object([28, 21, 14], x: 70)],
                      [object([28], x: 70), object([14], x: 70, y: 70)],
                      [object([28], x: 70), object([21, 14, 10], x: 70, y: 77)],
                      [object([12, 30, 14], x: 70, y: 12)]]
        for (index, objects) in scenes.enumerated() {
            for withShadows in [false, true] {
                context.saveGState()
                context.translateBy(x: CGFloat(index) * 140, y: withShadows ? 12 : 180)
                for model in objects {
                    context.saveGState()
                    context.translateBy(x: model.presentationFrame.minX, y: model.presentationFrame.minY)
                    let view = WinterObjectView(object: model)
                    view.display(object: model, shadows: withShadows ? WinterContactShadow.shadows(on: model, among: objects) : [])
                    view.draw(view.bounds)
                    context.restoreGState()
                }
                context.restoreGState()
            }
        }
        NSGraphicsContext.current?.flushGraphics()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
