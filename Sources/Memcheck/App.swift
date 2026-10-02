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
    private let swapItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let appsTitle = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let appItems = (0..<5).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var monitor = MemoryMonitor()
    private var pollingTask: Task<Void, Never>?
    private var refreshing = false
    private var snapshot: MemorySnapshot?
    private var appMemory: [AppMemory] = []
    private var appMemoryTrend = AppMemoryTrend()
    private var appMemoryLoaded = false
    private var menuOpen = false
    private var notificationState: MemoryHealthState = .normal
    private var lastError: String?
    private var loginItemError: String?
    private var loginStatus: SMAppService.Status = .notRegistered

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [pressureItem, availableItem, swapItem, errorItem] {
            menu.addItem(item)
        }
        menu.addItem(.separator())
        appsTitle.isEnabled = false
        appsTitle.title = "Top consumers (change while open)"
        menu.addItem(appsTitle)
        for item in appItems {
            let actions = NSMenu()
            actions.autoenablesItems = false
            for (title, action) in [
                ("Quit", #selector(quitApp(_:))),
                ("Force Quit…", #selector(forceQuitApp(_:))),
            ] {
                let actionItem = actions.addItem(withTitle: title, action: action, keyEquivalent: "")
                actionItem.target = self
            }
            item.submenu = actions
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
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let current = try await MemoryReader.sample()
            snapshot = current
            lastError = nil
            let next = monitor.update(current, at: .now)
            if next != notificationState {
                notificationState = next
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
        let pressure = lastError == nil ? snapshot?.systemPressure : nil
        let color: NSColor = switch pressure {
        case .some(.normal): .systemGreen
        case .some(.warning): .systemOrange
        case .some(.critical): .systemRed
        case nil: .secondaryLabelColor
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
        statusItem.button?.toolTip = pressure.map { "Memory pressure: \($0.rawValue.capitalized)" }
            ?? "Memory pressure unavailable"

        if let snapshot, let pressure {
            pressureItem.title = "Memory Pressure: \(pressure.rawValue.capitalized)"
            availableItem.title = "Available (estimated): \(format(snapshot.availableBytes))"
            swapItem.title = "Swap Used: \(format(snapshot.swapUsedBytes))"
        } else {
            pressureItem.title = "Memory Pressure: —"
            availableItem.title = lastError ?? "Reading memory…"
            swapItem.title = "Swap Used: —"
        }
        for (index, item) in appItems.enumerated() {
            item.isHidden = index >= max(appMemory.count, 1)
            if index < appMemory.count {
                let app = appMemory[index]
                let change = appMemoryTrend.change(for: app)
                let changeLabel = change == 0 ? "" : " (\(change > 0 ? "+" : "−")\(format(change.magnitude)))"
                item.title = "\(app.name) — \(format(app.bytes))\(changeLabel)"
                item.isEnabled = true
                if let actions = item.submenu?.items {
                    actions.forEach { $0.representedObject = app.bundlePath }
                    let canQuit = runningApp(for: actions[0]) != nil
                    actions[0].isEnabled = canQuit
                    actions[1].isEnabled = canQuit
                }
            } else if index == 0 {
                item.title = appMemoryLoaded ? "Unavailable" : "Reading…"
                item.isEnabled = false
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
        appMemory = []
        appMemoryLoaded = false
        appMemoryTrend.reset()
        updateMenu()
        Task { await refresh() }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func runningApp(for item: NSMenuItem) -> NSRunningApplication? {
        guard let path = item.representedObject as? String,
              !path.hasPrefix("/System/") else { return nil }
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
                && !$0.isTerminated
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        return matches.count == 1 ? matches[0] : nil
    }

    @objc private func quitApp(_ item: NSMenuItem) {
        guard let app = runningApp(for: item), app.terminate() else {
            showAppActionError()
            return
        }
        Task { await refresh() }
    }

    @objc private func forceQuitApp(_ item: NSMenuItem) {
        guard let app = runningApp(for: item) else {
            showAppActionError()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Force quit \(app.localizedName ?? "this app")?"
        alert.informativeText = "Unsaved changes in this app may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard app.isTerminated || app.forceTerminate() else {
            showAppActionError()
            return
        }
        Task { await refresh() }
    }

    private func showAppActionError() {
        let alert = NSAlert()
        alert.messageText = "App action unavailable"
        alert.informativeText = "The app may have closed or macOS may have denied the request."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
