import AppKit
import ApplicationServices
import MenuPinCore

struct BarItem: Identifiable {
    var id: String
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    var frame: CGRect
    var element: AXUIElement?
    var windowID: CGWindowID?
    var section: ItemSection = .unknown
    var symbol: String? = nil

    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
    var isSystem: Bool { bundleID == "com.apple.controlcenter" || bundleID == "com.apple.systemuiserver" }

    func matches(_ reference: BarItem) -> Bool {
        guard pid == reference.pid else { return false }
        if let windowID, let other = reference.windowID { return windowID == other }
        if let element, let other = reference.element { return CFEqual(element, other) }
        return ItemIdentity.canPersist(id) && id == reference.id
    }
}

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum BarScanner {
    static func scan(apps: [NSRunningApplication], screenFrames: [CGRect], ownPID: pid_t, preferredDivider: CGRect?) -> [BarItem] {
        guard Accessibility.trusted else { return [] }
        var items: [BarItem] = []
        for app in apps where app.processIdentifier != ownPID && !app.isTerminated {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.15)
            guard let extra = Accessibility.value(application, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(extra) == AXUIElementGetTypeID() else { continue }
            let menuBar = extra as! AXUIElement
            let children = Accessibility.value(menuBar, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for (ordinal, child) in children.enumerated() {
                let role = Accessibility.string(child, kAXRoleAttribute)
                guard role == kAXMenuBarItemRole || role == kAXButtonRole,
                      let frame = Accessibility.frame(child),
                      MenuGeometry.isMenuBarFrame(frame, screenFrames: screenFrames) else { continue }
                let appName = app.localizedName ?? app.bundleIdentifier ?? "菜单栏项目"
                let rawTitle = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                    .map { Accessibility.string(child, $0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? ""
                let title = rawTitle.isEmpty ? appName : String(rawTitle.prefix(100))
                let bundle = app.bundleIdentifier ?? "process:\(appName)"
                let identifier = Accessibility.string(child, kAXIdentifierAttribute)
                let id = ItemIdentity.key(bundleID: bundle, identifier: identifier, title: title, ordinal: ordinal)
                items.append(BarItem(id: id, pid: app.processIdentifier, bundleID: bundle, appName: appName, title: title, frame: frame, element: child))
            }
        }

        // Include offscreen status windows so opening the panel does not require expanding the bar.
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows.sorted(by: { ($0[kCGWindowNumber as String] as? Int ?? 0) < ($1[kCGWindowNumber as String] as? Int ?? 0) }) {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary),
                  MenuGeometry.isMenuBarFrame(frame, screenFrames: screenFrames),
                  let app = NSRunningApplication(processIdentifier: pid) else { continue }
            if let index = items.firstIndex(where: { $0.pid == pid && abs($0.frame.midX - frame.midX) < 8 && abs($0.frame.midY - frame.midY) < 8 }) {
                items[index].windowID = window[kCGWindowNumber as String] as? CGWindowID
                if !ItemIdentity.canPersist(items[index].id), let windowID = items[index].windowID {
                    items[index].id = ItemIdentity.windowKey(pid: pid, windowID: windowID)
                }
                continue
            }
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            let appName = app.localizedName ?? "菜单栏项目"
            let bundle = app.bundleIdentifier ?? "process:\(appName)"
            let title = window[kCGWindowName as String] as? String ?? ""
            items.append(BarItem(id: ItemIdentity.windowKey(pid: pid, windowID: windowID), pid: pid, bundleID: bundle, appName: appName,
                                 title: title.isEmpty ? appName : title, frame: frame, windowID: windowID))
        }
        // Deduplicate mirrored identities, then present physical order from left to right.
        var seen: Set<String> = []
        return items.sorted { left, right in
            if let preferredDivider {
                let a = MenuGeometry.section(item: left.frame, divider: preferredDivider, screenFrames: screenFrames) != .unknown
                let b = MenuGeometry.section(item: right.frame, divider: preferredDivider, screenFrames: screenFrames) != .unknown
                if a != b { return a }
            }
            return left.frame.minX > right.frame.minX
        }.filter { seen.insert($0.id).inserted }.sorted { $0.frame.minX < $1.frame.minX }
    }
}
