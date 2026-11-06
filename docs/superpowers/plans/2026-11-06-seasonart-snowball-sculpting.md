# Snowball Sculpting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development to implement this plan task-by-task.

**Goal:** Лепить один снежный шар из видимого сугроба одноразовым жестом через меню, с отменой и возвратом ввода.

**Architecture:** Чистая модель жеста собирает уникальные колонки снимка одной опоры. SnowSimulation подтверждает и атомарно снимает снег. Временная AppKit-панель получает жест и Esc, WinterSceneController создаёт обычную игрушку.

**Tech Stack:** Swift, AppKit, CoreGraphics, XCTest, текущие упаковка и локальная подпись.

Спецификация: ../specs/2026-11-06-seasonart-snowball-sculpting-design.md. Исполнение уже разрешено пользователем, дополнительные подтверждения этапов не нужны. Статусы задач ведутся здесь.

Статус на 2026-11-06 22:41 MSK: задачи 1–3 завершены. Полный Swift-набор: 92 теста без ошибок, обязательная упаковка: 19 тестов, OK. Нативные результаты и ограничения записаны в docs/verification/snowball-sculpting.md. Исходные настройки восстановлены, тестовые окна закрыты.

## Task 1: Жест и локальный сбор снега

- [x] Написать тесты чистой модели и SnowSimulation, получить RED, затем реализацию и GREEN.
- [x] Создать Sources/SeasonArt/SnowSculptingGesture.swift и Tests/SeasonArtTests/SnowSculptingTests.swift. Расширить SnowSimulation только узкими операциями чтения и подтверждения.

Контракты: `simulation.sculptingSource(at: CGPoint) -> SculptingSource?`, `SnowSculptingGesture(source:at:)`, `gesture.include(CGPoint)`, `gesture.size: WinterBallSize?`, `simulation.commitSculpting(gesture) -> SculptedBall?`. Результат содержит size и center. Снимок содержит идентичность слоя, геометрию и видимые колонки. Количество снятого снега ограничено 220 pt², пороги размеров 40/100/220 pt², не больше 2 pt высоты с колонки. До отпускания снег не изменяется.

```swift
let sim = SnowSimulation(width: 600, height: 400, snowfall: .off)
XCTAssertNil(sim.sculptingSource(at: CGPoint(x: 100, y: 0)), "Пустая опора не создаёт снег")
```

Проверить повторное прохождение колонок, отсутствие сбора при движении вне снега, проверку размеров на границах, исчезновение/движение/перекрытие опоры, неизменность другого слоя и ground, несовпадение слоя после удаления. Нечисловые и огромные координаты отклоняются до преобразования в индекс. При недостаточном запасе подтверждение ничего не меняет.

Verify: `swift test --filter SnowSculptingTests`, затем полный `swift test`. Коммит `feat: model snowball sculpting from visible snow`.

## Task 2: Одноразовая панель, контроллер и меню

- [x] Написать поведенческие тесты, получить RED, реализовать и получить GREEN.
- [x] Создать Sources/SeasonArt/SnowSculptingWindow.swift и Tests/SeasonArtTests/SnowSculptingWindowTests.swift. Расширить WinterSceneController, AppDelegate и контроллерные тесты.

Панель получает координаты в глобальной системе и передаёт контроллеру. Она может стать key для Esc, не main, пропускает клавиатурные команды кроме отмены без перенаправления в чужие приложения. Отображает читаемую подсказку и предварительный размер. Таймер ожидания 15 секунд отменяется при начале жеста. Закрытие идемпотентно и освобождает захват. Закрытая панель и её callbacks не создают игрушку.

Контроллер: startSculpting, cancelSculpting, isSculpting. Состояния enabled/active/suppressed, clear, fit, close и изменение опоры отменяют жест. По успешному mouseUp проверяется лимит и атомарно подтверждается снег, создаётся один обычный шар. Клик вне снега отменяет режим. При начале другого режима лепки предыдущий закрывается. Панель участвует в sharingType и FixedSpace, всегда закрывается при системном выборе окна.

В AppDelegate добавить «Лепить снежок…», отключать при лимите и вне Snow. Перед началом отменять режим на остальных экранах. После закрытия восстанавливать прежнее приложение только если фокус всё ещё принадлежит лепке, не перехватывать фокус после явного переключения пользователем.

```swift
controller.isEnabled = true
controller.startSculpting()
XCTAssertTrue(controller.isSculpting)
controller.isSuppressed = true
XCTAssertFalse(controller.isSculpting, "Системный выбор окна отменяет лепку")
```

Verify: полный `swift test`. Коммит `feat: add one-shot snowball sculpting controls`.

## Task 3: Нативная проверка и установка

- [x] Проверить полный Swift-набор и 19 обязательных packaging-тестов на неизменяемых исходниках.
- [x] Собрать с Oasis Dev, установить с резервной копией, сверить подпись и SHA-256.
- [x] Нативно создать шар из настоящего снега, проверить Esc и клик вне сугроба, ввод текста после завершения, переключение режима, fullscreen и системный выбор окна.
- [x] Проверить таймер отмены и отсутствие панелей после выхода/перезапуска. Вернуть временные настройки.
- [x] Обновить README и docs/verification/snowball-sculpting.md, сохранить результаты и ограничения.

```bash
swift test
SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh
SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v
bash Scripts/install.sh
codesign --verify --deep --strict "$HOME/Applications/SeasonArt.app"
```

Во время компиляции Swift-файлы не редактируются, компилятор запускается один. Сон исключён пользователем, второго монитора нет. Нативные личные артефакты остаются ignored. Коммит `docs: record snowball sculpting verification`.
