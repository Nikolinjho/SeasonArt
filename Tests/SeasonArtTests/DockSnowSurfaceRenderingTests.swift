import AppKit
import Metal
import XCTest
@testable import SeasonArt

final class DockSnowSurfaceRenderingTests: XCTestCase {
    func testMetalРисуетЦельныйСугробРазнойТолщины() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = library.makeFunction(name: "pileVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "pileFragment")
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        let state = try device.makeRenderPipelineState(descriptor: pipeline)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var compactPixels = 0
        for (label, raised, depth): (String, Bool, Float) in [("resting", false, 7), ("compact", true, 7), ("fluffy", true, 11)] {
            let simulation = SnowSimulation(width: 900, height: 220, snowfall: .off)
            simulation.thaws = false
            simulation.cursorInteracts = false
            simulation.dockMagnification = DockMagnificationSettings(enabled: raised, normalSize: 47, largeSize: 76)
            let names = ["com.apple.finder", "com.google.Chrome", "ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap",
                         "com.microsoft.VSCode", "md.obsidian", "com.apple.Safari", "com.apple.dt.Xcode", "trash"]
            let sizes: [CGFloat] = raised ? [47, 47, 53, 65, 76, 67, 55, 47, 47] : Array(repeating: 47, count: 9)
            var icons: [DockSnowIcon] = []
            var images: [NSImage] = []
            var x: CGFloat = 170
            for (name, side) in zip(names, sizes) {
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
                    ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
                let image = name == "trash" ? try XCTUnwrap(NSImage(named: NSImage.trashEmptyName))
                    : NSWorkspace.shared.icon(forFile: url.path)
                images.append(image)
                let frame = CGRect(x: x, y: 11, width: side, height: side)
                icons.append(DockSnowIcon(frame: frame,
                    roof: try XCTUnwrap(DockIconGeometry.roofProfile(of: image)),
                    badge: name == "com.google.Chrome" ? DockSnowBadge(label: "19", iconFrame: frame) : nil))
                x += side + 8
            }
            let body = CGRect(x: 155, y: 6, width: x - 155 + 8, height: 60)
            simulation.dockIconFrames = icons
            simulation.updateWindows([WindowSurface(id: 42, frame: body,
                blockers: [], cover: [], cornerRadius: 20, cornerExponent: 2.5, isDock: true)], interval: 1 / 60)
            let layers = Mirror(reflecting: simulation).children.first { $0.label == "layers" }!.value as! [SnowLayer]
            let dock = try XCTUnwrap(layers.first { $0.isDock })
            for i in 0..<dock.count { dock.set(i, depth) }
            for _ in 0..<60 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(350, 40)) }
            let heights = try XCTUnwrap(device.makeBuffer(length: simulation.columnCount * MemoryLayout<Float>.stride, options: .storageModeShared))
            let piles = simulation.writeLayers(into: heights.contents().bindMemory(to: Float.self, capacity: simulation.columnCount),
                                               capacity: simulation.columnCount)
            var uniforms = Uniforms(viewSize: SIMD2(900, 220), scale: 1, time: 0, columnWidth: 2)
            var occluder = SIMD4<Float>.zero
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 900, height: 220, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
            encoder.setRenderPipelineState(state)
            encoder.setFragmentBytes(&occluder, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            for pile in piles where pile.isDock {
                uniforms.columnCount = Int32(pile.count)
                uniforms.columnWidth = pile.columnWidth
                uniforms.origin = pile.origin
                uniforms.pileTop = pile.top + 2
                uniforms.pileBottom = pile.bottom
                uniforms.occluderCount = Int32(pile.occluders.count)
                var occluders = pile.occluders.isEmpty ? [SIMD4<Float>.zero] : pile.occluders
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&occluders, length: occluders.count * MemoryLayout<SIMD4<Float>>.stride, index: 2)
                encoder.setFragmentBuffer(heights, offset: pile.offset * MemoryLayout<Float>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            var bytes = [UInt8](repeating: 0, count: 900 * 220 * 4)
            texture.getBytes(&bytes, bytesPerRow: 900 * 4, from: MTLRegionMake2D(0, 0, 800, 200), mipmapLevel: 0)
            let badge = try XCTUnwrap(icons.compactMap(\.badge).first)
            let badgeX = Int(badge.frame.midX)
            let badgeY = Int(ceil(badge.frame.maxY + 1))
            XCTAssertGreaterThan(bytes[((219 - badgeY) * 900 + badgeX) * 4 + 1], 100,
                                 "Шейдер рисует белую шапку прямо на бейдже ниже общей полки")
            var upperSnow = 0
            for y in 82..<110 {
                for x in 300..<600 {
                    let i = ((219 - y) * 900 + x) * 4
                    if bytes[i + 1] > 100 { upperSnow += 1 }
                }
            }
            if raised { XCTAssertGreaterThan(upperSnow, 100, "Сугроб виден над увеличенными значками") }
            else { XCTAssertEqual(upperSnow, 0, "Без увеличения снег остаётся на полке") }
            var gaps = 0
            for x in Int(body.minX + 25)..<Int(body.maxX - 25) {
                let covered = (40..<115).contains { y in bytes[((219 - y) * 900 + x) * 4 + 1] > 100 }
                if !covered { gaps += 1 }
            }
            XCTAssertEqual(gaps, 0, "Каждое сечение цельного сугроба содержит снег")
            let lit = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0 + 1] > 100 }.count
            if label == "compact" { compactPixels = lit }
            if label == "fluffy" { XCTAssertGreaterThan(lit, compactPixels + 500, "Больший запас даёт более объёмный сугроб") }
            if let folder = ProcessInfo.processInfo.environment["SEASONART_DOCK_SURFACE_PREVIEW"] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 220,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 900 * 4, bitsPerPixel: 32))
                let pixels = try XCTUnwrap(bitmap.bitmapData)
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    pixels[i] = bytes[i + 2]
                    pixels[i + 1] = bytes[i + 1]
                    pixels[i + 2] = bytes[i]
                    pixels[i + 3] = bytes[i + 3]
                }
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let scene = NSImage(size: NSSize(width: 900, height: 220))
                scene.lockFocus()
                NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.085, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 900, height: 220).fill()
                NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
                NSBezierPath(roundedRect: body, xRadius: 20, yRadius: 20).fill()
                for (image, icon) in zip(images, icons) { image.draw(in: icon.frame) }
                for badge in icons.compactMap(\.badge) {
                    NSColor.systemRed.setFill()
                    NSBezierPath(ovalIn: badge.frame).fill()
                }
                let snow = NSImage(size: NSSize(width: 900, height: 220))
                snow.addRepresentation(bitmap)
                snow.draw(in: NSRect(x: 0, y: 0, width: 900, height: 220))
                scene.unlockFocus()
                let composite = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(scene.tiffRepresentation)))
                try XCTUnwrap(composite.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(label + ".png"))
            }
        }
    }
}
