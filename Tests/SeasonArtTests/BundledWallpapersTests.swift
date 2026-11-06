import AppKit
import XCTest
@testable import SeasonArt

final class BundledWallpapersTests: XCTestCase {
    private var root: URL!
    private var sourceRoot: URL { root.appendingPathComponent("Resources") }
    private var supportRoot: URL { root.appendingPathComponent("Application Support") }
    private var sourceURL: URL { sourceRoot.appendingPathComponent("Wallpapers/winter-lake-v1.png") }
    private var wallpapers: BundledWallpapers {
        BundledWallpapers(resourceRoot: sourceRoot, applicationSupportRoot: supportRoot)
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SeasonArtWallpapers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testStoresValidImageOutsideBundleWithoutChangingSource() throws {
        let original = try makeSourcePNG()
        let result = try wallpapers.persistentURL()
        XCTAssertEqual(result, supportRoot.appendingPathComponent("SeasonArt/Wallpapers/winter-lake-v1.png"), "Обои должны храниться в Application Support под постоянным именем")
        XCTAssertNoThrow(try WallpaperSelection.validate(result), "Сохранённая копия должна быть изображением")
        XCTAssertEqual(try Data(contentsOf: result), original, "Копия должна сохранять исходное изображение")
        XCTAssertEqual(try Data(contentsOf: sourceURL), original, "Ресурс приложения не должен изменяться")
    }

    func testRepeatedApplicationKeepsSamePersistentURL() throws {
        try makeSourcePNG()
        let first = try wallpapers.persistentURL()
        XCTAssertEqual(try wallpapers.persistentURL(), first, "Повторное применение должно использовать прежний адрес")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.deletingLastPathComponent().path), ["winter-lake-v1.png"], "Сохранение не должно оставлять временные копии")
    }

    func testMissingSourceDoesNotCreateCache() {
        XCTAssertThrowsError(try wallpapers.persistentURL()) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .missingFile, "Отсутствующий ресурс должен приводить к понятной ошибке")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportRoot.path), "Ошибка чтения не должна создавать кэш")
    }

    func testCorruptSourceDoesNotReplaceValidCache() throws {
        let original = try makeSourcePNG()
        let cached = try wallpapers.persistentURL()
        try Data("Повреждённый ресурс".utf8).write(to: sourceURL)
        XCTAssertThrowsError(try wallpapers.persistentURL()) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .invalidImage, "Повреждённый ресурс должен быть отклонён")
        }
        XCTAssertEqual(try Data(contentsOf: cached), original, "Ошибка ресурса должна сохранять исправную копию")
    }

    func testRepairsCorruptCachedImageFromBundledSource() throws {
        let original = try makeSourcePNG()
        let cached = try wallpapers.persistentURL()
        try Data("Повреждённый кэш".utf8).write(to: cached)
        XCTAssertEqual(try wallpapers.persistentURL(), cached, "Восстановление должно сохранить постоянный адрес")
        XCTAssertEqual(try Data(contentsOf: cached), original, "Повреждённая копия должна восстанавливаться из ресурса")
        XCTAssertNoThrow(try WallpaperSelection.validate(cached), "Восстановленные обои должны читаться")
    }

    func testReadingPreviewDoesNotCreateCache() throws {
        try makeSourcePNG()
        let previewURL = wallpapers.sourceURL
        XCTAssertNoThrow(try WallpaperSelection.validate(previewURL), "Превью должно читать исходный ресурс")
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportRoot.path), "Чтение превью не должно сохранять обои")
    }

    @discardableResult
    private func makeSourcePNG() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: sourceURL)
        return data
    }
}
