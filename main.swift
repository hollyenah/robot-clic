import SwiftUI
import AppKit

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2"

// MARK: - Helpers (macOS 10.15 compatible)

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .withinWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct GlassSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.primary.opacity(0.55) : Color.primary.opacity(0.18))
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

extension View {
    func glassFill<S: ShapeStyle>(_ style: S, _ radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(style))
    }
}

// MARK: - Keyboard shortcut

struct Shortcut: Equatable {
    var keyCode: UInt16
    var mods: NSEvent.ModifierFlags
    var label: String

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private static let names: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    var display: String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s + label
    }

    static func from(_ e: NSEvent) -> Shortcut {
        let label = names[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        return Shortcut(keyCode: e.keyCode, mods: e.modifierFlags.intersection(relevant), label: label)
    }

    func matches(_ e: NSEvent) -> Bool {
        e.keyCode == keyCode && e.modifierFlags.intersection(Shortcut.relevant) == mods
    }
}

enum ShortcutTarget { case start, stop }

// MARK: - Logic

final class Clicker: ObservableObject {
    @Published var intervalMs = "100"
    @Published var clickCount = "100"
    @Published var infinite = true
    @Published var delaySec = "3"

    @Published var useFixedPoint = false
    @Published var x = "0"
    @Published var y = "0"
    @Published var picking = false

    @Published var startKey = Shortcut(keyCode: 97, mods: [], label: "F6")
    @Published var stopKey = Shortcut(keyCode: 98, mods: [], label: "F7")
    @Published var recording: ShortcutTarget? = nil

    @Published var running = false
    @Published var done = 0
    @Published var status = "Ready"

    private var timer: Timer?
    private var countdownTimer: Timer?
    private var monitors: [Any] = []

    // MARK: Permissions

    func requestAccessIfNeeded() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            status = "Allow the app in Settings > Privacy > Accessibility"
        }
    }

    // MARK: Event monitors

    func installMonitors() {
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: { [weak self] e in
            self?.globalEvent(e)
        }) { monitors.append(g) }

        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            (self?.localKey(e) ?? false) ? nil : e
        }) { monitors.append(l) }
    }

    private func globalEvent(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            if picking, let p = CGEvent(source: nil)?.location {
                x = String(Int(p.x))
                y = String(Int(p.y))
                useFixedPoint = true
                picking = false
                status = "Position saved"
                NSApp.activate(ignoringOtherApps: true)
            }
        case .keyDown:
            if picking && e.keyCode == 53 {
                picking = false
                status = "Selection cancelled"
                return
            }
            handleShortcut(e)
        default:
            break
        }
    }

    private func localKey(_ e: NSEvent) -> Bool {
        if let target = recording {
            if e.keyCode == 53 { recording = nil; return true }
            let sc = Shortcut.from(e)
            switch target {
            case .start: startKey = sc
            case .stop: stopKey = sc
            }
            recording = nil
            return true
        }
        return handleShortcut(e)
    }

    @discardableResult
    private func handleShortcut(_ e: NSEvent) -> Bool {
        if e.isARepeat { return false }
        if stopKey.matches(e) { stop(); return true }
        if startKey.matches(e) { start(); return true }
        return false
    }

    // MARK: Clicking

    func start() {
        guard !running else { return }
        guard AXIsProcessTrusted() else { requestAccessIfNeeded(); return }

        let interval = Double(max(1, Int(intervalMs) ?? 100)) / 1000
        let total = infinite ? Int.max : max(1, Int(clickCount) ?? 1)
        var remaining = max(0, Double(delaySec.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let fixed = useFixedPoint
        let point = CGPoint(x: Double(x) ?? 0, y: Double(y) ?? 0)

        running = true
        done = 0

        let begin = { [weak self] in
            guard let self = self else { return }
            if fixed {
                CGWarpMouseCursorPosition(point)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
            self.status = "Running…"
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                let p = fixed ? point : (CGEvent(source: nil)?.location ?? .zero)
                Clicker.click(at: p)
                self.done += 1
                if self.done >= total {
                    timer.invalidate()
                    self.timer = nil
                    self.running = false
                    self.status = "Done"
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }

        if remaining > 0 {
            status = String(format: "Starting in %.1f s", remaining)
            let c = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                remaining -= 0.1
                if remaining <= 0 {
                    timer.invalidate()
                    self.countdownTimer = nil
                    begin()
                } else {
                    self.status = String(format: "Starting in %.1f s", remaining)
                }
            }
            RunLoop.main.add(c, forMode: .common)
            countdownTimer = c
        } else {
            begin()
        }
    }

    func stop() {
        guard running else { return }
        timer?.invalidate(); timer = nil
        countdownTimer?.invalidate(); countdownTimer = nil
        running = false
        status = "Stopped"
    }

    private static func click(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, CGEventType.leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}

// MARK: - UI components

struct GlassCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

struct NumField: View {
    @Binding var text: String
    var decimal = false
    var width: CGFloat = 78

    var body: some View {
        TextField("0", text: Binding(
            get: { text },
            set: { new in
                text = new.filter { $0.isNumber || (decimal && ($0 == "." || $0 == ",")) }
            }
        ))
        .textFieldStyle(PlainTextFieldStyle())
        .multilineTextAlignment(.trailing)
        .font(.system(size: 13, design: .monospaced))
        .frame(width: width)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassFill(Color.black.opacity(0.14), 8)
    }
}

struct Row<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            content
        }
    }
}

struct ShortcutButton: View {
    @EnvironmentObject var model: Clicker
    let target: ShortcutTarget

    var body: some View {
        let isRec = model.recording == target
        let sc = target == .start ? model.startKey : model.stopKey
        return Button(action: { model.recording = isRec ? nil : target }) {
            Text(isRec ? "Press a key…" : sc.display)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassFill(isRec ? Color.white.opacity(0.30) : Color.black.opacity(0.14), 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject var model: Clicker

    var body: some View {
        VStack(spacing: 12) {
            header
            rhythmCard
            positionCard
            shortcutsCard
            Spacer(minLength: 0)
            mainButton
            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 34)
        .padding(.bottom, 14)
        .frame(width: 400, height: 690)
    }

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Robot-clic").font(.system(size: 22, weight: .bold, design: .rounded))
                Text(model.status)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(model.done)").font(.system(size: 22, weight: .semibold, design: .monospaced))
                Text("clicks").font(.system(size: 10.5)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    var rhythmCard: some View {
        GlassCard(title: "Timing") {
            Row(label: "Interval") {
                NumField(text: $model.intervalMs)
                Text("ms").font(.system(size: 12)).foregroundColor(.secondary)
            }
            Row(label: "Click count") {
                if !model.infinite {
                    NumField(text: $model.clickCount)
                }
                Toggle("", isOn: $model.infinite).toggleStyle(GlassSwitch())
                Text("∞").font(.system(size: 15, weight: .medium))
            }
            Row(label: "Start delay") {
                NumField(text: $model.delaySec, decimal: true)
                Text("s").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    var positionCard: some View {
        GlassCard(title: "Position") {
            Row(label: "Fixed position") {
                Toggle("", isOn: $model.useFixedPoint).toggleStyle(GlassSwitch())
            }
            if model.useFixedPoint {
                Row(label: "X") { NumField(text: $model.x) }
                Row(label: "Y") { NumField(text: $model.y) }
            } else {
                Text("Clicks at the current cursor position.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Button(action: {
                model.picking.toggle()
                model.status = model.picking ? "Click where you want (Esc to cancel)" : "Ready"
            }) {
                Text(model.picking ? "Click anywhere…" : "◎  Pick by clicking")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassFill(model.picking ? Color.white.opacity(0.30) : Color.white.opacity(0.14), 10)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    var shortcutsCard: some View {
        GlassCard(title: "Shortcuts") {
            Row(label: "Start") { ShortcutButton(target: .start) }
            Row(label: "Stop") { ShortcutButton(target: .stop) }
        }
    }

    var footer: some View {
        VStack(spacing: 2) {
            Button(action: { NSWorkspace.shared.open(URL(string: "https://github.com/hollyenah/robot-clic")!) }) {
                Text("github.com/hollyenah/robot-clic").underline()
            }
            .buttonStyle(PlainButtonStyle())
            Text("By Hollyenah - Version : \(appVersion)")
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
    }

    var mainButton: some View {
        Button(action: { model.running ? model.stop() : model.start() }) {
            HStack(spacing: 8) {
                Text(model.running ? "■" : "▶")
                Text(model.running ? "Stop  \(model.stopKey.display)" : "Start  \(model.startKey.display)")
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassFill(Color.white.opacity(model.running ? 0.30 : 0.16), 14)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = Clicker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let blur = NSVisualEffectView()
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active

        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = blur
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        model.installMonitors()
        model.requestAccessIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()