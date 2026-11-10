import AppKit
import Metal
import XCTest
@testable import SeasonArt

final class DockSnowSurfaceRenderingTests: XCTestCase {
    func testГлубокийНижнийСнегУступаетРасширенномуDockИВозвращаетсяПослеСжатия() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let simulation = SnowSimulation(width: 600, height: 200, snowfall: .off)
        let body = CGRect(x: 100, y: 6, width: 300, height: 60)
        let surface = WindowSurface(id: 42, frame: body, blockers: [], cover: [],
            cornerRadius: 0, cornerExponent: 2, isDock: true)
        simulation.updateWindows([surface], interval: 1 / 60)
        simulation.dockMagnification = DockMagnificationSettings(enabled: true, normalSize: 48, largeSize: 100)
        let ground = try XCTUnwrap(Mirror(reflecting: simulation).children.first { $0.label == "ground" }?.value as? SnowLayer)
        for i in ground.heights.indices { ground.set(i, 100) }
        ground.refreshTop()
        let before = ground.heights
        let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm, simulation: simulation)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 600, height: 200, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        func render() throws -> [UInt8] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            renderer.encode(into: commands, pass: pass, scale: 1, time: 0)
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            var bytes = [UInt8](repeating: 0, count: 600 * 200 * 4)
            texture.getBytes(&bytes, bytesPerRow: 600 * 4, from: MTLRegionMake2D(0, 0, 600, 200), mipmapLevel: 0)
            XCTAssertEqual(ground.heights, before, "Наведение меняет только видимость накопленного снега")
            return bytes
        }
        func alpha(_ pixels: [UInt8], _ x: Int, _ y: Int) -> UInt8 {
            pixels[((199 - y) * 600 + x) * 4 + 3]
        }

        for _ in 0..<3 {
            // Высота AX может отставать. Отсечение использует текущую высоту корпуса.
            simulation.dockPresentationFrame = CGRect(x: 60, y: 150, width: 400, height: 60)
            simulation.dockIconFrames = [DockSnowIcon(frame: CGRect(x: 65, y: 12, width: 100, height: 100), roof: [1, 1])]
            let expanded = try render()
            XCTAssertEqual(alpha(expanded, 80, 20), 0, "Снег слева уступает расширившемуся Dock")
            XCTAssertEqual(alpha(expanded, 440, 20), 0, "Снег справа уступает расширившемуся Dock")
            XCTAssertEqual(alpha(expanded, 80, 80), 0, "Высокая иконка не утопает в глубоком сугробе")
            XCTAssertGreaterThan(alpha(expanded, 40, 20), 240, "Вне Dock снег остаётся виден")
            XCTAssertGreaterThan(alpha(expanded, 480, 20), 240, "За правой границей снег остаётся виден")
            XCTAssertGreaterThan(alpha(expanded, 440, 80), 240, "Над пустым участком корпуса лишнего выреза нет")

            simulation.dockPresentationFrame = body
            simulation.dockIconFrames = []
            let contracted = try render()
            XCTAssertGreaterThan(alpha(contracted, 80, 20), 240, "При сжатии левый снег возвращается")
            XCTAssertGreaterThan(alpha(contracted, 440, 20), 240, "При сжатии правый снег возвращается")
            XCTAssertEqual(alpha(contracted, 250, 20), 0, "Обычный корпус продолжает скрывать снег")
        }

        simulation.dockPresentationFrame = CGRect(x: 60, y: 6, width: 400, height: 60)
        simulation.dockIconFrames = [DockSnowIcon(frame: CGRect(x: 65, y: 12, width: 100, height: 100), roof: [1, 1])]
        simulation.dockSnowPosition = .below
        let below = try render()
        XCTAssertGreaterThan(alpha(below, 80, 20), 240, "Под Dock нижний слой остаётся виден")
        XCTAssertGreaterThan(alpha(below, 80, 80), 240, "Под Dock иконки не вырезают нижний слой")
        simulation.dockSnowPosition = .above
        simulation.updateWindows([], interval: 1 / 60)
        let hidden = try render()
        XCTAssertGreaterThan(alpha(hidden, 80, 80), 240, "Скрытый Dock не оставляет вырез по старой геометрии AX")
        XCTAssertGreaterThan(alpha(hidden, 250, 20), 240, "Скрытый корпус больше не скрывает снег")
    }

    func testНастоящийRendererСкрываетЗемлюКорпусомDockБезПереносаМассы() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let simulation = SnowSimulation(width: 600, height: 200, snowfall: .off)
        simulation.updateWindows([WindowSurface(id: 42, frame: CGRect(x: 100, y: 6, width: 300, height: 60),
            blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2, isDock: true)], interval: 1 / 60)
        let ground = try XCTUnwrap(Mirror(reflecting: simulation).children.first { $0.label == "ground" }?.value as? SnowLayer)
        for i in ground.heights.indices { ground.set(i, 30) }
        ground.refreshTop()
        let before = ground.heights
        let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm, simulation: simulation)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 600, height: 200, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        for position in [DockSnowPosition.above, .below] {
            simulation.dockSnowPosition = position
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            renderer.encode(into: commands, pass: pass, scale: 1, time: 0)
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            var bytes = [UInt8](repeating: 0, count: 600 * 200 * 4)
            texture.getBytes(&bytes, bytesPerRow: 600 * 4, from: MTLRegionMake2D(0, 0, 600, 200), mipmapLevel: 0)
            let rowOffset: Int = 179 * 600 * 4
            XCTAssertGreaterThan(bytes[rowOffset + 203], 240, "Сбоку снег остаётся виден")
            let coveredAlpha: UInt8 = bytes[rowOffset + 1003]
            if position == .above {
                XCTAssertEqual(coveredAlpha, 0, "Корпус скрывает нижний снег")
            } else {
                XCTAssertGreaterThan(coveredAlpha, 240, "В режиме Под Dock земля остаётся в нижнем слое")
            }
            XCTAssertEqual(ground.heights, before, "Отсечение не меняет массу")
        }
    }

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
                    badge: ["com.google.Chrome", "com.microsoft.VSCode"].contains(name)
                        ? DockSnowBadge(label: "19", iconFrame: frame) : nil))
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
            for badge in icons.compactMap(\.badge) {
                let badgeX = Int(badge.frame.midX)
                let badgeY = Int(ceil(badge.frame.maxY + 1))
                let pixel = bytes[((219 - badgeY) * 900 + badgeX) * 4 + 1]
                if badge.frame.maxY > body.maxY + 0.8 {
                    XCTAssertGreaterThan(pixel, 100, "Шапка видна на выступающем бейдже")
                } else {
                    XCTAssertEqual(pixel, 0, "Внутри Dock под общим сугробом отдельного снега нет")
                }
            }
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
