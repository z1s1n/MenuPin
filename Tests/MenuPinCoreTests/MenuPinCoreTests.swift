import Foundation
import CoreGraphics
import Darwin
import MenuPinCore

// Standalone runner: works with Command Line Tools, without an XCTest installation.
@main
struct CoreTests {
    static var failures = 0
    static var assertions = 0
    static var count = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ description: String, line: Int = #line) {
        assertions += 1
        if !condition() { failures += 1; print("FAIL line \(line): \(description)") }
    }

    static func test(_ name: String, _ body: () -> Void) {
        count += 1
        let previous = failures
        body()
        print("\(failures == previous ? "PASS" : "FAIL"): \(name)")
    }

    static func main() {
        test("图钉区域判定，包括重叠和异屏") {
            let divider = CGRect(x: 600, y: 0, width: 20, height: 24)
            expect(MenuGeometry.section(item: CGRect(x: 640, y: 0, width: 24, height: 24), divider: divider) == .pinned, "右侧固定")
            expect(MenuGeometry.section(item: CGRect(x: 560, y: 0, width: 24, height: 24), divider: divider) == .hidden, "左侧收起")
            expect(MenuGeometry.section(item: CGRect(x: 610, y: 0, width: 24, height: 24), divider: divider) == .unknown, "重叠不应声称已固定")
            expect(MenuGeometry.section(item: CGRect(x: 640, y: 900, width: 24, height: 24), divider: divider) == .unknown, "异屏不应分类到当前分隔区")
        }
        test("跨屏 AppKit → Quartz 坐标转换") {
            expect(MenuGeometry.quartzRect(CGRect(x: 100, y: 876, width: 24, height: 24), primaryHeight: 900) == CGRect(x: 100, y: 0, width: 24, height: 24), "主屏转换")
            expect(MenuGeometry.quartzRect(CGRect(x: -1200, y: 1176, width: 24, height: 24), primaryHeight: 900) == CGRect(x: -1200, y: -300, width: 24, height: 24), "左上方副屏转换")
        }
        test("窗口过滤避免点击普通窗口和菜单弹窗") {
            let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -300, width: 1920, height: 1200)]
            expect(MenuGeometry.isStatusFrame(CGRect(x: 1000, y: 0, width: 24, height: 24), screenFrames: screens), "主屏图标")
            expect(MenuGeometry.isStatusFrame(CGRect(x: -500, y: -300, width: 24, height: 24), screenFrames: screens), "副屏图标")
            expect(!MenuGeometry.isStatusFrame(CGRect(x: 1000, y: 200, width: 24, height: 24), screenFrames: screens), "普通窗口拒绝")
            expect(!MenuGeometry.isStatusFrame(CGRect(x: 0, y: 0, width: 1440, height: 24), screenFrames: screens), "整个菜单栏拒绝")
            expect(!MenuGeometry.isStatusFrame(.zero, screenFrames: screens), "零尺寸拒绝")
        }
        test("稳定标识不随进程重启和百分比文本变化") {
            expect(ItemIdentity.key(bundleID: "test.app", identifier: "item.one", title: "Battery 80%", ordinal: 0) == ItemIdentity.key(bundleID: "test.app", identifier: "item.one", title: "Battery 75%", ordinal: 4), "优先采用 AXIdentifier")
            expect(ItemIdentity.key(bundleID: "test.app", identifier: "one", title: "", ordinal: 0) != ItemIdentity.key(bundleID: "test.app", identifier: "two", title: "", ordinal: 0), "不同 AX 项目分开")
            expect(ItemIdentity.key(bundleID: "test.app", identifier: "", title: "", ordinal: 0) != ItemIdentity.key(bundleID: "test.app", identifier: "", title: "", ordinal: 1), "未提供标识时序号区分")
        }
        test("中英文搜索及首尾空白") {
            expect(ItemIdentity.matches(query: "微信", title: "微信", appName: "WeChat"), "中文名称")
            expect(ItemIdentity.matches(query: " chat ", title: "微信", appName: "WeChat"), "大小写和空白")
            expect(!ItemIdentity.matches(query: "不存在", title: "微信", appName: "WeChat"), "未匹配")
            expect(ItemIdentity.matches(query: "  ", title: "微信", appName: "WeChat"), "空搜索")
        }
        test("拒绝非法坐标，限制收起区宽度") {
            expect(MenuGeometry.section(item: CGRect(x: CGFloat.infinity, y: 0, width: 24, height: 24), divider: CGRect(x: 600, y: 0, width: 20, height: 24)) == .unknown, "无穷坐标不能用于拖动")
            expect(MenuGeometry.collapsedLength(screenWidths: [1440, 6000]) == 10000, "不超过系统宽度上限")
            expect(MenuGeometry.collapsedLength(screenWidths: [100]) == 500, "最小收起宽度")
            expect(MenuGeometry.collapsedLength(screenWidths: [1440, 1920]) == 3840, "使用最宽显示器")
        }
        test("左右排序边界和拖放顺序") {
            let ids = ["A", "B", "C"]
            expect(MenuOrder.neighbor(of: "B", in: ids, direction: .left) == "A", "左邻居")
            expect(MenuOrder.neighbor(of: "B", in: ids, direction: .right) == "C", "右邻居")
            expect(MenuOrder.neighbor(of: "A", in: ids, direction: .left) == nil, "最左边不再左移")
            expect(MenuOrder.neighbor(of: "C", in: ids, direction: .right) == nil, "最右边不再右移")
            expect(MenuOrder.neighbor(of: "missing", in: ids, direction: .left) == nil, "不存在的项目不能排序")
            expect(MenuOrder.reordered(ids, moving: "C", before: "A") == ["C", "A", "B"], "拖放到目标之前")
            expect(MenuOrder.reordered(ids, moving: "A", before: "A") == ids, "拖放自己保持不变")
            expect(MenuOrder.reordered(ids, moving: "missing", before: "A") == ids, "未知项目不能加入布局")
        }
        test("未固定项目禁止通过鼠标点击或展开主菜单栏兜底") {
            expect(MenuOpeningPolicy.forSection(.hidden) == .accessibilityOnly, "收起项目仅使用 AX")
            expect(MenuOpeningPolicy.forSection(.unknown) == .accessibilityOnly, "待定位项目不得点击旧坐标")
            expect(MenuOpeningPolicy.forSection(.pinned) == .accessibilityThenClick, "固定项目允许点击可见图标")
        }
        test("隐藏项目枚举保留屏幕外图标，但拒绝普通窗口") {
            let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
            expect(MenuGeometry.isMenuBarFrame(CGRect(x: -9000, y: 5, width: 24, height: 24), screenFrames: screens), "保留被收起区推到屏幕外的图标")
            expect(!MenuGeometry.isStatusFrame(CGRect(x: -9000, y: 5, width: 24, height: 24), screenFrames: screens), "普通可见区过滤仍然拒绝屏幕外")
            expect(!MenuGeometry.isMenuBarFrame(CGRect(x: 800, y: 300, width: 24, height: 24), screenFrames: screens), "普通窗口拒绝")
            expect(!MenuGeometry.isMenuBarFrame(CGRect(x: -9000, y: 5, width: 9000, height: 24), screenFrames: screens), "收起分隔符拒绝")
        }
        test("完整排序验证拒绝没有生效的拖动") {
            let ids = ["A", "B", "C"]
            let expected = MenuOrder.reordered(ids, moving: "A", relativeTo: "C", before: true)
            expect(expected == ["B", "A", "C"], "在左侧仍需移动到相邻目标前")
            expect(ids != expected, "系统忽略拖动不能当作成功")
            expect(MenuOrder.reordered(ids, moving: "A", relativeTo: "B", before: false) == ["B", "A", "C"], "向右移到目标之后")
            expect(MenuOrder.reordered(ids, moving: "B", relativeTo: "C", before: true) == ids, "已经相邻时无需拖动")
        }
        test("顶部对齐双屏和屏幕外归属") {
            let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
            let divider = CGRect(x: 800, y: 0, width: 20, height: 24)
            expect(MenuGeometry.section(item: CGRect(x: 900, y: 0, width: 24, height: 24), divider: divider, screenFrames: screens) == .pinned, "主屏固定区")
            expect(MenuGeometry.section(item: CGRect(x: 2200, y: 0, width: 24, height: 24), divider: divider, screenFrames: screens) == .unknown, "顶部对齐副屏拒绝")
            expect(MenuGeometry.section(item: CGRect(x: -9000, y: 0, width: 24, height: 24), divider: divider, screenFrames: screens) == .unknown, "多屏下屏幕外归属不明")
            expect(MenuGeometry.section(item: CGRect(x: -9000, y: 0, width: 24, height: 24), divider: CGRect(x: -8000, y: 0, width: 8820, height: 24), screenFrames: [screens[0]]) == .hidden, "单屏使用分隔符右端定位收起区")
        }
        test("会话窗口身份不得跨启动恢复") {
            expect(ItemIdentity.windowKey(pid: 10, windowID: 20) != ItemIdentity.windowKey(pid: 10, windowID: 21), "同应用不同窗口分开")
            expect(!ItemIdentity.canPersist(ItemIdentity.windowKey(pid: 10, windowID: 20)), "窗口 ID 只用于当前会话")
            expect(!ItemIdentity.canPersist("test.app|slot:0"), "无稳定 AX 标识不自动恢复")
            expect(ItemIdentity.canPersist("test.app|ax:status"), "稳定 AX 标识可以保存")
        }
        test("原生列表落点转换为真实菜单栏目标") {
            let ids = ["A", "B", "C", "D"]
            let down = MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 0), toOffset: 4)
            expect(down?.orderedIDs == ["B", "C", "D", "A"], "首项拖到末尾")
            expect(down?.itemID == "A" && down?.targetID == "D" && down?.before == false, "末尾使用最后一项作为后置锚点")
            let up = MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 3), toOffset: 0)
            expect(up?.orderedIDs == ["D", "A", "B", "C"], "末项拖到开头")
            expect(up?.targetID == "A" && up?.before == true, "开头使用前置锚点")
            let middle = MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 0), toOffset: 3)
            expect(middle?.orderedIDs == ["B", "C", "A", "D"], "向下拖动须扣除源项目占用的位置")
            expect(middle?.targetID == "D" && middle?.before == true, "落点转换为剩余项目的插入位置")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 2), toOffset: 1)?.orderedIDs == ["A", "C", "B", "D"], "向上移动一位")
        }
        test("列表取消或非法落点不能提交系统拖动") {
            let ids = ["A", "B", "C"]
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 1), toOffset: 1) == nil, "原位置无动作")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 1), toOffset: 2) == nil, "紧邻源后方仍是原位置")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(), toOffset: 0) == nil, "空选择不操作")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet([0, 1]), toOffset: 3) == nil, "单项目界面不接受批量系统拖动")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 8), toOffset: 0) == nil, "越界源拒绝")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 0), toOffset: -1) == nil, "负落点拒绝")
            expect(MenuOrder.listMove(ids, fromOffsets: IndexSet(integer: 0), toOffset: 4) == nil, "越界落点拒绝")
        }
        print("\(count) tests, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
