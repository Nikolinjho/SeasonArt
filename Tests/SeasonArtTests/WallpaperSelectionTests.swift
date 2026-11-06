import AppKit
import XCTest
@testable import SeasonArt

final class WallpaperSelectionTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    func testMissingFileIsRejected() {
        let url = temporaryURL(extension: "png")
        XCTAssertThrowsError(try WallpaperSelection.validate(url)) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .missingFile, "Отсутствующий файл должен быть отклонён")
        }
    }

    func testInvalidImageIsRejected() throws {
        let url = temporaryURL(extension: "png")
        try Data("Это не изображение".utf8).write(to: url)
        XCTAssertThrowsError(try WallpaperSelection.validate(url)) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .invalidImage, "Повреждённое изображение должно быть отклонено")
        }
    }

    func testRemoteURLIsRejected() {
        XCTAssertThrowsError(try WallpaperSelection.validate(URL(string: "https://example.com/wallpaper.png")!)) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .notLocalFile, "Разрешены только локальные файлы")
        }
    }

    func testGeneratedPNGIsAccepted() throws {
        let url = try makePNG()
        XCTAssertNoThrow(try WallpaperSelection.validate(url), "Сгенерированное изображение должно пройти проверку")
    }

    func testCancellationDoesNotApplyWallpaper() throws {
        var calls = 0
        let failures = try WallpaperSelection.apply(nil, to: ["Первый", "Второй"], name: { $0 }) { _, _ in calls += 1 }
        XCTAssertEqual(calls, 0, "Отмена не должна менять обои")
        XCTAssertTrue(failures.isEmpty, "Отмена не должна создавать ошибку")
    }

    func testInvalidSelectionDoesNotApplyWallpaper() throws {
        var calls = 0
        XCTAssertThrowsError(try WallpaperSelection.apply(temporaryURL(extension: "png"), to: ["Экран"], name: { $0 }) { _, _ in calls += 1 })
        XCTAssertEqual(calls, 0, "Проверка файла должна предшествовать изменению обоев")
    }

    func testAppliesToEveryScreenAndCollectsPartialFailures() throws {
        let url = try makePNG()
        var applied: [String] = []
        let error = NSError(domain: "SeasonArtTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Нет разрешения"])
        let failures = try WallpaperSelection.apply(url, to: ["Первый", "Второй", "Третий"], name: { $0 }) { receivedURL, screen in
            XCTAssertEqual(receivedURL, url, "Используется выбранный файл без копирования")
            applied.append(screen)
            if screen == "Второй" { throw error }
        }
        XCTAssertEqual(applied, ["Первый", "Второй", "Третий"], "Ошибка одного экрана не должна прерывать остальные")
        XCTAssertEqual(failures.count, 1, "Собираются только ошибки изменения")
        XCTAssertEqual(failures.first?.screenName, "Второй", "В ошибке должно быть имя экрана")
        XCTAssertEqual(failures.first?.message, "Нет разрешения", "В ошибке должна быть причина системы")
    }

    func testErrorAlertExplainsValidationFailure() {
        let error = WallpaperSelectionError.invalidImage
        let alert = WallpaperController.errorAlert(error.localizedDescription)
        XCTAssertEqual(alert.messageText, "Не удалось установить обои", "Пользователь должен видеть назначение ошибки")
        XCTAssertEqual(alert.informativeText, error.localizedDescription, "Диалог должен показывать причину отказа")
        XCTAssertEqual(alert.buttons.first?.title, "Понятно", "Диалог можно закрыть без изменения обоев")
    }

    private func temporaryURL(extension suffix: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SeasonArtTests-\(UUID().uuidString).\(suffix)")
        temporaryURLs.append(url)
        return url
    }

    private func makePNG() throws -> URL {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = temporaryURL(extension: "png")
        try data.write(to: url)
        return url
    }
}
