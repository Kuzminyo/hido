import AppKit
import ServiceManagement
import SwiftUI

/// Hides menu bar icons by stretching a separator item: everything to its left is pushed off
/// the screen. A chevron item on its right toggles between hidden and shown.
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let hiddenLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 14
    static let autoHideDelays: [Int] = [5, 10, 30, 0]

    // Created first, so it sits to the right of the separator.
    private let toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separatorItem = NSStatusBar.system.statusItem(withLength: MenuBarController.separatorLength)
    private(set) var isHidden = false
    private var autoHideWork: DispatchWorkItem?
    private var mouseMonitor: Any?
    private var guide: NSPopover?

    private var autoHideDelay: Int {
        get { UserDefaults.standard.object(forKey: "autoHideDelay") as? Int ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: "autoHideDelay") }
    }

    private var revealsOnHover: Bool {
        get { UserDefaults.standard.bool(forKey: "revealsOnHover") }
        set {
            UserDefaults.standard.set(newValue, forKey: "revealsOnHover")
            updateMouseMonitor()
        }
    }

    override init() {
        super.init()
        toggleItem.autosaveName = "HidoToggle"
        separatorItem.autosaveName = "HidoSeparator"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.button?.image = Self.separatorImage
        separatorItem.button?.toolTip = "Иконки левее этой черты Hido прячет. Перетаскивайте их с зажатым ⌘."

        updateToggleIcon()
        updateMouseMonitor()

        if UserDefaults.standard.bool(forKey: "didShowGuide") {
            // Give the menu bar a moment to lay out before measuring positions.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.hide() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showGuide() }
        }
    }

    // MARK: - Hide and show

    func hide() {
        guard !isHidden else { return }
        guard isSeparatorLeftOfToggle else {
            // Stretching a separator that sits to the right would push the chevron away too.
            showMisplacedSeparatorAlert()
            return
        }
        autoHideWork?.cancel()
        isHidden = true
        separatorItem.button?.image = nil
        separatorItem.length = Self.hiddenLength
        updateToggleIcon()
    }

    func show() {
        guard isHidden else {
            scheduleAutoHide()
            return
        }
        isHidden = false
        separatorItem.length = Self.separatorLength
        separatorItem.button?.image = Self.separatorImage
        updateToggleIcon()
        scheduleAutoHide()
    }

    private var isSeparatorLeftOfToggle: Bool {
        guard let separator = separatorItem.button?.window?.frame,
              let toggle = toggleItem.button?.window?.frame else { return true }
        return separator.minX < toggle.minX
    }

    private func scheduleAutoHide() {
        autoHideWork?.cancel()
        guard autoHideDelay > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Don't snap shut while the pointer is still in the menu bar.
            if self.isMouseInMenuBar {
                self.scheduleAutoHide()
            } else {
                self.hide()
            }
        }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(autoHideDelay), execute: work)
    }

    private func updateToggleIcon() {
        let symbol = isHidden ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isHidden ? "Показать иконки" : "Спрятать иконки")
        toggleItem.button?.image = image?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
    }

    // MARK: - Clicks

    @objc private func toggleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            isHidden ? show() : hide()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let delays = NSMenuItem(title: "Прятать автоматически", action: nil, keyEquivalent: "")
        let delaysMenu = NSMenu()
        for delay in Self.autoHideDelays {
            let item = NSMenuItem(
                title: delay == 0 ? "Никогда" : "Через \(delay) с",
                action: #selector(setAutoHideDelay(_:)), keyEquivalent: ""
            )
            item.tag = delay
            item.target = self
            item.state = delay == autoHideDelay ? .on : .off
            delaysMenu.addItem(item)
        }
        delays.submenu = delaysMenu
        menu.addItem(delays)

        let hover = NSMenuItem(title: "Показывать при наведении на строку меню", action: #selector(toggleHover), keyEquivalent: "")
        hover.target = self
        hover.state = revealsOnHover ? .on : .off
        menu.addItem(hover)

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let guide = NSMenuItem(title: "Как пользоваться…", action: #selector(showGuideFromMenu), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из Hido", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self

        // Attach the menu only for this click, so a left click keeps toggling.
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        toggleItem.menu = nil
    }

    @objc private func setAutoHideDelay(_ sender: NSMenuItem) {
        autoHideDelay = sender.tag
        if !isHidden { scheduleAutoHide() }
    }

    @objc private func toggleHover() {
        revealsOnHover.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    @objc private func showGuideFromMenu() {
        show()
        showGuide()
    }

    @objc private func quit() {
        // Leave the icons visible: a stretched separator disappears with the app anyway.
        NSApp.terminate(nil)
    }

    // MARK: - Hover reveal

    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return false }
        return mouse.y >= screen.visibleFrame.maxY
    }

    private func updateMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        guard revealsOnHover else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, self.isHidden else { return }
            let mouse = NSEvent.mouseLocation
            // Reveal when the pointer reaches the menu bar on the right half, where the icons are.
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
                  self.isMouseInMenuBar, mouse.x > screen.frame.midX else { return }
            self.show()
        }
    }

    // MARK: - Guide

    private func showGuide() {
        guard let button = toggleItem.button else { return }
        guide?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: GuideView { [weak self] in
            self?.guide?.close()
        })
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guide = popover
        UserDefaults.standard.set(true, forKey: "didShowGuide")
    }

    private func showMisplacedSeparatorAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Разделитель стоит не там"
        alert.informativeText = "Черта «|» должна быть левее стрелки Hido. Зажмите ⌘ и перетащите черту левее стрелки — иначе Hido спрятал бы и саму стрелку."
        alert.runModal()
    }

    private static let separatorImage: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1, width: 1.5, height: rect.height - 2), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct GuideView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Как прятать иконки")
                .font(.system(size: 15, weight: .semibold))
            step("1", "Зажмите **⌘** и перетащите ненужные иконки **левее черты «|»** рядом со стрелкой.")
            step("2", "Нажмите на **стрелку**, и все иконки левее черты спрячутся. Нажмите ещё раз — появятся.")
            step("3", "Правый клик по стрелке — настройки: когда прятать автоматически, показ при наведении, автозапуск.")
            HStack {
                Spacer()
                Button("Понятно", action: onDone)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    private func step(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
