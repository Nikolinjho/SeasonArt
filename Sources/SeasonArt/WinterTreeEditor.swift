import AppKit

final class WinterTreeEditor: NSWindowController {
    private var settings: WinterTreeDecorations
    private let apply: (WinterTreeDecorations) -> Void
    private let remove: () -> Void
    private let pages = NSTabView()
    private let height = NSSegmentedControl()
    private let topper = NSPopUpButton()
    private let preview = WinterTreePreview(frame: .zero)
    private var options: [(WinterTreeOrnament, NSButton)] = []

    init(settings: WinterTreeDecorations, apply: @escaping (WinterTreeDecorations) -> Void, remove: @escaping () -> Void) {
        self.settings = settings
        self.apply = apply
        self.remove = remove
        let window = WinterTreeEditorWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 332),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Украшения ёлки"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContent()
        window.center()
        synchronizeControls()
    }

    required init?(coder: NSCoder) { nil }

    private func makeContent() -> NSView {
        let content = NSView()
        let tabs = NSSegmentedControl(labels: ["Ёлка", "Украшения"], trackingMode: .selectOne,
                                      target: self, action: #selector(selectPage(_:)))
        tabs.selectedSegment = 0
        tabs.setAccessibilityLabel("Раздел настроек")
        pages.tabViewType = .noTabsNoBorder
        for (identifier, form) in [("tree", treeForm()), ("ornaments", ornamentForm())] {
            let page = NSView()
            form.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(form)
            NSLayoutConstraint.activate([
                form.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                form.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor),
                form.topAnchor.constraint(equalTo: page.topAnchor)
            ])
            let tab = NSTabViewItem(identifier: identifier)
            tab.view = page
            pages.addTabViewItem(tab)
        }

        let line = NSBox()
        line.boxType = .separator
        let remove = NSButton(title: "Убрать ёлку", target: self, action: #selector(removeTree))
        let surprise = NSButton(title: "Случайный набор", target: self, action: #selector(surpriseMe))
        let done = NSButton(title: "Готово", target: self, action: #selector(closeEditor))
        done.keyEquivalent = "\r"
        window?.defaultButtonCell = done.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [remove, surprise, spacer, done])
        footer.spacing = 8
        preview.setAccessibilityLabel("Превью ёлки")
        for view in [tabs, pages, preview, line, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            pages.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            pages.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 24),
            pages.trailingAnchor.constraint(equalTo: preview.leadingAnchor, constant: -24),
            pages.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16),
            preview.widthAnchor.constraint(equalToConstant: 220),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            preview.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16)
        ])
        return content
    }

    private func treeForm() -> NSView {
        let sizes = WinterTreeHeight.allCases
        height.segmentCount = sizes.count
        for (index, size) in sizes.enumerated() { height.setLabel(size.title, forSegment: index) }
        height.trackingMode = .selectOne
        height.target = self
        height.action = #selector(updateHeight)
        height.setAccessibilityLabel("Высота")
        topper.addItems(withTitles: WinterTreeTopper.allCases.map(\.title))
        topper.target = self
        topper.action = #selector(updateTopper)
        topper.setAccessibilityLabel("Верхушка")

        let heightLabel = NSTextField(labelWithString: "Высота")
        let topperLabel = NSTextField(labelWithString: "Верхушка")
        heightLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        topperLabel.font = heightLabel.font
        let form = NSStackView(views: [heightLabel, height, topperLabel, topper])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.setCustomSpacing(20, after: height)
        return form
    }

    private func ornamentForm() -> NSView {
        options = WinterTreeOrnament.allCases.enumerated().map { index, item in
            let button = NSButton(checkboxWithTitle: item.title, target: self, action: #selector(updateOrnament(_:)))
            button.tag = index
            return (item, button)
        }
        let grid = NSGridView(views: (0..<4).map { [options[$0].1, options[$0 + 4].1] })
        grid.columnSpacing = 20
        grid.rowSpacing = 12
        grid.xPlacement = .leading
        return grid
    }

    private func synchronizeControls() {
        height.selectedSegment = WinterTreeHeight.allCases.firstIndex(of: settings.height) ?? 1
        topper.selectItem(withTitle: settings.topper.title)
        for (item, button) in options { button.state = settings.ornaments.contains(item) ? .on : .off }
        preview.settings = settings
    }

    private func update() {
        synchronizeControls()
        apply(settings)
    }

    @objc private func selectPage(_ sender: NSSegmentedControl) {
        pages.selectTabViewItem(at: sender.selectedSegment)
    }

    @objc private func updateHeight() {
        guard WinterTreeHeight.allCases.indices.contains(height.selectedSegment) else { return }
        settings.height = WinterTreeHeight.allCases[height.selectedSegment]
        update()
    }

    @objc private func updateTopper() {
        guard WinterTreeTopper.allCases.indices.contains(topper.indexOfSelectedItem) else { return }
        settings.topper = WinterTreeTopper.allCases[topper.indexOfSelectedItem]
        update()
    }

    @objc private func updateOrnament(_ sender: NSButton) {
        let item = WinterTreeOrnament.allCases[sender.tag]
        if sender.state == .on { settings.ornaments.insert(item) } else { settings.ornaments.remove(item) }
        update()
    }

    @objc private func surpriseMe() {
        settings.surprise()
        update()
    }

    @objc private func closeEditor() { close() }

    @objc private func removeTree() {
        remove()
        close()
    }
}

private final class WinterTreeEditorWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

private final class WinterTreePreview: NSView {
    var settings = WinterTreeDecorations() { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: CGRect) {
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 11, yRadius: 11).fill()
        let size = settings.height.size
        let scale = min((bounds.width - 24) / WinterTreeHeight.tall.size.width, (bounds.height - 24) / WinterTreeHeight.tall.size.height)
        guard scale > 0 else { return }
        let rect = CGRect(x: bounds.midX - size.width * scale / 2, y: 12,
                          width: size.width * scale, height: size.height * scale)
        WinterTreeArtwork.draw(in: rect, decorations: settings)
    }
}
