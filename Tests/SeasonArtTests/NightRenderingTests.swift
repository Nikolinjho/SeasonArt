import AppKit
import Metal
import XCTest
@testable import SeasonArt

final class NightRenderingTests: XCTestCase {
    func testMetalРисуетСветлячковИМетеорыНепустымЦветнымКадром() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        for mode: Mode in [.fireflies, .starfall] {
            let simulation = SnowSimulation(width: 800, height: 600, snowfall: .steady)
            simulation.mode = mode
            for _ in 0..<150 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(400, 300)) }
            let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm, simulation: simulation)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 800, height: 600, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.015, 0.025, 0.06, 1)
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            renderer.encode(into: commands, pass: pass, scale: 1, time: 2.5)
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            var bytes = [UInt8](repeating: 0, count: 800 * 600 * 4)
            texture.getBytes(&bytes, bytesPerRow: 800 * 4, from: MTLRegionMake2D(0, 0, 800, 600), mipmapLevel: 0)
            let lit = stride(from: 0, to: bytes.count, by: 4).filter { max(bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) > 60 }
            XCTAssertGreaterThan(lit.count, 20, "На экране виден свет, а не только фон")
            if mode == .fireflies {
                XCTAssertTrue(lit.contains { Int(bytes[$0 + 1]) > Int(bytes[$0]) + 20 }, "Огоньки имеют жёлто-зелёный оттенок")
            } else {
                XCTAssertTrue(lit.contains { Int(bytes[$0]) > Int(bytes[$0 + 2]) + 15 }, "Метеоры имеют холодный оттенок")
            }
            if let folder = ProcessInfo.processInfo.environment["SEASONART_NIGHT_PREVIEW"] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 800 * 4, bitsPerPixel: 32))
                let pixels = try XCTUnwrap(bitmap.bitmapData)
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    pixels[i] = bytes[i + 2]
                    pixels[i + 1] = bytes[i + 1]
                    pixels[i + 2] = bytes[i]
                    pixels[i + 3] = bytes[i + 3]
                }
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("\(mode).png"))
            }
        }
    }
}
