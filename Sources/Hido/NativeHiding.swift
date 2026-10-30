import AppKit
import ApplicationServices
import HidoShim

/// Hiding for macOS 27+, where a stretched separator gets thrown out of the menu bar.
/// Reads whose icons sit left of the separator (needs Accessibility), then asks macOS to
/// keep only the others; macOS hides the rest and reflows the bar itself, with no "«".
/// Approach adapted from Hidden Bar by Dwarves Foundation (MIT).
final class NativeHiding {
    /// macOS's own items (clock, Wi-Fi, Control Center…) always stay; unknown ids are ignored.
    private static let systemItemsToKeep = (0..<64).map { NSNumber(value: $0) }

    private var assertion: AnyObject?

    static var isAvailable: Bool { HidoMenuBarVisibilityIsAvailable() }
    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isActive: Bool { assertion != nil }

    /// Hides the apps whose icons are all left of `boundary` (a screen x coordinate).
    func hide(leftOf boundary: CGFloat, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let icons = Self.menuBarIcons()
            // Hide only apps whose icons are all left of the boundary; an app with icons on both
            // sides stays. Every other running app is allowed too, so icons that couldn't be read
            // never disappear by accident.
            let visible = Set(icons.filter { $0.minX >= boundary }.map(\.bundleID))
            let hidden = Set(icons.map(\.bundleID)).subtracting(visible)
            var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).subtracting(hidden)
            allowed.insert(Bundle.main.bundleIdentifier ?? "com.kuzminyo.hido")

            DispatchQueue.main.async {
                guard !hidden.isEmpty else { return completion(true) }
                HidoMenuBarVisibilityActivate(Self.systemItemsToKeep, Array(allowed)) { [weak self] assertion, error in
                    if let error { NSLog("Hido: native hiding failed: %@", error.localizedDescription) }
                    self?.assertion = assertion as AnyObject?
                    completion(assertion != nil)
                }
            }
        }
    }

    func show() {
        guard let assertion else { return }
        HidoMenuBarVisibilityInvalidate(assertion)
        self.assertion = nil
    }

    /// Status icons of other apps with their left edge on screen, read through Accessibility.
    private static func menuBarIcons() -> [(bundleID: String, minX: CGFloat)] {
        var icons: [(String, CGFloat)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, app.processIdentifier != getpid() else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // Don't let one frozen app stall the whole read.
            AXUIElementSetMessagingTimeout(element, 0.25)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let items = children as? [AXUIElement] else { continue }
            for item in items {
                var value: CFTypeRef?
                var position = CGPoint.zero
                guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &value) == .success,
                      let value, AXValueGetValue(value as! AXValue, .cgPoint, &position) else { continue }
                icons.append((bundleID, position.x))
            }
        }
        return icons
    }
}
