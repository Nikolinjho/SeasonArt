# Automatic Snowballs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development to implement and review this plan.

**Goal:** По умолчанию собирать снежные шары обычным движением указателя по снегу и сохранить прежнюю сборку снеговика.

**Architecture:** До шага SnowSimulation контроллер обрабатывает пассивные координаты указателя. Существующая модель собирает уникальный снег, небольшое окно показывает черновик и пропускает ввод. Пауза, выход и максимум подтверждают один обычный WinterObject.

**Tech Stack:** Swift, AppKit, Metal frame loop, XCTest.

Дизайн: ../specs/2026-11-06-seasonart-automatic-snowballs-design.md. Пользователь согласовал поведение и поручил реализацию в текущей сессии.

## Task 1: Автоматическая лепка и интеграция

- [x] Добавить поведенческие тесты нового API контроллера, получить RED до реализации.
- [x] Реализовать автоматический проход, предварительный шар, остановку 0,35 секунды, выход, максимум, блокировку повторного создания до выхода и работу с кнопками.
- [x] Подключить пассивный шаг перед simulation.step в Renderer/ScreenSnow. Защитить сугроб от обычной расчистки до подтверждения. Сохранить режимы дождя и листьев.
- [x] Удалить команду одноразовой лепки и лишний захват ввода, обновить прежние тесты под новое поведение. Сохранить готовые шары и их физику.
- [x] Запустить целевые тесты, затем полный swift test на неизменяемых исходниках. Получить независимые spec и quality review, исправить блокеры. Коммит feat: sculpt snowballs automatically with pointer movement.

Ключевой тест нового поведения:

```swift
controller.updateAutomaticSculpting(at: start, dt: 1.0 / 60, mouseButtons: 0)
controller.updateAutomaticSculpting(at: end, dt: 1.0 / 60, mouseButtons: 0)
controller.updateAutomaticSculpting(at: end, dt: 0.4, mouseButtons: 0)
XCTAssertEqual(controller.scene.objects.count, 1, "Остановка завершает один шар без нажатия кнопки")
```

Verify: swift test. Проверки жизненного цикла выполняются с presentsWindows: false, без влияния на пользовательский ввод. Один компилятор за раз.

Task 1: 9ffdc978 и e736ea9. Полный Swift-набор: 95 тестов без ошибок, spec и quality review PASS.

## Task 2: Инерция при приземлении

- [x] Написать RED-тесты первого контакта в WinterScene и локального расталкивания в SnowSimulation. Объекты разного размера и скорость дают разную силу, повторный resting step не деформирует снег.
- [x] Добавить событие первого контакта до обнуления скорости и узкую операцию деформации выбранной опоры. Снятая масса уходит в боковые кучи и частицы, центр проседает. Игрушка использует новую высоту.
- [x] Проверить землю, Dock, окна, скрытый/пустой/пропавший слой, конечность координат и локальность. Сохранить прежнюю сборку снеговика.
- [x] Получить GREEN и полный swift test, независимые spec и quality review. Коммит feat: displace snow on winter toy landing.

Verify: swift test. Нативного ввода в этой задаче нет.

Task 2: 12916e1 и 77c2a35. Полный Swift-набор: 106 тестов без ошибок, spec и quality review PASS.

## Task 3: Приёмка и поставка

- [x] Обновить README и отчёт проверки под автоматическое управление.
- [x] Собрать с SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh. Выполнить SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v.
- [x] Установить через bash Scripts/install.sh, проверить строгую подпись, совпадение SHA-256, сохранение настроек.
- [ ] Коротко проверить через Cua Driver лепку без кнопок и меню, остановку на размере, обычные клики и перенос готового шара. Глобальный ввод только в пределах согласованного пользователем свободного времени.
- [ ] Сохранить доказательства и ограничения, закоммитить отчёт. Личная поставка локальная, без push.

Статус поставки: продуктовый код 77c2a35 установлен, настройки восстановлены. Контролируемый Cua-прогон ожидает свободного ввода. Отчёт: docs/verification/automatic-snowballs.md.
