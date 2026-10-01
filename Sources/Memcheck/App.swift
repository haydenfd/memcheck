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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notifications = NotificationManager()
    private let logger = Logger(subsystem: "com.haydenfd.memcheck", category: "monitor")
    private let pressureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let ramItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let availableItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let freeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let compressedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let wiredItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let swapItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var monitor = MemoryMonitor()
    private var pollingTask: Task<Void, Never>?
    private var snapshot: MemorySnapshot?
    private var health: MemoryHealthState = .normal
    private var lastError: String?
    private var loginItemError: String?
    private var loginStatus: SMAppService.Status = .notRegistered

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.menu = menu
        for item in [pressureItem, ramItem, availableItem, freeItem, compressedItem, wiredItem, swapItem, errorItem] {
            item.isEnabled = false
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
        updateMenu()
    }

    private func updateMenu() {
        let symbol = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Memory health")
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        statusItem.button?.title = ""
        statusItem.button?.contentTintColor = switch health {
        case .normal: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
        statusItem.button?.toolTip = "Memory pressure: \(health.rawValue.capitalized)"

        pressureItem.title = "Memory Pressure: \(health.rawValue.capitalized)"
        if let snapshot {
            ramItem.title = "RAM: \(format(snapshot.usedBytes)) / \(format(snapshot.totalBytes))"
            availableItem.title = "Available: \(format(snapshot.availableBytes))"
            freeItem.title = "Free: \(format(snapshot.freeBytes))"
            compressedItem.title = "Compressed: \(format(snapshot.compressedBytes))"
            wiredItem.title = "Wired: \(format(snapshot.wiredBytes))"
            swapItem.title = "Swap: \(format(snapshot.swapUsedBytes))"
        } else {
            ramItem.title = lastError ?? "Reading memory…"
        }
        for item in [availableItem, freeItem, compressedItem, wiredItem, swapItem] {
            item.isHidden = snapshot == nil
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

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
