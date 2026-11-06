# Winter scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development or superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Добавить снежные шары, сборку снеговика и один проход снегоуборщика по настоящей полке Dock.

**Architecture:** Чистая WinterScene моделирует игрушки, AppKit-панели рисуют их и принимают только собственный drag. Контроллер использует существующие WindowUpdate и узкие операции SnowSimulation для высоты снега и отвала. Полноэкранный overlay остаётся прозрачным для кликов.

**Tech Stack:** Swift 5.9+, AppKit, CoreGraphics, существующие MetalKit/SnowSimulation, XCTest, Python packaging tests. Новых package dependencies нет.

Спека: ../specs/2026-11-06-seasonart-winter-scenes-design.md. Пользователь явно разрешил реализацию. Рабочий каталог: /Users/itsnikoko/SeasonArt-worktrees/winter-scenes, ветка feat/winter-scenes. Нативные задачи в этой среде недоступны, источником статусов служит соседний tasks.json.

## Общие контракты

WinterBallSize.small/medium/large имеют radius 14/21/28. WinterObject хранит UUID, sizes снизу вверх, center нижнего шара, velocity, support CGWindowID?, parked/isDragged, frame и isSnowman. WinterScene имеет init(width:height:), create(_:at:), beginDragging(_:at:), drag(_:to:dt:), endDragging(_:), updateWindows(_:), step(dt:), resize(width:height:), shoveObjects(in:by:), removeAll(), objects и isMoving. surfaceHeight(CGWindowID?,CGFloat) возвращает абсолютную Y поверхности снега.

WinterObjectWindow принимает WinterObject и screenFrame, обновляется display(object:screenFrame:), передаёт dragBegan/dragged/dragEnded с глобальной координатой указателя. WinterPlowWindow рисует машину и ignoresMouseEvents=true. Контроллер переводит глобальную координату в локальные пункты экрана.

---

## Task 1: Модель шаров, опор и снеговика

**Goal:** Модель шаров, опор и снеговика.

**Files:**
- `Sources/SeasonArt/WinterScene.swift`
- `Tests/SeasonArtTests/WinterSceneTests.swift`

**Acceptance Criteria:**
- [ ] Падение выбирает верхнюю видимую опору и не проходит через неё при ограниченном dt.
- [ ] Опора переносит объект, удаление освобождает его, parked/elsewhere скрывают до возврата.
- [ ] Перетаскивание сохраняет смещение захвата и ограничивает скорость броска 900 pt/s.
- [ ] Большой, средний и маленький шар объединяются в один снеговик в правильном порядке.
- [ ] Лимит 12, очистка и сдвиг машиной не оставляют дубликатов.

**Verify:** `swift test --filter WinterSceneTests` заканчивается успешными тестами.

**Steps:**

Сначала тестировать падение на WindowSurface и тройную сборку, получить RED из-за отсутствующего WinterScene. Реализовать чистую модель и дополнять тесты перекрытием, удалением, парковкой, resize, drag и лимитом.

```swift
let scene = WinterScene(width: 800, height: 600)
let id = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 200, y: 100)))
for _ in 0..<120 { scene.step(dt: 1.0 / 60) }
XCTAssertEqual(scene.objects.first { $0.id == id }?.frame.minY ?? -1, 0, accuracy: 0.1)
```

После GREEN выполнить полный swift test и сохранить только модель с тестами коммитом feat: add winter object physics and snowman assembly.

```json:metadata
{
  "files": [
    "Sources/SeasonArt/WinterScene.swift",
    "Tests/SeasonArtTests/WinterSceneTests.swift"
  ],
  "verifyCommand": "swift test --filter WinterSceneTests",
  "acceptanceCriteria": [
    "Падение выбирает верхнюю видимую опору и не проходит через неё при ограниченном dt.",
    "Опора переносит объект, удаление освобождает его, parked/elsewhere скрывают до возврата.",
    "Перетаскивание сохраняет смещение захвата и ограничивает скорость броска 900 pt/s.",
    "Большой, средний и маленький шар объединяются в один снеговик в правильном порядке.",
    "Лимит 12, очистка и сдвиг машиной не оставляют дубликатов."
  ]
}
```

## Task 2: AppKit-окна и собственная графика игрушек

**Goal:** AppKit-окна и собственная графика игрушек.

**Files:**
- `Sources/SeasonArt/WinterObjectWindow.swift`
- `Sources/SeasonArt/WinterObjectView.swift`
- `Sources/SeasonArt/WinterPlowWindow.swift`
- `Tests/SeasonArtTests/WinterObjectWindowTests.swift`

**Acceptance Criteria:**
- [ ] Снежный шар и собранный снеговик рисуются собственными AppKit-путями.
- [ ] Borderless nonactivating панели не забирают клавиатуру, их размер совпадает с рамкой объекта.
- [ ] События drag передают глобальную координату указателя, завершение захвата не теряется.
- [ ] Окно машины пропускает мышь, окна поддерживают sharingType и явное скрытие.

**Verify:** `swift test --filter WinterObjectWindowTests` заканчивается успешными тестами.

**Steps:**

До реализации проверить размер рамки, невозможность стать key/main и режимы ignoresMouseEvents/sharingType. Инициализация AppKit в тесте начинается с NSApplication.shared.

```swift
_ = NSApplication.shared
XCTAssertFalse(window.canBecomeKey)
XCTAssertFalse(window.canBecomeMain)
XCTAssertFalse(window.ignoresMouseEvents)
```

Рисование использует NSBezierPath, NSGradient и векторные элементы шарфа, лица и отвала. Ресурсы KoiArt не копируются. Сохранить окна и их тесты отдельным коммитом feat: draw draggable winter toys.

```json:metadata
{
  "files": [
    "Sources/SeasonArt/WinterObjectWindow.swift",
    "Sources/SeasonArt/WinterObjectView.swift",
    "Sources/SeasonArt/WinterPlowWindow.swift",
    "Tests/SeasonArtTests/WinterObjectWindowTests.swift"
  ],
  "verifyCommand": "swift test --filter WinterObjectWindowTests",
  "acceptanceCriteria": [
    "Снежный шар и собранный снеговик рисуются собственными AppKit-путями.",
    "Borderless nonactivating панели не забирают клавиатуру, их размер совпадает с рамкой объекта.",
    "События drag передают глобальную координату указателя, завершение захвата не теряется.",
    "Окно машины пропускает мышь, окна поддерживают sharingType и явное скрытие."
  ]
}
```

## Task 3: Уборка конкретной полки Dock

**Goal:** Уборка конкретной полки Dock.

**Files:**
- `Sources/SeasonArt/WinterPlow.swift`
- `Sources/SeasonArt/SnowSimulation.swift`
- `Tests/SeasonArtTests/WinterPlowTests.swift`

**Acceptance Criteria:**
- [ ] Маршрут машины существует только при видимой горизонтальной WindowSurface.isDock.
- [ ] Повторный запуск не создаёт вторую машину.
- [ ] Операция отвала меняет только пройденные колонки конкретной полки, дальние окна и ground не очищаются.
- [ ] Перемещённая масса сохраняется в куче и выброшенных частицах, игрушки на пути сдвигаются.

**Verify:** `swift test --filter WinterPlowTests` заканчивается успешными тестами.

**Steps:**

Тесты сначала создают SnowSimulation со своей WindowSurface(isDock:true), осаждают ScatterPiece и читают writeLayers. Проверяют ненулевую массу до прохода, изменение пройденного диапазона и неизменность другого слоя.

```swift
let dock = WindowSurface(id: 42, frame: CGRect(x: 100, y: 0, width: 500, height: 60), blockers: [], cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: true)
simulation.updateWindows([dock], interval: 0.1)
```

Ввести SnowSimulation.winterSurfaceY(at:on:) и plowDock(id:fromX:toX:). Шаг машины возвращает пройденный диапазон, рендер и модель используют один маршрут. Глобальный blowAway не вызывать. Коммит feat: plow snow along the Dock shelf.

```json:metadata
{
  "files": [
    "Sources/SeasonArt/WinterPlow.swift",
    "Sources/SeasonArt/SnowSimulation.swift",
    "Tests/SeasonArtTests/WinterPlowTests.swift"
  ],
  "verifyCommand": "swift test --filter WinterPlowTests",
  "acceptanceCriteria": [
    "Маршрут машины существует только при видимой горизонтальной WindowSurface.isDock.",
    "Повторный запуск не создаёт вторую машину.",
    "Операция отвала меняет только пройденные колонки конкретной полки, дальние окна и ground не очищаются.",
    "Перемещённая масса сохраняется в куче и выброшенных частицах, игрушки на пути сдвигаются."
  ]
}
```

## Task 4: Контроллер сцены и команды меню

**Goal:** Контроллер сцены и команды меню.

**Files:**
- `Sources/SeasonArt/WinterSceneController.swift`
- `Sources/SeasonArt/ScreenSnow.swift`
- `Sources/SeasonArt/AppDelegate.swift`
- `Tests/SeasonArtTests/WinterSceneControllerTests.swift`

**Acceptance Criteria:**
- [ ] Команды создают размер на экране указателя, видны только в Snow и отключаются при лимите.
- [ ] Контроллер получает существующие WindowUpdate, отдельного полного WindowTracker нет.
- [ ] Неподвижные игрушки не перерисовываются непрерывно, движение и машина обновляются ограниченным таймером.
- [ ] Пауза, смена режима, ScreenshotWatch и закрытие экрана скрывают/закрывают все окна.
- [ ] Без подходящего Dock команда уборки отключена и объясняет причину.

**Verify:** `swift test` заканчивается успешными тестами.

**Steps:**

Связать модель с окнами по UUID, callbacks захвата с beginDragging/drag/endDragging, surfaceHeight с узким API SnowSimulation. Таймер нужен для физики игрушек, список окон поступает из renderer.windowSurfaces. Состояние режима, паузы и aside имеет приоритет над показом окон.

```swift
if let update { winter.updateWindows(update) }
winter.showsInScreenshots = Preferences.showInScreenshots
```

В AppDelegate добавить «Зимние игрушки», три размера, «Убрать зимние игрушки» и «Убрать снег трактором». Переиспользовать путь установленного приложения и штатные build/install. Коммит feat: integrate winter scenes with seasonal controls.

```json:metadata
{
  "files": [
    "Sources/SeasonArt/WinterSceneController.swift",
    "Sources/SeasonArt/ScreenSnow.swift",
    "Sources/SeasonArt/AppDelegate.swift",
    "Tests/SeasonArtTests/WinterSceneControllerTests.swift"
  ],
  "verifyCommand": "swift test",
  "acceptanceCriteria": [
    "Команды создают размер на экране указателя, видны только в Snow и отключаются при лимите.",
    "Контроллер получает существующие WindowUpdate, отдельного полного WindowTracker нет.",
    "Неподвижные игрушки не перерисовываются непрерывно, движение и машина обновляются ограниченным таймером.",
    "Пауза, смена режима, ScreenshotWatch и закрытие экрана скрывают/закрывают все окна.",
    "Без подходящего Dock команда уборки отключена и объясняет причину."
  ]
}
```

## Task 5: Проверка, установка и локальная приёмка

**Goal:** Проверка, установка и локальная приёмка.

**Files:**
- `docs/verification/winter-scenes.md`
- `README.md`
- `docs/superpowers/plans/2026-11-06-seasonart-winter-scenes.md.tasks.json`

**Acceptance Criteria:**
- [ ] Полный Swift-набор, 19 обязательных packaging-проверок и строгая подпись проходят.
- [ ] Подписанная версия установлена с резервной копией и совпадает со сборкой по SHA-256.
- [ ] Нативные кадры и журнал подтверждают drag шара, сборку/перенос снеговика, click-through вне рамок, проход машины либо документированную недоступность Dock.
- [ ] Проверены смена режима, очистка, выход, Mission Control и системный выбор окна.
- [ ] Записаны CPU/RSS без объектов и с 12 неподвижными игрушками. Сон исключён пользователем, второй монитор недоступен.

**Verify:** `swift test && SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v` заканчивается успешными тестами.

**Steps:**

Не редактировать Swift во время компиляции и не запускать параллельные компиляторы. После тестов выполнить:

```bash
SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh
bash Scripts/install.sh
codesign --verify --deep --strict "$HOME/Applications/SeasonArt.app"
```

При интерактивном прогоне сначала подтвердить разблокированный сеанс и видимость собственной сцены. Выполнять действия последовательно, снимать кадр после завершения действия. Личные снимки и программы хранить только в ignored docs/verification/artifacts. Перед завершением восстановить временно изменённые настройки и закрыть тестовые окна. Сохранить отчёт docs: record winter scenes verification.

```json:metadata
{
  "files": [
    "docs/verification/winter-scenes.md",
    "README.md",
    "docs/superpowers/plans/2026-11-06-seasonart-winter-scenes.md.tasks.json"
  ],
  "verifyCommand": "swift test && SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v",
  "acceptanceCriteria": [
    "Полный Swift-набор, 19 обязательных packaging-проверок и строгая подпись проходят.",
    "Подписанная версия установлена с резервной копией и совпадает со сборкой по SHA-256.",
    "Нативные кадры и журнал подтверждают drag шара, сборку/перенос снеговика, click-through вне рамок, проход машины либо документированную недоступность Dock.",
    "Проверены смена режима, очистка, выход, Mission Control и системный выбор окна.",
    "Записаны CPU/RSS без объектов и с 12 неподвижными игрушками. Сон исключён пользователем, второй монитор недоступен."
  ]
}
```
