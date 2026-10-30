import AppKit
import ServiceManagement
import SwiftUI

/// Hides menu bar icons by stretching a separator item over the free space to its left, so the
/// icons there no longer fit and macOS hides them. The separator is also the button: click the
/// "|" to hide, click the empty stretched area to show again. There is no chevron of our own,
/// because macOS already shows its "«" button for icons that don't fit.
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let separatorLength: CGFloat = 14
    static let autoHideDelays: [Int] = [5, 10, 30, 0]

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
        separatorItem.autosaveName = "HidoSeparator"
        if let button = separatorItem.button {
            button.target = self
            button.action = #selector(separatorClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateSeparator()
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
        autoHideWork?.cancel()
        let length = hiddenLength
        isHidden = true
        separatorItem.length = length
        updateSeparator()
    }

    func show() {
        guard isHidden else {
            scheduleAutoHide()
            return
        }
        isHidden = false
        separatorItem.length = Self.separatorLength
        updateSeparator()
        scheduleAutoHide()
    }

    /// How far to stretch the separator so it fills the menu bar from its left edge up to
    /// where it stands. Everything that was there no longer fits and macOS hides it.
    /// It must not be wider than that: on recent macOS a separator that doesn't fit is the
    /// one that gets hidden, and the icons stay.
    private var hiddenLength: CGFloat {
        guard let frame = separatorItem.button?.window?.frame,
              let screen = separatorItem.button?.window?.screen ?? NSScreen.main else { return 300 }
        // Status items start right of the notch; without a notch, assume they never reach
        // past the middle of the screen, where the app menus are.
        let leftEdge = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
        return max(Self.separatorLength, frame.maxX - leftEdge - 8)
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

    /// Shown: a thin "|" to click. Hidden: an empty area over where the icons were.
    private func updateSeparator() {
        separatorItem.button?.image = isHidden ? nil : Self.separatorImage
        separatorItem.button?.toolTip = isHidden
            ? "Нажмите, чтобы вернуть спрятанные иконки"
            : "Нажмите, чтобы спрятать иконки левее черты. Перетаскивайте иконки с зажатым ⌘."
    }

    // MARK: - Clicks

    @objc private func separatorClicked() {
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
        separatorItem.menu = menu
        separatorItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        separatorItem.menu = nil
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
        guard let button = separatorItem.button else { return }
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
            step("1", "Зажмите **⌘** и перетащите ненужные иконки **левее черты «|»**.")
            step("2", "Нажмите на **черту** — иконки левее неё спрячутся. Чтобы вернуть, нажмите на пустое место, где они были.")
            step("3", "Спрятанные иконки можно открыть и списком — системной кнопкой **«**.")
            step("4", "Правый клик по черте — настройки: когда прятать автоматически, показ при наведении, автозапуск.")
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
