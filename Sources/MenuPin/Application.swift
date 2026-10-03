import AppKit
import SwiftUI
import ApplicationServices

@main
enum MenuPinApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var model: AppModel!
    private var engine: StatusBarEngine?
    private let popover = NSPopover()
    private var demoWindow: NSWindow?
    private var monitors: [Any] = []
    private var permissionTimer: Timer?
    private var hideTimer: Timer?
    private var restoreCollapsed = false
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let demo = args.contains("--demo") || args.contains("--render")
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出 MenuPin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
        model = AppModel(demo: demo)
        model.closePanel = { [weak self] in self?.closePanel() }
        model.dismissForAction = { [weak self] in
            self?.restoreCollapsed = false
            self?.hideTimer?.invalidate()
            self?.popover.performClose(nil)
        }
        if demo {
            showDemo()
            if let index = args.firstIndex(of: "--render"), args.indices.contains(index + 1) {
                let path = args[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.render(to: path) }
            }
            return
        }
        engine = StatusBarEngine(target: self, action: #selector(statusClicked(_:)))
        model.engine = engine
        let hosting = NSHostingController(rootView: PanelView(model: model))
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.busy else { return }
                self.closePanel()
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, self.popover.isShown, !self.model.busy,
                  event.window !== self.popover.contentViewController?.view.window,
                  event.window !== self.engine?.launcher.button?.window,
                  event.window !== self.engine?.separator.button?.window else { return event }
            self.closePanel()
            return event
        }) { monitors.append(local) }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let permission = Accessibility.trusted
                if permission != self.model.trusted {
                    self.model.trusted = permission
                    if permission { self.model.refresh() }
                    else { self.model.items = [] }
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.popover.isShown else { return }
                    self.model.refresh()
                }
            })
        }
        if let index = args.firstIndex(of: "--diagnose"), args.indices.contains(index + 1) {
            let path = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.diagnose(to: path) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPanel() }
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        hideTimer?.invalidate()
        let isSeparator = sender === engine?.separator.button
        if NSApp.currentEvent?.type == .rightMouseUp || isSeparator {
            if popover.isShown { restoreCollapsed = false; popover.performClose(nil) }
            model.setExpanded(!model.expanded)
        } else if popover.isShown { closePanel() }
        else { showPanel() }
    }

    private func showPanel() {
        guard let button = engine?.launcher.button, !model.busy else { return }
        hideTimer?.invalidate()
        restoreCollapsed = !model.expanded
        // Preserve the collapsed bar while the independent management panel is open.
        model.orderValid = engine?.validOrder ?? true
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Task { await StatusBarEngine.pause(250); await model.scan() }
    }

    private func closePanel() {
        if model.demo { demoWindow?.close(); return }
        guard popover.isShown, !model.busy else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard !model.busy else { return }
        if restoreCollapsed { model.setExpanded(false); restoreCollapsed = false }
        else if model.autoCollapse { scheduleCollapse() }
    }

    private func scheduleCollapse() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.popover.isShown, !self.model.busy, self.model.autoCollapse else { return }
                let point = NSEvent.mouseLocation
                let inBar = NSScreen.screens.contains { screen in
                    point.x >= screen.frame.minX && point.x <= screen.frame.maxX && point.y >= screen.frame.maxY - 40 && point.y <= screen.frame.maxY
                }
                if inBar || NSEvent.pressedMouseButtons != 0 { self.scheduleCollapse(); return }
                self.model.setExpanded(false)
            }
        }
    }

    @objc private func screenChanged() {
        if let engine { engine.setExpanded(engine.expanded) }
        if popover.isShown { model.refresh() }
    }

    private func showDemo() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MenuPin · 交互演示"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PanelView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        demoWindow = window
    }

    private func render(to path: String) {
        guard let view = demoWindow?.contentView else { NSApp.terminate(nil); return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("Rendered \(path)")
        } catch { fputs("Render failed: \(error)\n", stderr) }
        NSApp.terminate(nil)
    }

    private func diagnose(to path: String) {
        Task {
            await model.scan()
            let data: [String: Any] = [
                "version": "1.2", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "accessibility": Accessibility.trusted, "expanded": engine?.expanded ?? false,
                "dividerOrderValid": engine?.validOrder ?? false,
                "dividerFrame": engine?.dividerFrame.map { NSStringFromRect($0) } ?? "unavailable",
                "launcherFrame": engine?.launcherFrame.map { NSStringFromRect($0) } ?? "unavailable",
                "itemCount": model.items.count,
                "items": model.items.map { ["title": $0.title, "section": $0.section.rawValue, "frame": NSStringFromRect($0.frame), "ax": $0.element != nil] as [String: Any] }
            ]
            do { try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path)) }
            catch { fputs("Diagnostics failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hideTimer?.invalidate()
        permissionTimer?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        NotificationCenter.default.removeObserver(self)
        engine?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { model?.demo == true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model?.demo == true { demoWindow?.makeKeyAndOrderFront(nil) }
        else { showPanel() }
        return false
    }
}
