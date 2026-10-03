import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement
import MenuPinCore

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [BarItem] = []
    @Published var query = ""
    @Published var trusted = Accessibility.trusted
    @Published var busy = false
    @Published var scanning = false
    @Published var expanded = true
    @Published var orderValid = true
    @Published var message: String?
    @Published var settings = false
    @Published var autoCollapse: Bool {
        didSet { if !demo { UserDefaults.standard.set(autoCollapse, forKey: "autoCollapse") } }
    }
    @Published var loginEnabled = false
    let demo: Bool
    var engine: StatusBarEngine?
    var dismissForAction: (() -> Void)?
    var closePanel: (() -> Void)?
    private var preferredPins: [String: Bool]
    private var preferredOrders: [String: [String]]
    private var scanGeneration = 0
    @Published private var pendingOrder: [String]?
    var applyingOrder: Bool { pendingOrder != nil }
    private let reorderAnimation = Animation.spring(response: 0.28, dampingFraction: 0.88)

    init(demo: Bool = false) {
        self.demo = demo
        autoCollapse = demo ? true : UserDefaults.standard.bool(forKey: "autoCollapse")
        preferredPins = demo ? [:] : (UserDefaults.standard.dictionary(forKey: "preferredPins") as? [String: Bool] ?? [:])
        preferredOrders = demo ? [:] : (UserDefaults.standard.dictionary(forKey: "preferredOrders") as? [String: [String]] ?? [:])
        loginEnabled = SMAppService.mainApp.status == .enabled
        if demo {
            trusted = true
            items = [
                demoItem("微信", "WeChat", "message.fill", .pinned),
                demoItem("网络代理", "Clash Verge", "network", .pinned),
                demoItem("声音", "系统项目", "speaker.wave.2.fill", .pinned),
                demoItem("Docker Desktop", "Docker", "shippingbox.fill", .hidden),
                demoItem("截图工具", "Shottr", "viewfinder", .hidden)
            ]
        }
    }

    private func demoItem(_ title: String, _ app: String, _ symbol: String, _ section: ItemSection) -> BarItem {
        BarItem(id: title, pid: -1, bundleID: "demo", appName: app, title: title,
                frame: CGRect(x: 0, y: 0, width: 24, height: 24), section: section, symbol: symbol)
    }

    private var displayItems: [BarItem] {
        guard let pendingOrder else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let requested = Set(pendingOrder)
        return pendingOrder.compactMap { lookup[$0] } + items.filter { !requested.contains($0.id) }
    }

    var filtered: [BarItem] {
        displayItems.filter { ItemIdentity.matches(query: query, title: $0.title, appName: $0.appName) }
    }
    var pinned: [BarItem] { filtered.filter { $0.section == .pinned } }
    var hidden: [BarItem] { filtered.filter { $0.section == .hidden } }
    var unknown: [BarItem] { filtered.filter { $0.section == .unknown } }

    func refresh() {
        guard !busy, !demo else { return }
        Task { await scan() }
    }

    func scan() async {
        guard !demo else { return }
        trusted = Accessibility.trusted
        guard trusted else { items = []; scanning = false; return }
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
        let apps = NSWorkspace.shared.runningApplications
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screens = NSScreen.screens.map { MenuGeometry.quartzRect($0.frame, primaryHeight: primaryHeight) }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let preferredDivider = engine?.dividerFrame
        let result: [BarItem] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: BarScanner.scan(apps: apps, screenFrames: screens, ownPID: ownPID, preferredDivider: preferredDivider))
            }
        }
        guard generation == scanGeneration else { return }
        orderValid = engine?.validOrder ?? false
        let divider = engine?.dividerFrame
        items = result.map { item in
            var item = item
            item.section = divider.map { MenuGeometry.section(item: item.frame, divider: $0, screenFrames: screens) } ?? .unknown
            return item
        }
        scanning = false
    }

    func setExpanded(_ value: Bool) {
        guard !busy else { return }
        if demo { expanded = value; return }
        guard let engine else { return }
        if !value && !engine.validOrder {
            message = "请按住 ⌘，把分隔图标拖到 MenuPin 图标左边，再收起。"
            orderValid = false
            return
        }
        engine.setExpanded(value)
        expanded = value
        if value { Task { await StatusBarEngine.pause(250); await scan() } }
    }

    func togglePin(_ item: BarItem) {
        guard !busy else { return }
        if demo {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].section = item.section == .pinned ? .hidden : .pinned
            }
            return
        }
        guard Accessibility.trusted else { message = "请先开启辅助功能权限。"; return }
        guard engine?.validOrder == true else { message = "请先把分隔图标拖到 MenuPin 左边。"; return }
        let pin = item.section != .pinned
        let restoreExpanded = pin && (engine?.expanded ?? true)
        busy = true
        message = nil
        Task {
            defer {
                busy = false
                engine?.setExpanded(restoreExpanded)
                expanded = restoreExpanded
            }
            let success = await move(reference: item, pinned: pin)
            if success {
                if ItemIdentity.canPersist(item.id) { preferredPins[item.id] = pin }
                UserDefaults.standard.set(preferredPins, forKey: "preferredPins")
                saveOrder()
            }
        }
    }

    private func move(reference: BarItem, pinned: Bool) async -> Bool {
        guard let engine else { return false }
        engine.setExpanded(true)
        expanded = true
        await StatusBarEngine.pause(180)
        await scan()
        guard let current = items.first(where: { $0.matches(reference) }), let divider = engine.dividerFrame,
              engine.validOrder, current.section != .unknown else {
            message = "没有找到项目的可操作位置。请刷新，或按住 ⌘ 手动拖动。"
            return false
        }
        if current.section == (pinned ? .pinned : .hidden) { return true }
        guard abs(current.frame.midY - divider.midY) < 20 else {
            message = "项目位于另一个屏幕，请在同一屏幕的菜单栏调整。"
            return false
        }
        guard engine.isVisibleOutsideNotch(current.frame), engine.isOnManagedScreen(current.frame) else {
            message = "项目当前位于刘海或屏幕可见区之外，无法安全拖动。请减少固定项目或在外接屏调整。"
            return false
        }
        let destination = CGPoint(x: pinned ? divider.maxX + max(current.frame.width / 2, 14) : divider.minX - max(current.frame.width / 2, 14), y: divider.midY)
        guard engine.isVisibleOutsideNotch(CGRect(x: destination.x - current.frame.width / 2, y: current.frame.minY, width: current.frame.width, height: current.frame.height)),
              await StatusBarEngine.drag(from: CGPoint(x: current.frame.midX, y: current.frame.midY), to: destination) else {
            message = "系统未接受拖动。请检查辅助功能权限，并松开鼠标后重试。"
            return false
        }
        for _ in 0..<3 {
            await StatusBarEngine.pause(300)
            await scan()
            if let moved = items.first(where: { $0.matches(current) }), moved.section == (pinned ? .pinned : .hidden) { return true }
        }
        message = "“\(current.title)”未移动到目标区域。此项目可能不允许移动；可按住 ⌘ 手动尝试。"
        return false
    }

    func canMove(_ item: BarItem, direction: MenuMoveDirection) -> Bool {
        guard item.section != .unknown else { return false }
        let ids = items.filter { $0.section == item.section }.map(\.id)
        return MenuOrder.neighbor(of: item.id, in: ids, direction: direction) != nil
    }

    func moveOne(_ item: BarItem, direction: MenuMoveDirection) {
        let ids = items.filter { $0.section == item.section }.map(\.id)
        guard let targetID = MenuOrder.neighbor(of: item.id, in: ids, direction: direction),
              let target = items.first(where: { $0.id == targetID }) else { return }
        reorder(reference: item, targetReference: target, before: direction == .left)
    }

    func canListMove(_ item: BarItem) -> Bool {
        !busy && !scanning && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        item.section != .unknown && (demo || item.windowID != nil || ItemIdentity.canPersist(item.id))
    }

    func moveListItems(snapshot: [BarItem], fromOffsets: IndexSet, toOffset: Int) {
        guard let section = snapshot.first?.section, section != .unknown,
              snapshot.allSatisfy({ $0.section == section }) else { return }
        guard snapshot.map(\.id) == items.filter({ $0.section == section }).map(\.id) else {
            message = "列表已变化，请重新拖动。"
            return
        }
        guard let move = MenuOrder.listMove(snapshot.map(\.id), fromOffsets: fromOffsets, toOffset: toOffset),
              let source = snapshot.first(where: { $0.id == move.itemID }),
              let target = snapshot.first(where: { $0.id == move.targetID }), canListMove(source) else { return }
        guard canListMove(target) else {
            message = "目标项目暂时无法可靠定位，请选另一个落点，或用更多菜单中的左右移动。"
            return
        }
        reorder(reference: source, targetReference: target, before: move.before)
    }

    private func reorder(reference: BarItem, targetReference: BarItem, before: Bool) {
        let itemID = reference.id, targetID = targetReference.id
        guard !busy, itemID != targetID,
              let source = items.first(where: { demo ? $0.id == itemID : $0.matches(reference) }),
              let target = items.first(where: { demo ? $0.id == targetID : $0.matches(targetReference) }),
              source.section == target.section, source.section != .unknown else {
            message = "排序请在同一分组内拖动；切换固定 / 收起请使用图钉。"
            return
        }
        if demo {
            let ids = MenuOrder.reordered(items.map(\.id), moving: itemID, relativeTo: targetID, before: before)
            let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            withAnimation(reorderAnimation) { items = ids.compactMap { lookup[$0] } }
            return
        }
        guard Accessibility.trusted else { message = "请先开启辅助功能权限。"; return }
        let requested = MenuOrder.reordered(items.map(\.id), moving: source.id, relativeTo: target.id, before: before)
        guard requested != items.map(\.id) else { return }
        let wasExpanded = expanded
        message = nil
        busy = true
        withAnimation(reorderAnimation) { pendingOrder = requested }
        Task {
            defer {
                engine?.setExpanded(wasExpanded)
                expanded = wasExpanded
                withAnimation(reorderAnimation) { pendingOrder = nil; busy = false }
            }
            if await moveRelative(reference: source, targetReference: target, before: before) { saveOrder() }
        }
    }

    private func moveRelative(reference sourceReference: BarItem, targetReference: BarItem, before: Bool) async -> Bool {
        guard let engine else { return false }
        engine.setExpanded(true)
        expanded = true
        await StatusBarEngine.pause(180)
        await scan()
        guard let source = items.first(where: { $0.matches(sourceReference) }),
              let target = items.first(where: { $0.matches(targetReference) }),
              engine.validOrder,
              source.section == target.section, source.section != .unknown,
              abs(source.frame.midY - target.frame.midY) < 20,
              engine.isVisibleOutsideNotch(source.frame), engine.isVisibleOutsideNotch(target.frame),
              engine.isOnManagedScreen(source.frame), engine.isOnManagedScreen(target.frame) else {
            message = "项目不可见、位于刘海后方或不在同一分组，未执行拖动。"
            return false
        }
        let initialOrder = items.filter { $0.section == source.section }.map(\.id)
        let expectedOrder = MenuOrder.reordered(initialOrder, moving: source.id, relativeTo: target.id, before: before)
        if expectedOrder == initialOrder { return true }
        let destination = CGPoint(x: before ? target.frame.minX + 1 : target.frame.maxX - 1, y: target.frame.midY)
        guard await StatusBarEngine.drag(from: CGPoint(x: source.frame.midX, y: source.frame.midY), to: destination) else {
            message = "系统未接受排序拖动，请检查权限后重试。"
            return false
        }
        for _ in 0..<3 {
            await StatusBarEngine.pause(300)
            await scan()
            if let moved = items.first(where: { $0.matches(source) }),
               let anchor = items.first(where: { $0.matches(target) }),
               moved.section == source.section,
               anchor.section == source.section,
               items.filter({ $0.section == source.section }).map(\.id) == expectedOrder { return true }
        }
        message = "系统没有将“\(source.title)”移动到目标顺序；此项目可能不允许移动。"
        return false
    }

    private func saveOrder() {
        guard !demo else { return }
        preferredOrders = Dictionary(uniqueKeysWithValues: [ItemSection.pinned, .hidden].map { section in
            (section.rawValue, items.filter { $0.section == section && ItemIdentity.canPersist($0.id) }.map(\.id))
        })
        UserDefaults.standard.set(preferredOrders, forKey: "preferredOrders")
    }

    func openOriginal(_ item: BarItem, right: Bool = false) {
        guard !busy else { return }
        if demo { message = "演示模式：尝试在保持菜单栏收起的状态下打开“\(item.title)”的原菜单。"; return }
        guard Accessibility.trusted else { message = "请先开启辅助功能权限。"; return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            // Do not expand or move an unpinned item just to open its menu.
            await scan()
            guard let current = items.first(where: { $0.matches(item) }) else {
                message = "项目已退出或暂时无法识别。请刷新后重试。"
                return
            }
            let action = right ? kAXShowMenuAction : kAXPressAction
            if let element = current.element {
                var names: CFArray?
                let available = AXUIElementCopyActionNames(element, &names) == .success ? names as? [String] ?? [] : []
                if available.contains(action), AXUIElementPerformAction(element, action as CFString) == .success {
                    dismissForAction?()
                    return
                }
            }
            if MenuOpeningPolicy.forSection(current.section) == .accessibilityOnly {
                message = "“\(current.title)”不支持在隐藏状态下直接打开原菜单。你可以手动展开后再打开；MenuPin 不会自动展开整排图标。"
                return
            }
            let frame = current.element.flatMap({ Accessibility.frame($0) }) ?? current.frame
            guard engine?.isVisibleOutsideNotch(frame) == true, engine?.isOnManagedScreen(frame) == true else {
                message = "图标位于刘海或可见区之外，无法点击。可调整固定项目数量。"
                return
            }
            dismissForAction?()
            await StatusBarEngine.pause(120)
            if !StatusBarEngine.click(CGPoint(x: frame.midX, y: frame.midY), right: right) {
                message = "系统未接受点击。请检查辅助功能权限后重试。"
            }
        }
    }

    func restoreLayout() {
        guard !demo, !busy, Accessibility.trusted else { return }
        let wasExpanded = expanded
        busy = true
        message = nil
        Task {
            defer { busy = false; engine?.setExpanded(wasExpanded); expanded = wasExpanded }
            engine?.setExpanded(true)
            expanded = true
            await StatusBarEngine.pause(200)
            await scan()
            let desired = items.compactMap { item -> (String, Bool)? in
                guard ItemIdentity.canPersist(item.id), let pin = preferredPins[item.id], (item.section == .pinned) != pin else { return nil }
                return (item.id, pin)
            }
            for (id, pin) in desired {
                guard let reference = items.first(where: { $0.id == id }), await move(reference: reference, pinned: pin) else { return }
            }
            for section in [ItemSection.pinned, .hidden] {
                let order = (preferredOrders[section.rawValue] ?? []).filter { id in ItemIdentity.canPersist(id) && items.contains { $0.id == id && $0.section == section } }
                if order.count > 1 {
                    for index in (0..<(order.count - 1)).reversed() {
                        guard let source = items.first(where: { $0.id == order[index] }),
                              let target = items.first(where: { $0.id == order[index + 1] }),
                              await moveRelative(reference: source, targetReference: target, before: true) else { return }
                    }
                }
            }
            message = "已恢复保存的图钉选择和左右顺序。"
        }
    }

    func setLogin(_ value: Bool) {
        if demo { loginEnabled = value; return }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if value && !loginEnabled { message = "请在系统设置 → 通用 → 登录项中允许 MenuPin。" }
        } catch { message = "登录项设置失败：\(error.localizedDescription)" }
    }
}
