import AppKit
import MetalKit
import ServiceManagement
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum StartupError {
        case metalUnavailable
        case scenesUnavailable
    }

    static func startupErrorAlert(_ error: StartupError) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Не удалось запустить SeasonArt"
        switch error {
        case .metalUnavailable:
            alert.informativeText = "Metal недоступен на этом Mac. Для отображения эффектов нужна поддержка Metal."
        case .scenesUnavailable:
            alert.informativeText = "Не удалось создать эффекты для подключённых экранов. Попробуйте запустить SeasonArt ещё раз."
        }
        alert.addButton(withTitle: "Закрыть")
        return alert
    }

    private var device: MTLDevice!
    private var screens: [ScreenSnow] = []
    private var snowfall = Snowfall.steady
    private var accumulates = true
    private var thaws = true
    private var snowOnWindows = true
    private var behindWindows = false
    private var snowfallHeld = false
    private var halloween = false
    private var statusItem: NSStatusItem!
    /// Без строки в Dock приложение считается фоновым: App Nap сдвигает его таймеры и физика подтормаживает.
    private var animationActivity: NSObjectProtocol?
    private let snowfallSlider = SnowfallSlider()
    private var accumulateItem: NSMenuItem!
    private var meltItem: NSMenuItem!
    private var blizzardItem: NSMenuItem!
    private var colorfulFirefliesItem: NSMenuItem!
    private var dockAccessItem: NSMenuItem!
    private var dockPositionItem: NSMenuItem!
    private var dockPositionItems: [DockSnowPosition: NSMenuItem] = [:]
    private var snowOnWindowsItem: NSMenuItem!
    private var skipSnowNearMenuBarItem: NSMenuItem!
    private var clearItem: NSMenuItem!
    private var modeItems: [Mode: NSMenuItem] = [:]
    private var defaultPerformanceItem: NSMenuItem!
    private var maxPerformanceItem: NSMenuItem!
    private var behindWindowsItem: NSMenuItem!
    private var fullScreenItem: NSMenuItem!
    private var screenshotsItem: NSMenuItem!
    private var deepInteractionItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var winterItem: NSMenuItem!
    private var winterBallItems: [NSMenuItem] = []
    private var winterClearItem: NSMenuItem!
    private var winterPlowItem: NSMenuItem!
    private var winterTreeEditorItem: NSMenuItem!
    private var finderGarlandItem: NSMenuItem!
    private var sleighItem: NSMenuItem!
    private var treeEditor: WinterTreeEditor?
    private var winterToyItems: [WinterToy: NSMenuItem] = [:]
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private let screenshots = ScreenshotWatch()
    private var screenLocked = false
    private var sessionInactive = false
    private var welcome: WelcomeController?
    private let power = PowerMonitor()
    private let wallpaper = WallpaperController()
    private let wallpaperGallery = WallpaperGalleryController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Повторная проверка после регистрации процесса выбирает одну копию до создания оверлеев.
        if !StartupGuard.shouldLaunch() { NSApp.terminate(nil) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        animationActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Сезонные эффекты анимируются поверх рабочего стола")
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSApp.activate()
            Self.startupErrorAlert(.metalUnavailable).runModal()
            NSApp.terminate(nil)
            return
        }
        self.device = device
        snowfall = Preferences.snowfall
        accumulates = Preferences.accumulate
        thaws = Preferences.meltSnow
        snowOnWindows = Preferences.snowOnWindows
        behindWindows = Preferences.behindWindows
        snowfallHeld = !Preferences.welcomed
        syncScreens()
        guard !screens.isEmpty else {
            NSApp.activate()
            Self.startupErrorAlert(.scenesUnavailable).runModal()
            NSApp.terminate(nil)
            return
        }

        statusItem = makeStatusItem()
        updateStatusIcon()
        refreshHalloween()
        observeSystem()
        Marquee.enabled = Preferences.deepInteraction
        screenshots.stepAside = { [weak self] aside in self?.screens.forEach { $0.stepAside(aside) } }
        screenshots.start()
        if snowfallHeld {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showWelcome() }
        }
    }

    // MARK: - Displays

    /// One overlay per display: new displays get snow, removed ones lose theirs, the rest follow resolution changes.
    private func syncScreens() {
        let current = NSScreen.screens
        let ids = Set(current.compactMap(\.displayID))
        for gone in screens where !ids.contains(gone.displayID) { gone.close() }
        screens.removeAll { !ids.contains($0.displayID) }

        for screen in current {
            if let existing = screens.first(where: { $0.displayID == screen.displayID }) {
                existing.fit(to: screen)
            } else if let snow = ScreenSnow(screen: screen, device: device, snowOnWindows: { [unowned self] in snowOnWindows }) {
                snow.simulation.snowfallHeld = snowfallHeld
                snow.simulation.snowfallReleased = { [weak self] in self?.releaseSnowfall() }
                snow.halloween = halloween
                snow.mode = Preferences.mode
                snow.maxFrameRate = Preferences.maxPerformance
                snow.activityChanged = { [weak self] in self?.updateActivity() }
                snow.apply(power.budget)
                screens.append(snow)
            }
        }
        updateActivity()
    }

    private func releaseSnowfall() {
        snowfallHeld = false
        for snow in screens { snow.simulation.snowfallHeld = false }
    }

    private func showWelcome() {
        let welcome = WelcomeController()
        welcome.scatter = { [weak self] pieces in
            guard let self, let first = pieces.first else { return }
            let point = CGPoint(x: CGFloat(first.position.x), y: CGFloat(first.position.y))
            guard let snow = screens.first(where: { $0.window.frame.contains(point) }) ?? screens.first else { return }
            let origin = SIMD2(Float(snow.window.frame.minX), Float(snow.window.frame.minY))
            snow.simulation.scatter(pieces.map { piece in
                var local = piece
                local.position -= origin
                return local
            })
        }
        welcome.skipped = { [weak self] in self?.releaseSnowfall() }
        welcome.finished = { [weak self] in
            Preferences.welcomed = true
            self?.welcome = nil
        }
        self.welcome = welcome
        welcome.show()
    }

    // MARK: - Menu

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: "Интенсивность"))
        snowfallSlider.changed = { [unowned self] in select($0) }
        let sliderItem = NSMenuItem()
        sliderItem.view = snowfallSlider
        menu.addItem(sliderItem)
        menu.addItem(.separator())
        let modes = NSMenu()
        modes.autoenablesItems = false
        for mode in Mode.allCases {
            let item = add(mode.title, #selector(chooseMode), to: modes)
            item.tag = mode.rawValue
            modeItems[mode] = item
        }
        menu.addItem(withTitle: "Режим", action: nil, keyEquivalent: "").submenu = modes
        let performance = NSMenu()
        performance.autoenablesItems = false
        defaultPerformanceItem = add("Обычная", #selector(choosePerformance), to: performance)
        maxPerformanceItem = add("Максимальная", #selector(choosePerformance), to: performance)
        menu.addItem(withTitle: "Производительность", action: nil, keyEquivalent: "").submenu = performance
        accumulateItem = add("Накапливать", #selector(toggleAccumulate), to: menu)
        meltItem = add("Таяние снега", #selector(toggleMeltSnow), to: menu)
        blizzardItem = add("Метель", #selector(toggleBlizzard), to: menu)
        colorfulFirefliesItem = add("Разноцветные светлячки", #selector(toggleColorfulFireflies), to: menu)
        let dockPositionMenu = NSMenu()
        dockPositionMenu.autoenablesItems = false
        for position in DockSnowPosition.allCases {
            let item = add(position.title, #selector(chooseDockSnowPosition), to: dockPositionMenu)
            item.tag = position.rawValue
            dockPositionItems[position] = item
        }
        dockPositionItem = menu.addItem(withTitle: "Расположение снега", action: nil, keyEquivalent: "")
        dockPositionItem.submenu = dockPositionMenu
        dockAccessItem = add("Снег на иконках: разрешить доступ…", #selector(allowDockGeometry), to: menu)
        snowOnWindowsItem = add("Снег на окнах", #selector(toggleSnowOnWindows), to: menu)
        skipSnowNearMenuBarItem = add("Пропускать окна у строки меню", #selector(toggleSkipSnowNearMenuBar), to: menu)
        deepInteractionItem = add("Взаимодействие с выделением", #selector(toggleDeepInteraction), to: menu)
        clearItem = add("Убрать снег", #selector(clearSnow), to: menu)
        menu.addItem(.separator())
        behindWindowsItem = add("За окнами", #selector(toggleBehindWindows), to: menu)
        fullScreenItem = add("Поверх полноэкранных приложений", #selector(toggleFullScreen), to: menu)
        screenshotsItem = add("Показывать на снимках экрана", #selector(toggleScreenshots), to: menu)
        menu.addItem(.separator())
        add("Сезонные обои…", #selector(showWallpaperGallery), to: menu)
        add("Выбрать обои…", #selector(chooseWallpaper), to: menu)
        loginItem = add("Запускать при входе", #selector(toggleOpenAtLogin), to: menu)
        add("О SeasonArt", #selector(showAbout), to: menu)
        menu.addItem(withTitle: "Выйти из SeasonArt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let winterMenu = NSMenu()
        winterMenu.autoenablesItems = false
        for (size, title) in [(WinterBallSize.large, "Большой снежный шар"), (.medium, "Средний снежный шар"), (.small, "Маленький снежный шар")] {
            let ball = add(title, #selector(createWinterBall), to: winterMenu)
            ball.tag = size.rawValue
            winterBallItems.append(ball)
        }
        winterMenu.addItem(.separator())
        for toy in WinterToy.allCases {
            winterToyItems[toy] = add(toy.menuTitle, #selector(toggleWinterToy(_:)), to: winterMenu)
        }
        winterTreeEditorItem = add("Украсить ёлку…", #selector(showTreeEditor), to: winterMenu)
        winterMenu.addItem(.separator())
        finderGarlandItem = add("Гирлянда на окнах Finder", #selector(toggleFinderGarland), to: winterMenu)
        sleighItem = add("Запустить сани Деда Мороза", #selector(launchSleigh), to: winterMenu)
        winterPlowItem = add("Убрать снег трактором", #selector(startWinterPlow), to: winterMenu)
        winterClearItem = add("Убрать зимние игрушки", #selector(clearWinterObjects), to: winterMenu)
        winterItem = NSMenuItem(title: "Зимние игрушки", action: nil, keyEquivalent: "")
        winterItem.submenu = winterMenu
        menu.insertItem(winterItem, at: menu.items.firstIndex(of: behindWindowsItem) ?? menu.items.count)

        item.menu = menu
        return item
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        snowfallSlider.snowfall = snowfall
        accumulateItem.state = accumulates ? .on : .off
        let mode = Preferences.mode
        let autumn = mode == .autumn
        let rain = mode == .rain
        let blossom = mode == .blossom
        blizzardItem.isHidden = mode != .snow
        colorfulFirefliesItem.isHidden = mode != .fireflies
        colorfulFirefliesItem.state = Preferences.colorfulFireflies ? .on : .off
        dockPositionItem.isHidden = mode != .snow
        for (position, item) in dockPositionItems {
            item.state = position == Preferences.dockSnowPosition ? .on : .off
        }
        dockAccessItem.isHidden = mode != .snow || Preferences.dockSnowPosition != .above || DockIconGeometry.hasAccess
        blizzardItem.state = Preferences.blizzard ? .on : .off
        for (choice, item) in modeItems { item.state = choice == mode ? .on : .off }
        // Дождь не накапливается, поэтому таяние и очистка ему не нужны.
        accumulateItem.isHidden = rain || mode.isNightEffect
        meltItem.isHidden = rain || mode.isNightEffect
        clearItem.isHidden = rain || mode.isNightEffect
        meltItem.title = autumn ? "Увядание листьев" : blossom ? "Увядание лепестков" : "Таяние снега"
        snowOnWindowsItem.title = autumn ? "Листья на окнах" : blossom ? "Лепестки на окнах" : rain ? "Дождь на окнах" : "Снег на окнах"
        if mode == .starfall { snowOnWindowsItem.title = "Искры на окнах" }
        snowOnWindowsItem.isHidden = mode == .fireflies
        clearItem.title = autumn ? "Убрать листья" : blossom ? "Убрать лепестки" : "Убрать снег"
        meltItem.state = thaws ? .on : .off
        meltItem.isEnabled = accumulates
        snowOnWindowsItem.state = snowOnWindows ? .on : .off
        skipSnowNearMenuBarItem.isEnabled = snowOnWindows
        skipSnowNearMenuBarItem.state = Preferences.skipSnowNearMenuBar ? .on : .off
        deepInteractionItem.state = Preferences.deepInteraction ? .on : .off
        deepInteractionItem.isHidden = mode.isNightEffect
        deepInteractionItem.isEnabled = snowOnWindows
        clearItem.isEnabled = screens.contains { $0.simulation.hasSnow || $0.simulation.spriteCount > 0 }
        defaultPerformanceItem.state = Preferences.maxPerformance ? .off : .on
        maxPerformanceItem.state = Preferences.maxPerformance ? .on : .off
        behindWindowsItem.state = behindWindows ? .on : .off
        fullScreenItem.state = Preferences.showOverFullScreen ? .on : .off
        fullScreenItem.isEnabled = !behindWindows
        screenshotsItem.state = Preferences.showInScreenshots ? .on : .off
        winterItem.isHidden = mode != .snow
        let winter = screenAtPointer()?.winter
        winterItem.title = winter?.scene.hasCapacity == false
            ? "Зимние игрушки: лимит \(WinterScene.maximumObjects)"
            : "Зимние игрушки"
        for item in winterBallItems { item.isEnabled = winter?.canCreate ?? false }
        for (toy, item) in winterToyItems {
            item.isEnabled = winter?.canUseToys == true
            item.state = winter?.hasToy(toy) == true ? .on : .off
        }
        winterTreeEditorItem.isEnabled = winter?.canUseToys == true
        sleighItem.isEnabled = winter?.canLaunchSleigh == true
        finderGarlandItem.state = Preferences.finderGarland ? .on : .off
        winterClearItem.isEnabled = screens.contains { $0.winter.hasObjects }
        winterPlowItem.isEnabled = winter?.canPlow ?? false
        winterPlowItem.title = winter?.canPlow == true ? "Убрать снег трактором" : "Трактор: нет доступной полки Dock или идёт уборка"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func select(_ snowfall: Snowfall) {
        self.snowfall = snowfall
        Preferences.snowfall = snowfall
        for snow in screens { snow.simulation.snowfall = snowfall }
        updateStatusIcon()
    }

    @objc private func toggleAccumulate() {
        accumulates.toggle()
        Preferences.accumulate = accumulates
        for snow in screens { snow.simulation.accumulates = accumulates }
    }

    @objc private func toggleMeltSnow() {
        thaws.toggle()
        Preferences.meltSnow = thaws
        for snow in screens { snow.simulation.thaws = thaws }
    }

    @objc private func toggleBlizzard() {
        Preferences.blizzard.toggle()
        for snow in screens { snow.simulation.blizzard = Preferences.blizzard }
    }

    @objc private func toggleColorfulFireflies() {
        Preferences.colorfulFireflies.toggle()
        for snow in screens { snow.simulation.colorfulFireflies = Preferences.colorfulFireflies }
    }

    @objc private func chooseDockSnowPosition(_ sender: NSMenuItem) {
        guard let position = DockSnowPosition(rawValue: sender.tag) else { return }
        Preferences.dockSnowPosition = position
        for snow in screens { snow.dockSnowPosition = position }
    }

    @objc private func allowDockGeometry() {
        let alert = NSAlert()
        alert.messageText = "Снег на иконках Dock"
        alert.informativeText = "Для точного положения снежной шапки нужен доступ «Универсальный доступ». Он позволяет читать положение и размер иконок Dock. Разрешите SeasonArt в настройках macOS."
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleSnowOnWindows() {
        snowOnWindows.toggle()
        Preferences.snowOnWindows = snowOnWindows
        if !snowOnWindows { screens.forEach { $0.dropWindowSnow() } }
    }

    @objc private func toggleDeepInteraction() {
        Preferences.deepInteraction.toggle()
        Marquee.enabled = Preferences.deepInteraction
    }

    @objc private func toggleSkipSnowNearMenuBar() {
        Preferences.skipSnowNearMenuBar.toggle()
        screens.forEach { $0.refreshWindowSnow() }
    }

    @objc private func clearSnow() {
        let direction = screens.first?.simulation.breezeDirection ?? -1
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for snow in screens { snow.simulation.blowAway(direction: direction, calm: calm) }
    }

    @objc private func toggleBehindWindows() {
        behindWindows.toggle()
        Preferences.behindWindows = behindWindows
        for snow in screens { snow.behindWindows = behindWindows }
    }

    @objc private func toggleFullScreen() {
        Preferences.showOverFullScreen.toggle()
        for snow in screens { snow.overFullScreen = Preferences.showOverFullScreen }
    }

    @objc private func toggleScreenshots() {
        Preferences.showInScreenshots.toggle()
        for snow in screens {
            snow.window.showsInScreenshots = Preferences.showInScreenshots
            snow.dock.window.showsInScreenshots = Preferences.showInScreenshots
            snow.winter.showsInScreenshots = Preferences.showInScreenshots
        }
    }

    @objc private func chooseWallpaper() {
        wallpaper.chooseWallpaper()
    }

    @objc private func showWallpaperGallery() {
        wallpaperGallery.show()
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate()
            Self.loginErrorAlert(error).runModal()
        }
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let mode = Mode(rawValue: sender.tag) else { return }
        guard mode != Preferences.mode else { return }
        Preferences.mode = mode
        if mode != .snow { treeEditor?.close() }
        refreshHalloween()
        updateStatusIcon()
        let direction = screens.first?.simulation.breezeDirection ?? -1
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for snow in screens {
            snow.winter.isEnabled = mode == .snow
            snow.simulation.switchMode(to: mode, direction: direction, calm: calm)
        }
    }

    private func screenAtPointer() -> ScreenSnow? {
        let point = NSEvent.mouseLocation
        return screens.first { $0.screen.frame.contains(point) } ?? screens.first
    }

    @objc private func createWinterBall(_ sender: NSMenuItem) {
        guard let size = WinterBallSize(rawValue: sender.tag), let screen = screenAtPointer() else { return }
        let frame = screen.screen.frame
        let point = CGPoint(x: NSEvent.mouseLocation.x - frame.minX,
                            y: screen.screen.visibleFrame.minY - frame.minY + 160 + size.radius)
        screen.winter.create(size, at: point)
    }

    @objc private func toggleWinterToy(_ sender: NSMenuItem) {
        guard let toy = winterToyItems.first(where: { $0.value === sender })?.key,
              let screen = screenAtPointer() else { return }
        if toy == .tree, screen.winter.hasToy(.tree) { treeEditor?.close() }
        toggleWinterToy(toy, on: screen)
    }

    private func toggleWinterToy(_ toy: WinterToy, on screen: ScreenSnow) {
        let frame = screen.screen.frame
        if toy == .tree {
            screen.winter.toggleToy(.tree, at: CGPoint(x: 28, y: 0))
            return
        }
        let blade = WinterToy.shovelBlade
        let x = min(max(0, NSEvent.mouseLocation.x - frame.minX - blade.x), max(0, frame.width - toy.size.width))
        let floor = screen.simulation.winterSurfaceY(at: x + blade.x, on: nil) ?? 0
        let y = max(0, floor - blade.y)
        screen.winter.toggleToy(toy, at: CGPoint(x: x, y: y))
    }

    @objc private func showTreeEditor() {
        guard let screen = screenAtPointer(), screen.winter.canUseToys else { return }
        if !screen.winter.hasToy(.tree) { toggleWinterToy(.tree, on: screen) }
        treeEditor?.close()
        let editor = WinterTreeEditor(settings: Preferences.treeDecorations, apply: { [weak self] decorations in
            Preferences.treeDecorations = decorations
            for screen in self?.screens ?? [] { screen.winter.updateTree(decorations) }
        }, remove: { [weak self, weak screen] in
            guard let self, let screen, screen.winter.hasToy(.tree) else { return }
            toggleWinterToy(.tree, on: screen)
        })
        treeEditor = editor
        NSApp.activate()
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func launchSleigh() { screenAtPointer()?.winter.launchSleigh() }

    @objc private func toggleFinderGarland() {
        Preferences.finderGarland.toggle()
        for screen in screens {
            screen.winter.showsFinderGarlands = Preferences.finderGarland
            screen.refreshWindowSnow()
        }
    }

    @objc private func clearWinterObjects() {
        treeEditor?.close()
        for screen in screens { screen.winter.clear() }
    }

    @objc private func startWinterPlow() { screenAtPointer()?.winter.startPlow() }

    @objc private func choosePerformance(_ sender: NSMenuItem) {
        Preferences.maxPerformance = sender === maxPerformanceItem
        for snow in screens { snow.maxFrameRate = Preferences.maxPerformance }
    }

    static func loginErrorAlert(_ error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось изменить автозапуск"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Понятно")
        return alert
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Season Art"
        alert.informativeText = "Сезонные эффекты для рабочего стола."
        if let url = Bundle.main.url(forResource: "SeasonArtLogo", withExtension: "png", subdirectory: "Branding"),
           let image = NSImage(contentsOf: url) {
            let logo = NSImageView(frame: CGRect(x: 0, y: 0, width: 228, height: 76))
            logo.image = image
            logo.imageScaling = .scaleProportionallyDown
            logo.wantsLayer = true
            logo.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
            logo.layer?.cornerRadius = 8
            alert.accessoryView = logo
        }
        alert.addButton(withTitle: "Закрыть")
        NSApp.activate()
        alert.runModal()
    }

    private func updateStatusIcon() {
        statusItem.button?.image = Self.icon(halloween: halloween, dimmed: snowfall == .off)
    }

    private static let symbol: [Mode: String] = [.snow: "snowflake", .autumn: "leaf", .rain: "cloud.rain",
                                               .fireflies: "sparkles", .starfall: "moon.stars"]

    private static func icon(halloween: Bool, dimmed: Bool) -> NSImage? {
        let image = halloween ? Halloween.icon : Preferences.mode == .blossom ? Blossom.icon
            : NSImage(systemSymbolName: Self.symbol[Preferences.mode] ?? "snowflake", accessibilityDescription: "SeasonArt")
        guard dimmed, let image else { return image }
        // Dimmed by hand: the button's appearsDisabled also disables the slider in its menu, so Off could not be left.
        let faded = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        faded.isTemplate = image.isTemplate
        faded.accessibilityDescription = image.accessibilityDescription
        return faded
    }

    private func refreshHalloween() {
        // Дополнительный сезонный режим отключён независимо от даты и старых настроек.
        halloween = false
        for snow in screens { snow.halloween = false }
        updateStatusIcon()
    }

    // MARK: - System

    private func observeSystem() {
        power.changed = { [unowned self] in screens.forEach { $0.apply(power.budget) } }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { _ in }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.syncScreens() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.screens.forEach { $0.spaceChanged() } }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.screens.forEach { $0.watchWindows() } }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        _ change: @escaping (AppDelegate) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            self.updateActivity()
        })
    }

    private func updateActivity() {
        let awake = !screensAsleep && !screenLocked && !sessionInactive
        for snow in screens {
            snow.occlusionChanged()
            snow.setActive(awake && !snow.givesWay && (snow.window.occlusionState.contains(.visible) || snow.fading), asleep: !awake)
        }
    }
}
