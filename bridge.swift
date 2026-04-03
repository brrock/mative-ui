import SwiftUI
import AppKit
import Foundation

typealias EventCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

struct MativeEdgeInsets: Codable, Equatable {
    let top: Double?
    let bottom: Double?
    let leading: Double?
    let trailing: Double?
    let horizontal: Double?
    let vertical: Double?
}

enum MativePadding: Codable, Equatable {
    case all(Double)
    case edges(MativeEdgeInsets)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .all(value)
            return
        }

        self = .edges(try container.decode(MativeEdgeInsets.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all(let value):
            try container.encode(value)
        case .edges(let edges):
            try container.encode(edges)
        }
    }
}

struct MativeFrame: Codable, Equatable {
    let minWidth: Double?
    let minHeight: Double?
    let width: Double?
    let height: Double?
    let maxWidth: Double?
    let maxHeight: Double?
    let fillWidth: Bool?
    let fillHeight: Bool?
    let alignment: String?
}

struct MativeMenuSection: Codable, Equatable {
    let title: String
    let items: [MativeMenuItem]
}

struct MativeMenuItem: Codable, Equatable {
    let type: String
    let id: String?
    let title: String?
    let keyEquivalent: String?
    let enabled: Bool?
    let children: [MativeMenuItem]?
}

struct MativeEvent: Codable {
    let type: String
    let id: String
    let value: String?
    let source: String?
    let label: String?
}

struct IndexedNode: Identifiable {
    let id: String
    let node: MativeNode
}

struct MativeNode: Codable, Equatable {
    let type: String
    let key: String?
    let axis: String?
    let spacing: Double?
    let children: [MativeNode]?
    let content: String?
    let size: Double?
    let color: String?
    let weight: String?
    let id: String?
    let label: String?
    let alignment: String?
    let padding: MativePadding?
    let frame: MativeFrame?
    let background: String?
    let selectable: Bool?
    let value: String?
    let placeholder: String?
    let buttonStyle: String?
    let minLength: Double?
    let layoutPriority: Double?
    let fixedWidth: Bool?
    let fixedHeight: Bool?

    init(
        type: String,
        key: String? = nil,
        axis: String? = nil,
        spacing: Double? = nil,
        children: [MativeNode]? = nil,
        content: String? = nil,
        size: Double? = nil,
        color: String? = nil,
        weight: String? = nil,
        id: String? = nil,
        label: String? = nil,
        alignment: String? = nil,
        padding: MativePadding? = nil,
        frame: MativeFrame? = nil,
        background: String? = nil,
        selectable: Bool? = nil,
        value: String? = nil,
        placeholder: String? = nil,
        buttonStyle: String? = nil,
        minLength: Double? = nil,
        layoutPriority: Double? = nil,
        fixedWidth: Bool? = nil,
        fixedHeight: Bool? = nil
    ) {
        self.type = type
        self.key = key
        self.axis = axis
        self.spacing = spacing
        self.children = children
        self.content = content
        self.size = size
        self.color = color
        self.weight = weight
        self.id = id
        self.label = label
        self.alignment = alignment
        self.padding = padding
        self.frame = frame
        self.background = background
        self.selectable = selectable
        self.value = value
        self.placeholder = placeholder
        self.buttonStyle = buttonStyle
        self.minLength = minLength
        self.layoutPriority = layoutPriority
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
    }

    func stableKey(fallbackIndex: Int) -> String {
        key ?? id ?? "\(type)-\(fallbackIndex)"
    }

    static let placeholderRoot = MativeNode(
        type: "vstack",
        spacing: 12,
        children: [
            MativeNode(
                type: "text",
                content: "mativeUi",
                size: 28,
                color: "blue",
                weight: "bold",
                selectable: true
            ),
            MativeNode(
                type: "text",
                content: "Waiting for Bun render()...",
                size: 14,
                color: "secondary",
                weight: "regular",
                selectable: true
            )
        ],
        alignment: "leading",
        padding: .all(20)
    )
}

final class UIStore: ObservableObject {
    @Published var root: MativeNode = .placeholderRoot
    @Published private var inputValues: [String: String] = [:]

    func update(with node: MativeNode) {
        let nextInputValues = collectInputValues(from: node)

        if node == root {
            if nextInputValues != inputValues {
                inputValues = nextInputValues
            }
            return
        }

        root = node
        inputValues = nextInputValues
    }

    func textValue(for node: MativeNode) -> String {
        guard let id = node.id else {
            return node.value ?? ""
        }

        return inputValues[id] ?? node.value ?? ""
    }

    func setTextValue(_ value: String, for id: String) {
        inputValues[id] = value
    }

    private func collectInputValues(from node: MativeNode) -> [String: String] {
        var values: [String: String] = [:]
        walk(node, values: &values)
        return values
    }

    private func walk(_ node: MativeNode, values: inout [String: String]) {
        if node.type == "textField", let id = node.id {
            values[id] = node.value ?? ""
        }

        for child in node.children ?? [] {
            walk(child, values: &values)
        }
    }
}

final class MativeAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        shouldQuit = true
        mainWindow = nil
    }

    func windowWillClose(_ notification: Notification) {
        mainWindow = nil
        NSApplication.shared.terminate(nil)
    }
}

final class MenuActionHandler: NSObject {
    @objc func handleMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        emitEvent(
            MativeEvent(
                type: "menu",
                id: id,
                value: sender.title,
                source: "menuItem",
                label: sender.title
            )
        )
    }
}

private let store = UIStore()
private let appDelegate = MativeAppDelegate()
private let menuActionHandler = MenuActionHandler()
private let eventEncoder = JSONEncoder()
private var mainWindow: NSWindow?
private var eventCallback: EventCallback?
private var shouldQuit = false
private var menuSections: [MativeMenuSection] = []
private var lastRenderedTree: MativeNode?
private var renderGeneration: Int64 = 0

func emitEvent(_ event: MativeEvent) {
    guard let callback = eventCallback else { return }
    guard let data = try? eventEncoder.encode(event) else { return }
    guard let json = String(data: data, encoding: .utf8) else { return }

    json.withCString { cString in
        callback(cString)
    }
}

func makeMenuItem(from item: MativeMenuItem) -> NSMenuItem {
    switch item.type {
    case "separator":
        return NSMenuItem.separator()

    case "submenu":
        let title = item.title ?? "Menu"
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for child in item.children ?? [] {
            submenu.addItem(makeMenuItem(from: child))
        }
        menuItem.submenu = submenu
        menuItem.isEnabled = item.enabled ?? true
        return menuItem

    default:
        let menuItem = NSMenuItem(
            title: item.title ?? "Untitled",
            action: #selector(MenuActionHandler.handleMenuItem(_:)),
            keyEquivalent: item.keyEquivalent ?? ""
        )
        menuItem.target = menuActionHandler
        menuItem.representedObject = item.id
        menuItem.isEnabled = item.enabled ?? true
        return menuItem
    }
}

func installMainMenu(appName: String) {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu(title: appName)

    appMenu.addItem(
        withTitle: "Quit \(appName)",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )

    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    for section in menuSections {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: section.title)
        for child in section.items {
            menu.addItem(makeMenuItem(from: child))
        }
        menuItem.title = section.title
        menuItem.submenu = menu
        mainMenu.addItem(menuItem)
    }

    NSApplication.shared.mainMenu = mainMenu
}

struct RootView: View {
    @ObservedObject var store: UIStore

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                render(store.root)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(containerPadding(for: proxy.size.width))
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(Color(nsColor: .windowBackgroundColor))
            .textSelection(.enabled)
        }
    }

    func render(_ node: MativeNode) -> AnyView {
        switch node.type {
        case "vstack":
            let children = identifiedChildren(node.children ?? [])
            return applyCommonModifiers(
                AnyView(
                    VStack(
                        alignment: vStackAlignment(node.alignment),
                        spacing: CGFloat(node.spacing ?? 0)
                    ) {
                        ForEach(children) { item in
                            render(item.node)
                        }
                    }
                ),
                node: node
            )

        case "hstack":
            let children = identifiedChildren(node.children ?? [])
            return applyCommonModifiers(
                AnyView(
                    HStack(
                        alignment: hStackAlignment(node.alignment),
                        spacing: CGFloat(node.spacing ?? 0)
                    ) {
                        ForEach(children) { item in
                            render(item.node)
                        }
                    }
                ),
                node: node
            )

        case "zstack":
            let children = identifiedChildren(node.children ?? [])
            return applyCommonModifiers(
                AnyView(
                    ZStack(alignment: parseAlignment(node.alignment)) {
                        ForEach(children) { item in
                            render(item.node)
                        }
                    }
                ),
                node: node
            )

        case "scrollView":
            let children = identifiedChildren(node.children ?? [])
            return applyCommonModifiers(
                AnyView(
                    ScrollView(parseAxis(node.axis)) {
                        VStack(
                            alignment: vStackAlignment(node.alignment),
                            spacing: CGFloat(node.spacing ?? 0)
                        ) {
                            ForEach(children) { item in
                                render(item.node)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                ),
                node: node
            )

        case "text":
            return applyCommonModifiers(
                AnyView(
                    Text(node.content ?? "")
                        .font(
                            .system(
                                size: CGFloat(node.size ?? 14),
                                weight: fontWeight(node.weight)
                            )
                        )
                        .foregroundColor(parseColor(node.color))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                ),
                node: node
            )

        case "button":
            let button = Button(node.label ?? "Button") {
                guard let id = node.id else { return }
                emitEvent(
                    MativeEvent(
                        type: "action",
                        id: id,
                        value: node.label,
                        source: "button",
                        label: node.label
                    )
                )
            }

            let styledButton: AnyView
            switch node.buttonStyle ?? "prominent" {
            case "borderless":
                styledButton = AnyView(button.buttonStyle(.borderless))
            case "plain":
                styledButton = AnyView(button.buttonStyle(.plain))
            case "link":
                styledButton = AnyView(button.buttonStyle(.link))
            case "bordered":
                styledButton = AnyView(button.buttonStyle(.bordered))
            default:
                styledButton = AnyView(button.buttonStyle(.borderedProminent))
            }

            return applyCommonModifiers(styledButton, node: node)

        case "textField":
            guard let id = node.id else {
                return applyCommonModifiers(
                    AnyView(
                        Text("textField node missing id")
                            .foregroundColor(.red)
                    ),
                    node: node
                )
            }

            let binding = Binding<String>(
                get: {
                    store.textValue(for: node)
                },
                set: { newValue in
                    store.setTextValue(newValue, for: id)
                    emitEvent(
                        MativeEvent(
                            type: "change",
                            id: id,
                            value: newValue,
                            source: "textField",
                            label: node.placeholder
                        )
                    )
                }
            )

            return applyCommonModifiers(
                AnyView(
                    TextField(node.placeholder ?? "", text: binding)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            emitEvent(
                                MativeEvent(
                                    type: "submit",
                                    id: id,
                                    value: store.textValue(for: node),
                                    source: "textField",
                                    label: node.placeholder
                                )
                            )
                        }
                ),
                node: node
            )

        case "spacer":
            return applyCommonModifiers(
                AnyView(Spacer(minLength: node.minLength.map { CGFloat($0) })),
                node: node
            )

        case "divider":
            return applyCommonModifiers(AnyView(Divider()), node: node)

        default:
            return applyCommonModifiers(
                AnyView(
                    Text("Unknown node type: \(node.type)")
                        .foregroundColor(.red)
                ),
                node: node
            )
        }
    }

    func identifiedChildren(_ children: [MativeNode]) -> [IndexedNode] {
        children.enumerated().map { index, child in
            IndexedNode(id: child.stableKey(fallbackIndex: index), node: child)
        }
    }

    func containerPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<520:
            return 12
        case ..<760:
            return 18
        default:
            return 24
        }
    }

    func applyCommonModifiers(_ view: AnyView, node: MativeNode) -> AnyView {
        var result = view

        if let padding = node.padding {
            result = applyPadding(result, padding: padding)
        }

        if let frame = node.frame {
            result = applyFrame(result, frame: frame)
        }

        if let background = node.background {
            result = AnyView(result.background(parseColor(background)))
        }

        if let layoutPriority = node.layoutPriority {
            result = AnyView(result.layoutPriority(layoutPriority))
        }

        if node.fixedWidth != nil || node.fixedHeight != nil {
            result = AnyView(
                result.fixedSize(
                    horizontal: node.fixedWidth ?? false,
                    vertical: node.fixedHeight ?? false
                )
            )
        }

        if let selectable = node.selectable {
            if selectable {
                result = AnyView(result.textSelection(.enabled))
            } else {
                result = AnyView(result.textSelection(.disabled))
            }
        }

        return result
    }

    func applyPadding(_ view: AnyView, padding: MativePadding) -> AnyView {
        switch padding {
        case .all(let value):
            return AnyView(view.padding(CGFloat(value)))
        case .edges(let edges):
            let horizontal = edges.horizontal ?? 0
            let vertical = edges.vertical ?? 0
            let top = edges.top ?? vertical
            let bottom = edges.bottom ?? vertical
            let leading = edges.leading ?? horizontal
            let trailing = edges.trailing ?? horizontal
            return AnyView(
                view.padding(
                    EdgeInsets(
                        top: CGFloat(top),
                        leading: CGFloat(leading),
                        bottom: CGFloat(bottom),
                        trailing: CGFloat(trailing)
                    )
                )
            )
        }
    }

    func applyFrame(_ view: AnyView, frame: MativeFrame) -> AnyView {
        let alignment = parseAlignment(frame.alignment)
        var result = view
        let minWidth = frame.minWidth.map { CGFloat($0) }
        let minHeight = frame.minHeight.map { CGFloat($0) }
        let width = frame.width.map { CGFloat($0) }
        let height = frame.height.map { CGFloat($0) }
        let maxWidth = frame.fillWidth == true ? CGFloat.infinity : frame.maxWidth.map { CGFloat($0) }
        let maxHeight = frame.fillHeight == true ? CGFloat.infinity : frame.maxHeight.map { CGFloat($0) }

        if frame.width != nil || frame.height != nil {
            result = AnyView(
                result.frame(
                    width: width,
                    height: height,
                    alignment: alignment
                )
            )
        }

        if frame.fillWidth == true || frame.fillHeight == true || frame.minWidth != nil || frame.minHeight != nil || frame.maxWidth != nil || frame.maxHeight != nil {
            result = AnyView(
                result.frame(
                    minWidth: minWidth,
                    maxWidth: maxWidth,
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    alignment: alignment
                )
            )
        }

        return result
    }

    func parseColor(_ value: String?) -> Color {
        switch value ?? "primary" {
        case "blue":
            return .blue
        case "red":
            return .red
        case "green":
            return .green
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "mint":
            return .mint
        case "indigo":
            return .indigo
        case "secondary":
            return .secondary
        default:
            return .primary
        }
    }

    func fontWeight(_ value: String?) -> Font.Weight {
        switch value ?? "regular" {
        case "medium":
            return .medium
        case "semibold":
            return .semibold
        case "bold":
            return .bold
        case "light":
            return .light
        case "heavy":
            return .heavy
        default:
            return .regular
        }
    }

    func vStackAlignment(_ value: String?) -> HorizontalAlignment {
        switch value ?? "leading" {
        case "center", "top", "bottom":
            return .center
        case "trailing", "topTrailing", "bottomTrailing":
            return .trailing
        default:
            return .leading
        }
    }

    func hStackAlignment(_ value: String?) -> VerticalAlignment {
        switch value ?? "center" {
        case "top", "topLeading", "topTrailing":
            return .top
        case "bottom", "bottomLeading", "bottomTrailing":
            return .bottom
        default:
            return .center
        }
    }

    func parseAlignment(_ value: String?) -> Alignment {
        switch value ?? "center" {
        case "topLeading":
            return .topLeading
        case "top":
            return .top
        case "topTrailing":
            return .topTrailing
        case "leading":
            return .leading
        case "trailing":
            return .trailing
        case "bottomLeading":
            return .bottomLeading
        case "bottom":
            return .bottom
        case "bottomTrailing":
            return .bottomTrailing
        default:
            return .center
        }
    }

    func parseAxis(_ value: String?) -> Axis.Set {
        switch value ?? "vertical" {
        case "horizontal":
            return .horizontal
        case "both":
            return [.horizontal, .vertical]
        default:
            return .vertical
        }
    }
}

@_cdecl("mative_init")
public func mative_init(_ callbackPtr: UnsafeMutableRawPointer?) {
    if let callbackPtr {
        eventCallback = unsafeBitCast(callbackPtr, to: EventCallback.self)
    }

    shouldQuit = false

    DispatchQueue.main.async {
        let app = NSApplication.shared
        ProcessInfo.processInfo.processName = "mativeUi"
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.finishLaunching()
        installMainMenu(appName: "mativeUi")

        if mainWindow == nil {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 832)
            let initialWidth = min(max(visibleFrame.width * 0.42, 560), 980)
            let initialHeight = min(max(visibleFrame.height * 0.62, 680), 920)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "mativeUi"
            window.delegate = appDelegate
            window.minSize = NSSize(width: 520, height: 620)
            window.setFrameAutosaveName("mativeUi.mainWindow")
            window.contentView = NSHostingView(rootView: RootView(store: store))
            window.makeKeyAndOrderFront(nil)

            mainWindow = window
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }

        app.activate(ignoringOtherApps: true)
    }
}

@_cdecl("mative_poll")
public func mative_poll() {
    let app = NSApplication.shared

    while let event = app.nextEvent(
        matching: .any,
        until: Date.distantPast,
        inMode: RunLoop.Mode.default,
        dequeue: true
    ) {
        app.sendEvent(event)
    }

    app.updateWindows()
}

@_cdecl("mative_should_quit")
public func mative_should_quit() -> Int32 {
    shouldQuit ? 1 : 0
}

@_cdecl("mative_set_menu")
public func mative_set_menu(_ jsonPtr: UnsafePointer<CChar>?) {
    guard let jsonPtr else { return }

    let jsonString = String(cString: jsonPtr)
    guard let data = jsonString.data(using: .utf8) else { return }

    do {
        let decoded = try JSONDecoder().decode([MativeMenuSection].self, from: data)
        DispatchQueue.main.async {
            menuSections = decoded
            installMainMenu(appName: "mativeUi")
        }
    } catch {
        print("mative_set_menu decode error:", error)
    }
}

@_cdecl("mative_update")
public func mative_update(_ jsonPtr: UnsafePointer<CChar>?) {
    guard let jsonPtr else { return }

    let jsonString = String(cString: jsonPtr)
    guard let data = jsonString.data(using: .utf8) else { return }

    do {
        let decoded = try JSONDecoder().decode(MativeNode.self, from: data)
        DispatchQueue.main.async {
            if decoded == lastRenderedTree {
                return
            }

            lastRenderedTree = decoded
            renderGeneration += 1
            store.update(with: decoded)
        }
    } catch {
        print("mative_update decode error:", error)
    }
}