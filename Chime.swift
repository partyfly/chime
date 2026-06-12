// Chime — a tiny draggable desktop pet that tells you what to do right now,
// based on a schedule you control. Floating card shows the current block +
// tasks; collapses into a small pill. Drag it anywhere (position is saved).
// Right-click for the menu. Schedule lives in ~/.config/chime/schedule.json
// (editable, auto-created, hot-reloaded every 30s).
// Build: ./build.sh   Run: open Chime.app

import AppKit
import UserNotifications

// MARK: - Model

struct Phase: Codable {
    var start: String       // "HH:mm" local time
    var end: String         // "HH:mm", may wrap past midnight
    var emoji: String
    var title: String
    var task: String        // segments separated by ";" become lines
    var notify: Bool?       // default true
}

// A generic all-day starter schedule. Override it in ~/.config/chime/schedule.json.
let defaultPhases: [Phase] = [
    Phase(start: "07:00", end: "09:00", emoji: "🌅",
          title: "Morning",
          task: "Wake up, plan the day; light reading, no heavy decisions yet",
          notify: true),
    Phase(start: "09:00", end: "12:30", emoji: "💻",
          title: "Deep work",
          task: "Hardest task first; notifications off; single-task this block",
          notify: true),
    Phase(start: "12:30", end: "13:30", emoji: "🍽️",
          title: "Lunch",
          task: "Step away from the screen",
          notify: false),
    Phase(start: "13:30", end: "17:00", emoji: "🔨",
          title: "Focus",
          task: "Second work block; ship something concrete before you stop",
          notify: true),
    Phase(start: "17:00", end: "18:00", emoji: "🧘",
          title: "Exercise",
          task: "Move your body; the longest half-life is your health",
          notify: false),
    Phase(start: "18:00", end: "19:30", emoji: "🍜",
          title: "Dinner & break",
          task: "Eat, rest, touch grass",
          notify: false),
    Phase(start: "19:30", end: "22:00", emoji: "📚",
          title: "Learn & create",
          task: "Reading, writing, side projects; the compounding hours",
          notify: true),
    Phase(start: "22:00", end: "23:00", emoji: "🌙",
          title: "Wind down",
          task: "No screens; prep tomorrow's top task",
          notify: true),
    Phase(start: "23:00", end: "07:00", emoji: "💤",
          title: "Sleep",
          task: "Rest is a strategy, not a gap",
          notify: false),
]

func parseHM(_ s: String) -> Int? {
    let parts = s.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return nil }
    return h * 60 + m
}

func fmtCountdown(_ mins: Int) -> String {
    if mins >= 60 { return "\(mins / 60)h\(String(format: "%02d", mins % 60))m" }
    return "\(mins)m"
}

// MARK: - Views

/// Background view that lets you drag the window from anywhere.
final class DraggableEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: WidgetWindow!
    var timer: Timer?
    var phases: [Phase] = defaultPhases
    var lastNotifiedKey = ""
    var notificationsOK = false

    let defaults = UserDefaults.standard
    var expanded: Bool {
        get { defaults.object(forKey: "expanded") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "expanded") }
    }
    var agendaWindow: NSWindow?   // separate pop-up window listing the full day

    let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/chime", isDirectory: true)
    var configURL: URL { configDir.appendingPathComponent("schedule.json") }
    var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.partyfly.chime.plist")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadSchedule()

        window = WidgetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                self.notificationsOK = ok
            }
        }

        rebuildUI()
        restorePosition()
        window.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in self.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    /// Double-clicked in Finder while already running → bring the pet forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        expanded = true
        rebuildUI()
        window.orderFrontRegardless()
        return false
    }

    // MARK: schedule

    func loadSchedule() {
        guard let data = try? Data(contentsOf: configURL),
              let loaded = try? JSONDecoder().decode([Phase].self, from: data),
              !loaded.isEmpty,
              loaded.allSatisfy({ parseHM($0.start) != nil && parseHM($0.end) != nil })
        else { phases = defaultPhases; return }
        phases = loaded
    }

    func writeDefaultConfigIfMissing() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(defaultPhases) { try? data.write(to: configURL) }
    }

    func nowMinutes() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func currentPhase(_ now: Int) -> (Phase, Int)? {
        for p in phases {
            guard let s = parseHM(p.start), let e = parseHM(p.end) else { continue }
            let inside = s <= e ? (now >= s && now < e) : (now >= s || now < e)
            if inside { return (p, ((e - now) % 1440 + 1440) % 1440) }
        }
        return nil
    }

    func nextPhase(_ now: Int) -> (Phase, Int)? {
        var best: (Phase, Int)? = nil
        for p in phases {
            guard let s = parseHM(p.start) else { continue }
            let dt = ((s - now) % 1440 + 1440) % 1440
            if dt == 0 { continue }
            if best == nil || dt < best!.1 { best = (p, dt) }
        }
        return best
    }

    // MARK: tick + hot reload

    var lastConfigMTime: Date?
    func configMTime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
    }

    func tick() {
        let mt = configMTime()
        if mt != lastConfigMTime { lastConfigMTime = mt; loadSchedule() }

        let now = nowMinutes()
        if let (p, _) = currentPhase(now) {
            let key = "\(p.start)-\(p.title)"
            if key != lastNotifiedKey {
                lastNotifiedKey = key
                if p.notify ?? true { sendNotification(p) }
            }
        } else {
            lastNotifiedKey = ""
        }
        rebuildUI()
        if agendaWindow != nil { refreshAgendaWindow() }
    }

    func sendNotification(_ p: Phase) {
        guard notificationsOK else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(p.emoji) \(p.title)"
        content.body = p.task.replacingOccurrences(of: ";", with: "\n· ")
        content.sound = .default
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: UI

    func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 3
        l.preferredMaxLayoutWidth = 240
        return l
    }

    func rebuildUI() {
        let oldTopY = window.frame.maxY
        let oldX = window.frame.minX

        let effect = DraggableEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = expanded ? 16 : 19
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        effect.menu = buildContextMenu()

        let now = nowMinutes()
        let cur = currentPhase(now)
        let next = nextPhase(now)

        var size: NSSize

        if expanded {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 14)
            stack.translatesAutoresizingMaskIntoConstraints = false

            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            let emoji = makeLabel(cur?.0.emoji ?? "🐦", size: 26)
            let title = makeLabel(cur?.0.title ?? "Free time", size: 14, weight: .bold)
            let agendaBtn = NSButton(title: "📋", target: self, action: #selector(toggleAgenda))
            agendaBtn.isBordered = false
            agendaBtn.font = .systemFont(ofSize: 11)
            agendaBtn.toolTip = "Show the full day in a separate window"
            let collapseBtn = NSButton(title: "➖", target: self, action: #selector(toggleCollapse))
            collapseBtn.isBordered = false
            collapseBtn.font = .systemFont(ofSize: 11)
            collapseBtn.toolTip = "Collapse to a pill (click the pill to expand)"
            header.addArrangedSubview(emoji)
            header.addArrangedSubview(title)
            header.addArrangedSubview(NSView())
            header.addArrangedSubview(agendaBtn)
            header.addArrangedSubview(collapseBtn)
            stack.addArrangedSubview(header)

            if let (p, rem) = cur {
                stack.addArrangedSubview(makeLabel("\(p.start)–\(p.end) · \(fmtCountdown(rem)) left",
                                                   size: 12, color: .secondaryLabelColor))
                for seg in p.task.split(separator: ";").prefix(4) {
                    stack.addArrangedSubview(makeLabel("· " + seg.trimmingCharacters(in: .whitespaces),
                                                       size: 12.5))
                }
            } else if let (np, dt) = next {
                stack.addArrangedSubview(makeLabel("Next: \(np.emoji) \(np.title)", size: 12.5))
                stack.addArrangedSubview(makeLabel("starts at \(np.start) · in \(fmtCountdown(dt))",
                                                   size: 12, color: .secondaryLabelColor))
                stack.addArrangedSubview(makeLabel("Free block — focus on your own work 🛠️",
                                                   size: 12, color: .secondaryLabelColor))
            }

            effect.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: effect.topAnchor),
                stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            ])
            let fit = stack.fittingSize
            size = NSSize(width: max(280, fit.width), height: max(64, fit.height))
        } else {
            var text: String
            if let (p, rem) = cur { text = "\(p.emoji) \(fmtCountdown(rem))" }
            else if let (np, dt) = next, dt <= 90 { text = "→\(np.emoji) \(fmtCountdown(dt))" }
            else { text = "🐦" }

            let label = makeLabel(text, size: 15, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            ])
            let w = label.fittingSize.width + 30
            size = NSSize(width: max(56, w), height: 38)

            let click = NSClickGestureRecognizer(target: self, action: #selector(toggleCollapse))
            effect.addGestureRecognizer(click)
            effect.toolTip = "Click to expand · drag to move · right-click for menu"
        }

        window.contentView = effect
        window.setFrame(NSRect(x: oldX, y: oldTopY - size.height, width: size.width, height: size.height),
                        display: true, animate: false)
    }

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem(expanded ? "➖ Collapse to pill" : "⬆️ Expand card", #selector(toggleCollapse)))
        menu.addItem(.separator())

        let scheduleItem = NSMenuItem(title: "📋 Today's schedule", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let now = nowMinutes()
        let inside = currentPhase(now)?.0
        for p in phases {
            let mark = (inside != nil && inside!.start == p.start && inside!.title == p.title) ? "▶︎ " : "   "
            let i = NSMenuItem(title: "\(mark)\(p.start)–\(p.end)  \(p.emoji) \(p.title)", action: nil, keyEquivalent: "")
            i.isEnabled = false
            i.toolTip = p.task.replacingOccurrences(of: ";", with: "\n")
            sub.addItem(i)
        }
        scheduleItem.submenu = sub
        menu.addItem(scheduleItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("✏️ Edit schedule (JSON)…", #selector(editSchedule)))
        menu.addItem(makeItem("🔄 Reload schedule", #selector(reloadSchedule)))
        menu.addItem(makeItem(isLoginEnabled() ? "✅ Launch at login (on)" : "⬜︎ Launch at login", #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Chime", #selector(quit), key: "q"))
        return menu
    }

    func makeItem(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: position persistence

    func restorePosition() {
        if let x = defaults.object(forKey: "originX") as? Double,
           let y = defaults.object(forKey: "originY") as? Double {
            let pt = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -50, dy: -50).contains(pt) }) {
                window.setFrameOrigin(pt)
                return
            }
        }
        if let vf = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.maxX - window.frame.width - 24,
                                          y: vf.maxY - window.frame.height - 24))
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        defaults.set(Double(window.frame.origin.x), forKey: "originX")
        defaults.set(Double(window.frame.origin.y), forKey: "originY")
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === agendaWindow { agendaWindow = nil }
    }

    // MARK: actions

    @objc func toggleCollapse() { expanded.toggle(); rebuildUI() }

    @objc func toggleAgenda() {
        if let w = agendaWindow { w.close(); agendaWindow = nil; return }
        showAgendaWindow()
    }

    func showAgendaWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "Today"
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.delegate = self
        w.isReleasedWhenClosed = false
        agendaWindow = w
        refreshAgendaWindow()
        positionAgenda()
        w.makeKeyAndOrderFront(nil)
    }

    func refreshAgendaWindow() {
        guard let w = agendaWindow else { return }
        let cur = currentPhase(nowMinutes())?.0
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for p in phases {
            let isNow = cur != nil && p.start == cur!.start && p.title == cur!.title
            let row = makeLabel("\(isNow ? "▶︎" : "      ") \(p.start)–\(p.end)   \(p.emoji) \(p.title)",
                                size: 13,
                                weight: isNow ? .bold : .regular,
                                color: isNow ? .controlAccentColor : .labelColor)
            row.maximumNumberOfLines = 1
            row.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(row)
        }
        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        let fit = stack.fittingSize
        w.setContentSize(NSSize(width: max(300, fit.width), height: fit.height))
        w.contentView = host
    }

    func positionAgenda() {
        guard let w = agendaWindow else { return }
        let card = window.frame
        var x = card.minX - w.frame.width - 12
        var y = card.maxY - w.frame.height
        if let vf = NSScreen.main?.visibleFrame {
            if x < vf.minX + 8 { x = card.maxX + 12 }       // no room on the left → go right
            y = min(max(y, vf.minY + 8), vf.maxY - w.frame.height - 8)
        }
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc func editSchedule() { writeDefaultConfigIfMissing(); NSWorkspace.shared.open(configURL) }
    @objc func reloadSchedule() { loadSchedule(); lastNotifiedKey = ""; tick() }
    @objc func toggleLogin() {
        if isLoginEnabled() {
            try? FileManager.default.removeItem(at: agentURL)
        } else {
            let plist: [String: Any] = [
                "Label": "com.partyfly.chime",
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: agentURL)
        }
    }
    func isLoginEnabled() -> Bool { FileManager.default.fileExists(atPath: agentURL.path) }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
