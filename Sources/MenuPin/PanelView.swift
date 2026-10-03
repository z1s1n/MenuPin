import SwiftUI
import AppKit
import MenuPinCore

private let accent = Color(red: 0.20, green: 0.36, blue: 0.92)
private let canvas = Color(nsColor: .controlBackgroundColor)

struct PanelView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.settings { settingsContent }
            else { mainContent }
            footer
        }
        .frame(width: 420, height: 620)
        .background(canvas)
        .tint(accent)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .onExitCommand { model.closePanel?() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(accent)
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.settings ? "管理设置" : "菜单栏项目").font(.system(size: 23, weight: .bold))
                Text("MenuPin").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.settings {
                iconButton("arrow.left", help: "返回项目列表") { model.settings = false }
            }
            iconButton("xmark", help: "关闭面板") { model.closePanel?() }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索菜单栏项目", text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).focused($searching)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }.padding(11).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24).padding(.bottom, 16)

            if let message = model.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(accent)
                    Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.message = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                }.padding(12).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }

            if !model.trusted { permissionContent }
            else if !model.orderValid && !model.demo { layoutHelp }
            else if model.items.isEmpty {
                Spacer()
                Image(systemName: model.scanning ? "ellipsis" : "menubar.rectangle").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(model.scanning ? "正在读取菜单栏…" : "暂未发现可管理的项目").font(.system(size: 14, weight: .semibold)).padding(.top, 14)
                Text("请先展开菜单栏，再刷新列表。\n部分系统项目可能不向其他应用开放。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 5)
                Button("刷新列表") { model.refresh() }.padding(.top, 14).disabled(model.scanning)
                Spacer()
            } else {
                List {
                    if !model.pinned.isEmpty { group(title: "固定在菜单栏", subtitle: "按菜单栏从左到右排列 · 拖动左侧 ≡ 排序", items: model.pinned) }
                    if !model.hidden.isEmpty { group(title: "收起的项目", subtitle: "点击尝试直接打开 · 保持菜单栏收起", items: model.hidden) }
                    if !model.unknown.isEmpty { group(title: "待定位的项目", subtitle: "展开菜单栏后刷新，或在对应屏幕调整", items: model.unknown) }
                    if model.filtered.isEmpty {
                        Text("没有找到“\(model.query)”").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30)
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 48)
            }
        }.frame(maxHeight: .infinity)
    }

    private func group(title: String, subtitle: String, items: [BarItem]) -> some View {
        Section {
            ForEach(items) { item in
                row(item)
                    .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(!model.canListMove(item))
            }
            .onMove { offsets, destination in
                model.moveListItems(snapshot: items, fromOffsets: offsets, toOffset: destination)
            }
        } header: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text("\(items.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.primary.opacity(0.06), in: Capsule())
                }
                Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? subtitle : "清空搜索后可拖动排序")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
                .textCase(nil)
        }
    }

    private func row(_ item: BarItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .frame(width: 16, height: 34).contentShape(Rectangle())
                .help(model.canListMove(item) ? "拖动左侧横线调整组内顺序" : "当前不可拖动排序，可尝试更多菜单中的左右移动")
                .accessibilityLabel("拖动排序 \(item.title)")
            Button { model.openOriginal(item) } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04))
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(accent)
                        } else if let image = item.icon {
                            Image(nsImage: image).resizable().scaledToFit().padding(5)
                        } else {
                            Image(systemName: item.isSystem ? "gearshape" : "app.dashed").font(.system(size: 18)).foregroundStyle(.secondary)
                        }
                    }.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                        Text(item.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("打开 \(item.title) 的原菜单")
            Button { searching = false; model.togglePin(item) } label: {
                Image(systemName: item.section == .pinned ? "pin.fill" : "pin")
                    .font(.system(size: 16)).foregroundStyle(item.section == .pinned ? accent : Color.secondary)
                    .frame(width: 30, height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain).help(item.section == .pinned ? "收起此项目" : "固定到菜单栏")
                .disabled(item.section == .unknown)
            Menu {
                Button("打开原菜单") { model.openOriginal(item) }
                Button("打开右键菜单") { model.openOriginal(item, right: true) }
                Button(item.section == .pinned ? "收起此项目" : "固定到菜单栏") { model.togglePin(item) }.disabled(item.section == .unknown)
                Divider()
                Button("向左移一位") { model.moveOne(item, direction: .left) }.disabled(!model.canMove(item, direction: .left))
                Button("向右移一位") { model.moveOne(item, direction: .right) }.disabled(!model.canMove(item, direction: .right))
                if !model.demo {
                    Divider()
                    Button("显示所属应用") { NSRunningApplication(processIdentifier: item.pid)?.activate(options: [.activateIgnoringOtherApps]) }
                }
            } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).frame(width: 16, height: 32)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }.padding(.horizontal, 8).padding(.vertical, 7)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .disabled(model.busy)
    }

    private var permissionContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.08)).frame(width: 78, height: 78)
                Image(systemName: "hand.raised.fill").font(.system(size: 30)).foregroundStyle(accent)
            }
            Text("允许 MenuPin 管理菜单栏").font(.system(size: 17, weight: .semibold))
            Text("开启辅助功能后，即可读取菜单栏项目、\n固定图标，并从这里打开原菜单。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button("打开辅助功能设置") { Accessibility.openSettings() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("系统设置 → 隐私与安全性 → 辅助功能\n添加并开启 MenuPin，然后点刷新。\n已开启仍无效时，请移除旧条目并重新添加。")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var layoutHelp: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "arrow.left.and.right").font(.system(size: 32)).foregroundStyle(accent)
            Text("先摆好收起区分隔线").font(.system(size: 17, weight: .semibold))
            Text("按住 ⌘，将分隔图标拖到 MenuPin 左边。\n左边是收起区，右边是固定区。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button("已调整，刷新列表") { model.refresh() }.buttonStyle(.borderedProminent)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label("偏好设置", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                Toggle(isOn: $model.autoCollapse) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动收起").font(.system(size: 13))
                        Text("关闭面板 10 秒后收起，鼠标在菜单栏时延后。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch)
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .font(.system(size: 13)).toggleStyle(.switch)
            }.padding(16).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("辅助功能", systemImage: "accessibility").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(model.trusted ? "已开启" : "未开启").font(.system(size: 11)).foregroundStyle(model.trusted ? .green : .orange)
                }
                Text("权限仅用于读取、移动和点击菜单栏图标。\n所有设置保存在本机。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("打开系统权限设置") { if !model.demo { Accessibility.openSettings() } }.font(.system(size: 12))
            }.padding(16).background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                Button("恢复保存的图钉和顺序") { model.restoreLayout() }.disabled(!model.trusted || model.busy || model.demo)
                Button("展开所有图标") { model.setExpanded(true) }
                Text("也可按住 ⌘ 手动拖动图标。部分系统项目\n无法移动；退出 MenuPin 会恢复全部图标。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.font(.system(size: 12))
            if let message = model.message { Text(message).font(.system(size: 11)).foregroundStyle(accent) }
            Spacer()
            HStack {
                Text("MenuPin 1.2 · 本机运行").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("退出 MenuPin") { if model.demo { model.closePanel?() } else { NSApp.terminate(nil) } }.font(.system(size: 11))
            }
        }.padding(.horizontal, 24).padding(.bottom, 20).frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button { model.settings.toggle() } label: {
                    Label(model.settings ? "项目列表" : "管理菜单栏", systemImage: model.settings ? "square.grid.2x2" : "gearshape")
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain)
                Spacer()
                if model.busy || model.scanning { ProgressView().controlSize(.small).scaleEffect(0.75) }
                else { iconButton("arrow.clockwise", help: "刷新项目") { model.refresh() } }
                Button {
                    if model.expanded {
                        model.closePanel?()
                        model.setExpanded(false)
                    } else { model.setExpanded(true) }
                } label: {
                    Label(model.expanded ? "收起" : "展开", systemImage: model.expanded ? "chevron.left.2" : "chevron.right.2")
                        .font(.system(size: 11, weight: .semibold))
                }.buttonStyle(.bordered).disabled(model.busy)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            if model.applyingOrder {
                Text("正在应用菜单栏顺序…").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            if model.demo {
                Text("交互演示 · 示例项目，不操作真实菜单栏").font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 25, height: 25).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help)
    }
}
