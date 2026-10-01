import AppKit
import Foundation
import ServiceManagement
import os

@main
enum MemcheckApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let notifications = NotificationManager()
    private let logger = Logger(subsystem: "com.haydenfd.memcheck", category: "monitor")
    private let pressureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let availableItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let appsTitle = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let appItems = (0..<5).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private var appLabels: [(name: NSTextField, amount: NSTextField)] = []
    private let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var monitor = MemoryMonitor()
    private var pollingTask: Task<Void, Never>?
    private var snapshot: MemorySnapshot?
    private var appMemory: [AppMemory] = []
    private var appMemoryLoaded = false
    private var menuOpen = false
    private var health: MemoryHealthState = .normal
    private var lastError: String?
    private var loginItemError: String?
    private var loginStatus: SMAppService.Status = .notRegistered

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [pressureItem, availableItem, errorItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        appsTitle.isEnabled = false
        appsTitle.title = "Top consumers"
        menu.addItem(appsTitle)
        for item in appItems {
            let row = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            let name = NSTextField(labelWithString: "")
            name.frame = NSRect(x: 14, y: 1, width: 165, height: 20)
            name.lineBreakMode = .byTruncatingTail
            let amount = NSTextField(labelWithString: "")
            amount.frame = NSRect(x: 181, y: 1, width: 85, height: 20)
            amount.alignment = .right
            row.addSubview(name)
            row.addSubview(amount)
            item.view = row
            appLabels.append((name, amount))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r").target = self
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(withTitle: "Quit Memcheck", action: #selector(quitClicked), keyEquivalent: "q").target = self
        updateMenu()
        registerAtLogin()
        notifications.requestPermission()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
    }

    private func refresh() async {
        do {
            let current = try await MemoryReader.sample()
            snapshot = current
            lastError = nil
            let next = monitor.update(current, at: .now)
            if next != health {
                health = next
                notifications.entered(next)
            }
        } catch {
            lastError = "Memory reading unavailable"
            logger.error("Memory sample failed: \(String(describing: error))")
        }
        if menuOpen {
            appMemory = await AppMemoryReader.topFive()
            appMemoryLoaded = true
        }
        updateMenu()
    }

    private func updateMenu() {
        let color: NSColor = switch health {
        case .normal: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
        if let symbol = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Memory health") {
            let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                symbol.draw(in: rect)
                color.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            icon.isTemplate = false
            statusItem.button?.image = icon
        }
        statusItem.button?.title = ""
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = "Memory pressure: \(health.rawValue.capitalized)"

        if let snapshot, snapshot.totalBytes > 0 {
            let percent = Int((100 * Double(snapshot.availableBytes) / Double(snapshot.totalBytes)).rounded())
            pressureItem.title = "Health: \(percent)%"
            availableItem.title = "Available: \(format(snapshot.availableBytes))"
        } else {
            pressureItem.title = "Health: —"
            availableItem.title = lastError ?? "Reading memory…"
        }
        for (index, item) in appItems.enumerated() {
            item.isHidden = index >= max(appMemory.count, 1)
            if index < appMemory.count {
                let app = appMemory[index]
                appLabels[index].name.stringValue = app.name
                appLabels[index].amount.stringValue = format(app.bytes)
            } else if index == 0 {
                appLabels[index].name.stringValue = appMemoryLoaded ? "Unavailable" : "Reading…"
                appLabels[index].amount.stringValue = ""
            }
        }
        errorItem.title = lastError ?? ""
        errorItem.isHidden = lastError == nil || snapshot == nil
        switch loginStatus {
        case .enabled:
            loginItem.title = "Launch at Login: On"
            loginItem.action = nil
            loginItem.isEnabled = false
        case .requiresApproval:
            loginItem.title = "Enable Launch at Login…"
            loginItem.action = #selector(openLoginItems)
            loginItem.isEnabled = true
        default:
            loginItem.title = loginItemError ?? "Launch at Login: Off"
            loginItem.action = nil
            loginItem.isEnabled = false
        }
    }

    private func registerAtLogin() {
        loginStatus = SMAppService.mainApp.status
        if loginStatus != .enabled && loginStatus != .requiresApproval {
            do {
                try SMAppService.mainApp.register()
            } catch {
                loginItemError = "Launch at Login: Unavailable"
                logger.error("Login registration failed: \(error.localizedDescription, privacy: .public)")
            }
            loginStatus = SMAppService.mainApp.status
        }
        logger.info("Login service status: \(self.loginStatus.rawValue)")
        updateMenu()
    }

    private func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    @objc private func refreshClicked() {
        loginStatus = SMAppService.mainApp.status
        Task { await refresh() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        Task { await refresh() }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
