import AppKit
import ApplicationServices
import MenuPinCore

@MainActor
final class StatusBarEngine {
    let separator: NSStatusItem
    let launcher: NSStatusItem
    var expanded = true

    init(target: AnyObject, action: Selector) {
        // New items appear on the left. Create the launcher first, then its separator.
        launcher = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        launcher.autosaveName = "MenuPin.launcher"
        launcher.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MenuPin 菜单栏管理")
        launcher.button?.toolTip = "MenuPin · 左键管理，右键展开 / 收起"
        launcher.button?.target = target
        launcher.button?.action = action
        launcher.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        separator = NSStatusBar.system.statusItem(withLength: 18)
        separator.autosaveName = "MenuPin.separator"
        separator.button?.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "收起区分隔线")
        separator.button?.toolTip = "左侧为收起区，右侧为固定区。按住 ⌘ 拖动图标调整。"
        separator.button?.target = target
        separator.button?.action = action
        launcher.isVisible = true
        separator.isVisible = true
    }

    var dividerFrame: CGRect? { frame(of: separator) }
    var launcherFrame: CGRect? { frame(of: launcher) }

    private func frame(of item: NSStatusItem) -> CGRect? {
        guard let button = item.button, let window = button.window,
              let primary = NSScreen.screens.first else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return MenuGeometry.quartzRect(rect, primaryHeight: primary.frame.height)
    }

    var validOrder: Bool {
        guard let divider = dividerFrame, let manager = launcherFrame else { return false }
        return divider.maxX <= manager.minX + 2 && abs(divider.midY - manager.midY) < 20
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        separator.length = value ? 18 : MenuGeometry.collapsedLength(screenWidths: NSScreen.screens.map { $0.frame.width })
        separator.button?.image = NSImage(systemSymbolName: value ? "line.3.horizontal.decrease" : "chevron.right", accessibilityDescription: "收起区分隔线")
    }

    func shutdown() {
        setExpanded(true)
        NSStatusBar.system.removeStatusItem(separator)
        NSStatusBar.system.removeStatusItem(launcher)
    }

    func isVisibleOutsideNotch(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let rect = CGRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }) else { return false }
        if let right = screen.auxiliaryTopRightArea {
            return right.contains(rect) || (screen.auxiliaryTopLeftArea?.contains(rect) ?? false)
        }
        return true
    }

    func isOnManagedScreen(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first, let dividerFrame else { return false }
        let screens = NSScreen.screens.map { MenuGeometry.quartzRect($0.frame, primaryHeight: primary.frame.height) }
        guard let screen = MenuGeometry.screenIndex(for: dividerFrame, screenFrames: screens, trailingEdge: true) else { return false }
        return MenuGeometry.screenIndex(for: frame, screenFrames: screens) == screen
    }

    static func pause(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    static func drag(from start: CGPoint, to end: CGPoint) async -> Bool {
        guard Accessibility.trusted, CGEventSource.buttonState(.combinedSessionState, button: .left) == false,
              let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let oldMouse = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) else { return false }
        down.flags = .maskCommand
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.flags = .maskCommand
        defer {
            // Always release even if the task is cancelled mid-drag.
            up.post(tap: .cghidEventTap)
            if let point = oldMouse {
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
        down.post(tap: .cghidEventTap)
        await pause(100)
        for step in 1...16 {
            if Task.isCancelled { return false }
            let t = CGFloat(step) / 16
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
            await pause(18)
        }
        return true
    }

    static func click(_ point: CGPoint, right: Bool = false) -> Bool {
        guard Accessibility.trusted, let source = CGEventSource(stateID: .combinedSessionState),
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return false }
        let button: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseDown : .leftMouseDown, mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: right ? .rightMouseUp : .leftMouseUp, mouseCursorPosition: point, mouseButton: button) else { return false }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
