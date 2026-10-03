import Foundation
import CoreGraphics

public enum ItemSection: String, Codable {
    case pinned, hidden, unknown
}

public enum MenuGeometry {
    public static func screenIndex(for rect: CGRect, screenFrames: [CGRect], trailingEdge: Bool = false) -> Int? {
        let x = trailingEdge ? rect.maxX - 1 : rect.midX
        let candidates = screenFrames.indices.filter { abs(rect.minY - screenFrames[$0].minY) <= 8 }
        if let visible = candidates.first(where: { x >= screenFrames[$0].minX && x < screenFrames[$0].maxX }) { return visible }
        return candidates.count == 1 ? candidates.first : nil
    }

    public static func section(item: CGRect, divider: CGRect, screenFrames: [CGRect]) -> ItemSection {
        guard let screen = screenIndex(for: divider, screenFrames: screenFrames, trailingEdge: true),
              screenIndex(for: item, screenFrames: screenFrames) == screen else { return .unknown }
        return section(item: item, divider: divider)
    }

    public static func section(item: CGRect, divider: CGRect) -> ItemSection {
        guard item.minX.isFinite, item.minY.isFinite, item.width.isFinite, item.height.isFinite,
              divider.minX.isFinite, divider.minY.isFinite, divider.width.isFinite, divider.height.isFinite,
              item.width > 0, divider.width > 0,
              abs(item.midY - divider.midY) < max(item.height, divider.height) else { return .unknown }
        if item.minX >= divider.maxX - 1 { return .pinned }
        if item.maxX <= divider.minX + 1 { return .hidden }
        return .unknown
    }

    public static func quartzRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func isMenuBarFrame(_ rect: CGRect, screenFrames: [CGRect]) -> Bool {
        guard rect.width >= 5, rect.width <= 280, rect.height >= 12, rect.height <= 50,
              rect.minX.isFinite, rect.minY.isFinite else { return false }
        return screenFrames.contains { abs(rect.minY - $0.minY) <= 8 }
    }

    public static func isStatusFrame(_ rect: CGRect, screenFrames: [CGRect]) -> Bool {
        isMenuBarFrame(rect, screenFrames: screenFrames) && screenFrames.contains { screen in
            abs(rect.minY - screen.minY) <= 8 && rect.maxX > screen.minX && rect.minX < screen.maxX
        }
    }

    public static func collapsedLength(screenWidths: [CGFloat]) -> CGFloat {
        max(500, min((screenWidths.max() ?? 1440) * 2, 10_000))
    }
}

public enum ItemIdentity {
    public static func windowKey(pid: Int32, windowID: UInt32) -> String { "session:\(pid)|window:\(windowID)" }
    public static func canPersist(_ id: String) -> Bool { id.contains("|ax:") }
    public static func key(bundleID: String, identifier: String, title: String, ordinal: Int) -> String {
        // AXIdentifier is preferred; title can contain a changing percentage or counter.
        let component = identifier.isEmpty ? "slot:\(ordinal)" : "ax:\(identifier)"
        return "\(bundleID)|\(component)"
    }

    public static func matches(query: String, title: String, appName: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(title) \(appName)".localizedCaseInsensitiveContains(query)
    }
}


public enum MenuMoveDirection: Int { case left = -1, right = 1 }

public struct MenuListMove: Equatable {
    public let itemID: String
    public let targetID: String
    public let before: Bool
    public let orderedIDs: [String]
}

public enum MenuOrder {
    public static func listMove(_ ids: [String], fromOffsets: IndexSet, toOffset: Int) -> MenuListMove? {
        guard fromOffsets.count == 1, let source = fromOffsets.first, ids.indices.contains(source),
              toOffset >= 0, toOffset <= ids.count, Set(ids).count == ids.count else { return nil }
        let itemID = ids[source]
        var remaining = ids
        remaining.remove(at: source)
        let insertion = toOffset - (source < toOffset ? 1 : 0)
        var ordered = remaining
        ordered.insert(itemID, at: insertion)
        guard ordered != ids, !remaining.isEmpty else { return nil }
        let before = insertion < remaining.count
        let target = before ? remaining[insertion] : remaining[remaining.count - 1]
        return MenuListMove(itemID: itemID, targetID: target, before: before, orderedIDs: ordered)
    }

    public static func neighbor(of id: String, in orderedIDs: [String], direction: MenuMoveDirection) -> String? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        let destination = index + direction.rawValue
        return orderedIDs.indices.contains(destination) ? orderedIDs[destination] : nil
    }

    public static func reordered(_ ids: [String], moving source: String, before target: String) -> [String] {
        reordered(ids, moving: source, relativeTo: target, before: true)
    }

    public static func reordered(_ ids: [String], moving source: String, relativeTo target: String, before: Bool) -> [String] {
        guard source != target, ids.contains(source), ids.contains(target) else { return ids }
        var result = ids.filter { $0 != source }
        guard let index = result.firstIndex(of: target) else { return ids }
        result.insert(source, at: before ? index : index + 1)
        return result
    }
}

public enum MenuOpeningPolicy: Equatable {
    case accessibilityOnly, accessibilityThenClick
    public static func forSection(_ section: ItemSection) -> MenuOpeningPolicy {
        section == .pinned ? .accessibilityThenClick : .accessibilityOnly
    }
}
