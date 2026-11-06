# SeasonArt Local MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подготовить SeasonArt для личного локального использования Никитой: сезонные эффекты на окнах, управление из строки меню, собственные обои и независимая установка.

**Architecture:** Адаптировать macOS-часть зафиксированного Snowhush, сохранив его симуляцию и Metal-рендерер. Удалить Sparkle и механизм переноса приложения с DMG, отделить имя, bundle ID и настройки. Собственную новую функциональность ограничить обоями и локальной поставкой.

**Tech Stack:** Swift 5.9 language mode, доступный Swift 6.4 toolchain, SwiftPM, AppKit, MetalKit, CoreGraphics, IOKit, ServiceManagement, XCTest, shell и Python 3 для проверок упаковки.

---

## Статус и исходные решения

Пользователь поручил начать реализацию 6 ноября 2026 года. Объём: личное локальное использование без продаж, серверов, аналитики и сетевых функций. Исполняется рекомендуемый путь адаптации зафиксированного Snowhush.

Спецификация: [SeasonArt MVP](../specs/2026-11-06-seasonart-mvp-design.md). Контекст: [macOS и источники](../../research/2026-11-06-macos-context.md).

Основной сценарий первой проверки – снег. Дождь, листья и сакура сохраняются из основы и проверяются после него. Если нужен собственный движок, этот план сначала перерабатывается, не исполняется наполовину.

Все команды ниже выполняются из `/Users/itsnikoko/SeasonArt`, если не указано иное. Они относятся к будущему исполнению. Ожидаемые результаты команд не являются отчётом об уже выполненных проверках.

## Структура

```text
SeasonArt/
  Package.swift
  UPSTREAM.json
  LICENSE
  THIRD_PARTY.md
  README.md
  .gitignore
  Resources/Info.plist
  Sources/SeasonArt/
    main.swift
    AppDelegate.swift
    Preferences.swift
    WallpaperSelection.swift
    WallpaperController.swift
    OverlayWindow.swift
    ScreenSnow.swift
    WindowTracker.swift
    Renderer.swift
    SnowSimulation.swift
    SnowLayer.swift
    PowerMonitor.swift
    ScreenshotWatch.swift
    остальные macOS-файлы из зафиксированного снимка
  Tests/SeasonArtTests/
    PreferencesTests.swift
    SnowLayerTests.swift
    WallpaperSelectionTests.swift
  Tests/Packaging/test_local_bundle.py
  Scripts/
    import-upstream.sh
    build.sh
    sign.sh
    install.sh
    rollback.sh
  docs/verification/
    local-run.md
    artifacts/
```

`build/`, `.build/`, локальные резервные копии и измерения не коммитить. Пользовательские изображения в репозиторий не добавлять. До импорта не создавать пустые исходники, имитирующие готовое приложение.

## Зависимости и этапы

| Задача | Зависит от | Проверяемый результат |
|---|---|---|
| 1. Импорт основы | – | Зафиксированные исходники и provenance |
| 2. Независимое приложение без обновлений | 1 | SeasonArt собирается без Sparkle |
| 3. Подписанный локальный бандл | 2 | `.app` с собственным ID, запуск без установки |
| 4. Меню и независимые настройки | 3 | Четыре режима и сохранение настроек |
| 5. Физика и реальные окна | 4 | Основной сценарий снега и известные проблемные переходы |
| 6. Локальные обои | 4 | Выбор и установка существующего изображения |
| 7. Установка и возврат старой версии | 6 | Одна локальная копия, резервная версия |
| 8. Итоговая проверка | 7 | Записанная матрица поведения и измерения |

Исполнять последовательно. Отдельный запуск параллельных агентов не требуется для начала работы. Git-репозиторий и коммиты создаются при исполнении, документы в этой задаче не коммитились.

Уточнение при исполнении: автоматические проверки движка и базовые нативные сценарии Task 5 уже выполнены, полная ручная приёмка остаётся открытой. Установка Task 7 выполняется после Task 6, чтобы завершать ручные сценарии на стабильном установленном пути, не заменяя бандл работающей сборки. Критерии Task 5 этим не отменяются.

## Task 1: Импортировать зафиксированную macOS-основу

**Goal:** Получить macOS-исходники Snowhush ровно из `013f36782e5c6d017725aeb4b2173ae329bf0c6e` с сохранёнными авторством и лицензией.

**Files:**
- Create: `Scripts/import-upstream.sh`, `UPSTREAM.json`, `LICENSE`, `THIRD_PARTY.md`, `.gitignore`.
- Create: `Sources/SeasonArt/*.swift` из `Sources/Snowhush/*.swift` выбранного снимка.
- Create: `Resources/Info.plist` из выбранного снимка, до адаптации в Task 2.

**Acceptance Criteria:**
- [ ] Снимок совпадает с указанным SHA, не с текущим main.
- [ ] Импортированы только macOS-исходники. Windows, Rust, сайт и CI основы не добавлены.
- [ ] LICENSE совпадает с файлом снимка. Автор и ссылка сохранены в THIRD_PARTY.md.
- [ ] Исходники не собираются и не запускаются автоматически импортёром.

**Verify:** `python3 -c 'import json,pathlib; x=json.loads(pathlib.Path("UPSTREAM.json").read_text()); assert x["commit"]=="013f36782e5c6d017725aeb4b2173ae329bf0c6e"; assert pathlib.Path("Sources/SeasonArt/SnowSimulation.swift").is_file(); assert "PolyForm Noncommercial" in pathlib.Path("LICENSE").read_text(); print("upstream snapshot OK")'` печатает `upstream snapshot OK`.

**Steps:**

- [ ] Проверить, что целевые исходники ещё не существуют. Импортёр прекращает работу при существующем `Sources/SeasonArt`, а не перезаписывает локальные правки.
- [ ] Создать импортёр. Полное содержимое основного действия:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test ! -e Sources/SeasonArt
SEASONART_UPSTREAM_DIR="$(mktemp -d)"
trap 'rm -rf "$SEASONART_UPSTREAM_DIR"' EXIT
SEASONART_UPSTREAM_SHA=013f36782e5c6d017725aeb4b2173ae329bf0c6e
git -C "$SEASONART_UPSTREAM_DIR" init --quiet
git -C "$SEASONART_UPSTREAM_DIR" fetch --quiet --depth=1 \
  https://github.com/mbezruchko/Snowhush.git "$SEASONART_UPSTREAM_SHA"
test "$(git -C "$SEASONART_UPSTREAM_DIR" rev-parse FETCH_HEAD)" = "$SEASONART_UPSTREAM_SHA"
git -C "$SEASONART_UPSTREAM_DIR" archive FETCH_HEAD Sources/Snowhush Resources/Info.plist LICENSE \
  | tar -xf - -C "$SEASONART_UPSTREAM_DIR"
mkdir -p Sources Resources
ditto "$SEASONART_UPSTREAM_DIR/Sources/Snowhush" Sources/SeasonArt
cp "$SEASONART_UPSTREAM_DIR/Resources/Info.plist" Resources/Info.plist
cp "$SEASONART_UPSTREAM_DIR/LICENSE" LICENSE
printf '%s\n' '{"repository":"https://github.com/mbezruchko/Snowhush","commit":"013f36782e5c6d017725aeb4b2173ae329bf0c6e","license":"PolyForm-Noncommercial-1.0.0","importedSubtree":"Sources/Snowhush"}' > UPSTREAM.json
```

- [ ] В THIRD_PARTY.md записать автора Mykhailo Bezruchko, исходный репозиторий, SHA, личные изменения и путь LICENSE. Включить этот файл в будущий бандл. Если позже копируются фрагменты Oasis/Speakey, добавить их реальные notices в том же коммите.
- [ ] Запустить импортёр один раз. Повторный запуск должен завершаться до изменения файлов.
- [ ] Выполнить Verify. Инициализировать отдельный Git в SeasonArt, если его ещё нет, сохранить импорт отдельным коммитом `chore: import pinned macOS effect engine`.

## Task 2: Отделить SeasonArt и удалить обновления

**Goal:** Собрать отдельный исполняемый таргет SeasonArt без Sparkle, внешнего appcast и автоматического перемещения приложения.

**Files:**
- Create: `Package.swift`.
- Modify: `Resources/Info.plist`, `Sources/SeasonArt/AppDelegate.swift`, `Sources/SeasonArt/WelcomeWindow.swift`.
- Remove: `Sources/SeasonArt/AppMover.swift` после удаления вызова.
- Create: `Tests/Packaging/test_local_bundle.py`, первоначально с проверкой исходной конфигурации.

**Acceptance Criteria:**
- [ ] Имя и executable SeasonArt, bundle ID `dev.nikoko.SeasonArt`, версия `0.1.0`, build `1`.
- [ ] В Package.swift отсутствуют сторонние зависимости.
- [ ] Удалены импорт Sparkle, протокол SPUStandardUserDriverDelegate, updater и его запуск, пункт проверки обновлений, sponsor-action и SU-ключи plist.
- [ ] AppMover не переносит приложение и не снимает quarantine. Запуск из build остаётся запуском из build.
- [ ] Чужие copyright и provenance сохранены, пользовательские подписи интерфейса используют SeasonArt.

**Verify:** `swift build -c release` заканчивается `Build complete!`. `python3 -m unittest discover -s Tests/Packaging -v` заканчивается `OK`.

**Steps:**

- [ ] Сначала написать проверку конфигурации. Минимальный тест, который падает на импортированной конфигурации:

```python
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class LocalConfigurationTests(unittest.TestCase):
    def test_local_identity_and_no_update_feed(self):
        """Локальный бандл отделён от оригинала и не содержит ленту обновлений."""
        with (ROOT / "Resources/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], "dev.nikoko.SeasonArt")
        self.assertEqual(info["CFBundleExecutable"], "SeasonArt")
        self.assertFalse(any(key.startswith("SU") for key in info))
        manifest = (ROOT / "Package.swift").read_text()
        self.assertNotIn("Sparkle", manifest)
        self.assertNotIn(".package(", manifest)
```

- [ ] Запустить unittest, сохранить ожидаемое падение по идентичности.
- [ ] Задать манифест:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SeasonArt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SeasonArt", targets: ["SeasonArt"])],
    targets: [.executableTarget(name: "SeasonArt", path: "Sources/SeasonArt")]
)
```

- [ ] Изменить plist через Python plistlib: display/name/executable SeasonArt, ID `dev.nikoko.SeasonArt`, version `0.1.0`, build `1`, `LSUIElement=true`, minimum `14.0`. Удалить все SU-ключи и CFBundleIconFile, поскольку оригинальная иконка не импортируется. Сохранить исходное уведомление copyright.
- [ ] В AppDelegate удалить `import Sparkle`, conformance SPUStandardUserDriverDelegate, поле updater, его инициализацию, computed property supportsGentleScheduledUpdateReminders и две строки создания/настройки пункта updates. Удалить Support Snowhush и метод openSponsors. Удалить блок `if AppMover.moveIfNeeded()` и сам AppMover.swift. Эти удаления локальны и не меняют симуляцию.
- [ ] Перевести видимые приветствие и выход на SeasonArt. Не заменять автоматически имя автора, строки LICENSE или ссылку provenance. Для статуса оставить SF Symbols режима.
- [ ] Проверить компиляцию и упаковочные тесты. Не устанавливать приложение. Коммит `chore: isolate SeasonArt and remove online updates`.

## Task 3: Подготовить локальный подписанный бандл

**Goal:** Получить `build/SeasonArt.app` для этого arm64 Mac, строго проверить подпись и запустить его без изменения установленной копии.

**Files:**
- Create: `Scripts/sign.sh`, `Scripts/build.sh`.
- Modify: `Tests/Packaging/test_local_bundle.py`.
- Create: `docs/verification/local-run.md` с данными первой сборки.

**Acceptance Criteria:**
- [ ] Сборка не обращается к Sparkle и не содержит его framework.
- [ ] Identity задаётся через SEASONART_SIGN_ID и разрешается среди валидных code-signing identities.
- [ ] Отсутствующая identity и значение `-` завершают сборку до замены готового бандла.
- [ ] `codesign --verify --deep --strict` проходит, ID и executable правильные.
- [ ] Запуск показывает SeasonArt в строке меню, не завершает Oasis, Speakey или Snowhush.

**Verify:** `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh` создаёт проверенный `.app`, если такая identity есть. Иначе использовать фактическое имя из `security find-identity -v -p codesigning`. `codesign --verify --deep --strict build/SeasonArt.app` возвращает 0.

**Steps:**

- [ ] Дополнить packaging-тест проверкой построенного бандла при наличии `build/SeasonArt.app`: нет `Contents/Frameworks/Sparkle.framework`, executable существует и исполняемый, скопированы LICENSE и THIRD_PARTY.md. До сборки этот набор запускать с явным флагом `SEASONART_REQUIRE_BUNDLE=1`, чтобы отсутствие артефакта означало падение, а не пропуск.
- [ ] Реализовать sign.sh с аргументом пути. Получать список через `security find-identity -v -p codesigning` внутри процесса, находить точное имя или SHA из SEASONART_SIGN_ID, требовать ровно одно совпадение. Проверять identity отдельным режимом `--check-identity` до компиляции. Не создавать сертификаты и не менять trust settings автоматически. Ключ остаётся в Keychain.
- [ ] В build.sh выполнить preflight, затем `swift build -c release --arch arm64`. Получить binary directory через `swift build -c release --arch arm64 --show-bin-path`. Создать staging bundle в `build/.SeasonArt-staging.app`, скопировать executable, plist, LICENSE и THIRD_PARTY.md. В этой версии нет frameworks для копирования.
- [ ] Подписать staging, проверить подпись. Только после этого заменить `build/SeasonArt.app`. При любой ошибке удалить staging, сохранить старый готовый бандл. Команда codesign внутри sign.sh:

```bash
codesign --force --sign "$SEASONART_RESOLVED_IDENTITY" "$SEASONART_BUNDLE_PATH"
codesign --verify --deep --strict "$SEASONART_BUNDLE_PATH"
```

- [ ] Запустить packaging-тесты с требованием артефакта. Открыть build/SeasonArt.app командой `open build/SeasonArt.app`, записать результат и выйти через меню. Эта проверка не является установкой.
- [ ] Коммит `build: add stable local signing and app bundle`.

## Task 4: Настроить меню и независимое сохранение состояния

**Goal:** Управлять режимами SeasonArt и сохранять настройки, не читая и не меняя домен оригинального Snowhush.

**Files:**
- Modify: `Package.swift` для добавления testTarget только после создания его исходников.
- Modify: `Sources/SeasonArt/Preferences.swift`, `Sources/SeasonArt/AppDelegate.swift`, `Sources/SeasonArt/WelcomeWindow.swift`.
- Create: `Tests/SeasonArtTests/PreferencesTests.swift`.

**Acceptance Criteria:**
- [ ] Меню содержит четыре режима, интенсивность, накопление, таяние, очистку, fullscreen, скриншоты, автозапуск и выход.
- [ ] Названия настроек соответствуют режиму, дождь не показывает управление сугробами.
- [ ] Автозапуск выключен до явного включения пользователем.
- [ ] Режим и интенсивность восстанавливаются после перезапуска. Исходный домен не изменён.
- [ ] Halloween не включается автоматически по дате и не появляется в меню MVP.
- [ ] Ошибка автозапуска видна пользователю через NSAlert.

**Verify:** `swift test --filter PreferencesTests` проходит, затем ручной перезапуск восстанавливает Rain/Light, выбранные через меню.

**Steps:**

- [ ] Создать тест независимости доменов:

```swift
import Foundation
import XCTest
@testable import SeasonArt

final class PreferencesTests: XCTestCase {
    func testSeparateDomainsAndRelaunch() throws {
        let firstName = "SeasonArtTests.first.\(UUID().uuidString)"
        let secondName = "SeasonArtTests.second.\(UUID().uuidString)"
        let first = try XCTUnwrap(UserDefaults(suiteName: firstName))
        let second = try XCTUnwrap(UserDefaults(suiteName: secondName))
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
            Preferences.configure(defaults: .standard)
        }
        Preferences.configure(defaults: first)
        Preferences.registerDefaults()
        Preferences.mode = .rain
        Preferences.snowfall = .light
        Preferences.configure(defaults: second)
        Preferences.registerDefaults()
        XCTAssertEqual(Preferences.mode, .snow, "Чужой домен не наследует выбранный режим")
        Preferences.configure(defaults: try XCTUnwrap(UserDefaults(suiteName: firstName)))
        XCTAssertEqual(Preferences.mode, .rain, "Режим сохраняется после повторного открытия домена")
        XCTAssertEqual(Preferences.snowfall, .light)
    }
}
```

- [ ] После создания файла теста добавить `.testTarget(name: "SeasonArtTests", dependencies: ["SeasonArt"])` в targets Package.swift. Запустить тест до изменения Preferences, получить ошибку отсутствия configure. В Preferences заменить неизменяемое defaults на private static var и добавить `static func configure(defaults: UserDefaults) { self.defaults = defaults }`. В production оставить .standard, домен определяется бандлом.
- [ ] Сохранить Mode и методы chooseMode/switchMode основы. Перевести видимые настройки на русский. Скрыть Halloween-пункт, удалить его timer и датозависимую активацию. Метод refreshHalloween заменить установкой halloween=false для текущих сцен, чтобы существующие вызовы не включали сезонную добавку.
- [ ] Оставить регистрацию SMAppService только в обработчике пункта меню. При ошибке показать NSAlert с localizedDescription. Не включать автозапуск при старте или установке.
- [ ] В About указать SeasonArt и автора основы. В бандле сохранить полный LICENSE и THIRD_PARTY.md.
- [ ] Выполнить unit-проверку и ручной сценарий. Коммит `feat: add local seasonal controls and isolated preferences`.

## Task 5: Проверить снег на реальных окнах и сохранить исправления

**Goal:** Подтвердить накопление и стряхивание на настоящих окнах, пропуск кликов и отсутствие оставшихся слоёв при переходах.

**Files:**
- Create: `Tests/SeasonArtTests/SnowLayerTests.swift`.
- Modify only if reproduced: `Sources/SeasonArt/WindowTracker.swift`, `Sources/SeasonArt/ScreenSnow.swift`, `Sources/SeasonArt/DockOverlay.swift`, `Sources/SeasonArt/SnowLayer.swift`.
- Modify: `docs/verification/local-run.md`.

**Acceptance Criteria:**
- [ ] Снег на трёх окнах с перекрытием не рисует скрытый край поверх переднего окна.
- [ ] Перетаскивание, resize, сворачивание и закрытие убирают опору без оставшегося контура.
- [ ] Курсор смахивает снег, клики и печать в нижележащем редакторе работают.
- [ ] Mission Control и захват отдельного окна не выбирают слой SeasonArt вместо рабочего приложения.
- [ ] Нет неподтверждённого заявления о проверке второго физического монитора.

**Verify:** `swift test --filter SnowLayerTests` проходит. Видео или последовательность снимков покрывает каждый перечисленный сценарий, результаты записаны в local-run.md.

**Steps:**

- [ ] Зафиксировать инвариант границ колонок для собственного дальнейшего исправления:

```swift
import XCTest
@testable import SeasonArt

final class SnowLayerTests: XCTestCase {
    func testColumnBoundsDoNotWrapBetweenSurfaces() {
        let layer = SnowLayer(origin: SIMD2(100, 200), columns: 4,
                              columnWidth: 10, depth: 20,
                              opensAtEdges: true, phases: (0, 0))
        XCTAssertNil(layer.index(at: 99), "Снег слева от опоры не попадает в последнюю колонку")
        XCTAssertEqual(layer.index(at: 100), 0)
        XCTAssertEqual(layer.index(at: 139.9), 3)
        XCTAssertNil(layer.index(at: 140), "Соседняя опора не разделяет крайнюю колонку")
    }
}
```

- [ ] Этот тест фиксирует существующий важный инвариант и может сразу пройти. Не выдавать его за red-green нового кода. Для каждого реально найденного дефекта сначала добавить его воспроизведение на входных данных или в контролируемой сцене, получить падение, затем исправить.
- [ ] Запустить Snow/Steady на текущем экране. Записать движение, resize, сворачивание, закрытие, перекрытие и курсор. Снимки не заменяют проверку реакции на движение.
- [ ] Отдельно проверить Cmd+Shift+4, Space и выбор окна. Не считать `ignoresMouseEvents=true` достаточным доказательством поведения инструмента скриншотов.
- [ ] Проверить Mission Control и fullscreen. При дефекте использовать соответствующие треды из контекста как описание проблемы. Не подмешивать текущий main и не применять открытый PR без чтения diff к зафиксированной базе.
- [ ] При доступном втором экране перенести окно и Dock, отключить монитор. Проверить отсутствие старого слоя и нового двойного. Без оборудования записать `не проверено на физическом втором экране`.
- [ ] Сохранить необходимые исправления коммитом `fix: stabilize local window and display interactions`, если изменения были. Иначе сохранить только свидетельства проверки отдельным docs-коммитом.

## Task 6: Добавить выбор локальных обоев

**Goal:** Выбрать локальное изображение и применить его к подключённым экранам по явному действию, сохраняя фон при отмене и ошибке.

**Files:**
- Create: `Sources/SeasonArt/WallpaperSelection.swift`, `Sources/SeasonArt/WallpaperController.swift`.
- Create: `Tests/SeasonArtTests/WallpaperSelectionTests.swift`.
- Modify: `Sources/SeasonArt/AppDelegate.swift`.

**Acceptance Criteria:**
- [ ] Диалог принимает один локальный файл изображения. Отмена не вызывает установку.
- [ ] Невалидный файл отклоняется до вызова NSWorkspace.
- [ ] Установка вызывается отдельно для каждого текущего экрана.
- [ ] Частичная ошибка показывает причину, приложение не завершается.
- [ ] Перезапуск и смена эффекта не меняют обои автоматически.

**Verify:** `swift test --filter WallpaperSelectionTests` проходит. Ручные сценарии валидного файла, отмены и невалидного файла записаны без добавления личного изображения в Git.

**Steps:**

- [ ] Написать тест на невалидный и отсутствующий файл, используя временный каталог. До появления валидатора ожидается ошибка компиляции об отсутствующем типе. Тесты не меняют настоящие обои:

```swift
import Foundation
import XCTest
@testable import SeasonArt

final class WallpaperSelectionTests: XCTestCase {
    func testMissingAndInvalidFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.png")
        XCTAssertThrowsError(try WallpaperSelection.validate(missing)) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .missingFile)
        }
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("не изображение".utf8).write(to: invalid)
        XCTAssertThrowsError(try WallpaperSelection.validate(invalid)) {
            XCTAssertEqual($0 as? WallpaperSelectionError, .invalidImage)
        }
    }
}
```
- [ ] Реализовать в WallpaperSelection.swift полный валидатор:

```swift
import AppKit

enum WallpaperSelectionError: Error, Equatable {
    case missingFile
    case invalidImage
}

enum WallpaperSelection {
    static func validate(_ url: URL) throws -> URL {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw WallpaperSelectionError.missingFile
        }
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw WallpaperSelectionError.invalidImage
        }
        return url
    }
}
```

- [ ] Добавить успешный тест с маленьким PNG, созданным программно внутри временного каталога. Тестировать результат validate, не повторять его внутренние условия.
- [ ] WallpaperController выполняется на main thread. Состав обработчика:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WallpaperController {
    func chooseAndApply() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let validURL = try WallpaperSelection.validate(url)
            var failures: [String] = []
            for screen in NSScreen.screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(validURL, for: screen, options: [:])
                } catch {
                    failures.append("\(screen.localizedName): \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty { showError(failures.joined(separator: "\n")) }
        } catch {
            showError("Не удалось открыть изображение: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Не удалось установить обои"
        alert.informativeText = message
        alert.runModal()
    }
}
```

- [ ] В AppDelegate добавить сохраняемый контроллер и selector пункта «Выбрать обои…». Вызов main actor согласовать с существующим языковым режимом, не добавлять неподтверждённые `@unchecked Sendable` для подавления диагностики.
- [ ] Выполнить unit-проверки и ручной сценарий. Не использовать графику KoiArt как поставляемый ресурс. Коммит `feat: choose local desktop wallpapers`.

## Task 7: Установить одну локальную копию с возвратом

**Goal:** Обновлять только `~/Applications/SeasonArt.app`, сохраняя прежний бандл и не затрагивая другие приложения.

**Files:**
- Create: `Scripts/install.sh`, `Scripts/rollback.sh`.
- Modify: `Tests/Packaging/test_local_bundle.py`, `README.md`.

**Acceptance Criteria:**
- [ ] Install проверяет новую сборку до остановки установленного SeasonArt.
- [ ] Завершение процессов определяется bundle ID SeasonArt, не шаблоном Snow, Art или Swift.
- [ ] Старая версия сохраняется в `build/backups/<MSK-stamp>/SeasonArt.app`.
- [ ] Ошибка копирования возвращает старую версию. Rollback не удаляет UserDefaults.
- [ ] Подпись установленного executable совпадает с подготовленной сборкой по SHA-256.
- [ ] Установка не включает автозапуск.

**Verify:** `codesign --verify --deep --strict "$HOME/Applications/SeasonArt.app"` возвращает 0. `shasum -a 256 build/SeasonArt.app/Contents/MacOS/SeasonArt "$HOME/Applications/SeasonArt.app/Contents/MacOS/SeasonArt"` показывает одинаковые значения. Повторная установка и возврат версии сохраняют выбранный режим.

**Steps:**

- [ ] В install.sh установить `set -euo pipefail`, проверить подпись и bundle ID исходного бандла. Целевой каталог фиксировать как `$HOME/Applications/SeasonArt.app`. Произвольный путь из аргумента не принимать.
- [ ] Скопировать новую версию в соседний staging-каталог до завершения текущего процесса. Резервной версии дать timestamp через `TZ=Europe/Moscow date +%Y%m%d-%H%M%S-MSK`.
- [ ] Определить только NSRunningApplication с bundleIdentifier `dev.nikoko.SeasonArt`, запросить terminate, дождаться выхода не дольше пяти секунд. Если приложение не вышло, прекратить установку и сохранить старую копию. Не делать killall по имени и не завершать другие продукты.
- [ ] После выхода атомарно переименовать старую копию в backup, staging в целевой путь. Trap на ошибку восстанавливает backup. Проверить подпись установленной копии до запуска.
- [ ] Зарегистрировать только установленный бандл в LaunchServices. Не удалять домены defaults и не менять TCC. Запустить установленную копию через `open "$HOME/Applications/SeasonArt.app"`.
- [ ] Rollback принимает конкретный существующий backup внутри `build/backups`, проверяет подпись и bundle ID и использует тот же порядок замены. Текущую версию сохраняет как новый backup.
- [ ] Проверки файлового обмена запускать на временном дереве без production-процессов. Живую установку выполнить отдельно, убедиться, что Oasis/Speakey остались запущены, а режим SeasonArt сохранился.
- [ ] Коммит `build: add local install and rollback`.

## Task 8: Завершить локальную проверку и записать ограничения

**Goal:** Зафиксировать поведение установленного SeasonArt, наблюдаемую сетевую активность и нагрузку на этом Mac с воспроизводимыми командами и артефактами.

**Files:**
- Modify: `docs/verification/local-run.md`, `README.md`.
- Create: `docs/verification/artifacts/` с локальными логами и снимками, не включаемыми в Git.
- Modify production files only when a recorded failure requires a fix.

**Acceptance Criteria:**
- [ ] Сборка, unit-проверки, packaging-проверки и подпись установленной версии проходят на одном зафиксированном наборе исходников.
- [ ] Матрица включает снег, остальные режимы, окна, курсор, fullscreen, Spaces, Mission Control, скриншот, сон/пробуждение, обои и выход.
- [ ] Нагрузка измерена после прогрева, записаны модель Mac, macOS, SHA, число экранов и режим.
- [ ] Цели Snow/Steady на одном экране: средний CPU за минуту не выше 15% одного ядра, RSS не выше 200 МиБ.
- [ ] За пять минут в nettop не наблюдаются исходящие соединения SeasonArt, Sparkle отсутствует в бандле.
- [ ] Непроверенные физические сценарии явно отмечены.

**Verify:** `swift test`, `SEASONART_REQUIRE_BUNDLE=1 python3 -m unittest discover -s Tests/Packaging -v`, `codesign --verify --deep --strict "$HOME/Applications/SeasonArt.app"` возвращают 0. local-run.md содержит результаты каждого пункта, а не только названия команд.

**Steps:**

- [ ] Выполнить проверки на неизменяемом наборе исходников. После любого исправления повторить относящуюся к нему проверку и обновить записанный SHA.
- [ ] Зафиксировать окружение через `sw_vers`, `system_profiler SPHardwareDataType`, `git rev-parse HEAD`. В публикуемый документ не переносить serial number и hardware UUID.
- [ ] После прогрева получить точный PID установленной копии по bundle ID. Для минутного замера 12 раз с интервалом пять секунд записать `ps -p "$SEASONART_PID" -o pid=,%cpu=,rss=`. RSS выводится в КиБ, для МиБ разделить на 1024. Средний CPU считать по записанным значениям. Не считать единичный замер доказательством устойчивой нагрузки.
- [ ] В отдельном процессе записать пять минут наблюдения `nettop -P -L 300 -p "$SEASONART_PID"` с переключением четырёх режимов. Указать, что это наблюдение ограниченного прогона, а не доказательство отсутствия всех возможных попыток в будущем.
- [ ] Выполнить матрицу спецификации. Для визуальной проверки сохранять видео/скрины с отсутствием лишнего фокуса и оставшихся слоёв. Временно выбранные обои после проверки вернуть вручную по желанию пользователя, его изображения не добавлять в Git.
- [ ] При превышении нагрузки сначала измерить текущий frame rate и число частиц. Уменьшать эти параметры с повторным замером, не объявлять заранее необходимость переписывания на другой движок.
- [ ] Записать команды локальной сборки, обновления и возврата в README. Итоговый docs-коммит `docs: record local SeasonArt acceptance`.

## Ожидаемый объём

При выбранной адаптации ориентир – 24–48 часов на независимую сборку и основной снег, 40–80 часов на весь описанный локальный MVP с обоями, установкой и проверкой. Это предварительная оценка работы с готовой основой. Не включает новый движок, новые эффекты, исправление каждой особенности macOS или недоступное для проверки оборудование.

## Самопроверка плана

Перед передачей проверить соответствие задач спецификации, определение новых типов до их использования, отсутствие ссылок на отсутствующие исходники, отсутствие продажи и серверных задач. Сохранить `2026-11-06-seasonart-mvp.md.tasks.json` рядом с планом: полное описание каждой задачи, критерии, Verify, зависимости и status=pending. Чекбоксы реализации остаются пустыми, пока соответствующая работа не выполнена и не проверена.
