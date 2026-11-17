//
//  AppDelegate.swift
//  CaffeineMate
//
//  Created by Edd on 07/10/2025.
//

import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private let inactiveIcon = AppDelegate.statusIcon("cup.and.saucer")
    private let activeIcon = AppDelegate.statusIcon("cup.and.saucer.fill")

    private let powerManager = PowerAssertionManager.shared
    private let settings = SettingsManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item with variable length to accommodate countdown
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Set up click handlers
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create menu
        setupMenu()

        // Initialize menu checkmarks with stored preferences
        updateMenuCheckmarks()

        powerManager.onStatusChanged = { [weak self] remainingSeconds in
            self?.updateStatusBarDisplay(remainingSeconds: remainingSeconds)
        }
        updateStatusBarDisplay(remainingSeconds: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerManager.onStatusChanged = nil
        powerManager.deactivate()
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Right click - show menu
            // Refresh menu checkmarks to reflect current settings
            updateMenuCheckmarks()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click - toggle awake mode
            toggleAwakeMode()
        }
    }

    private func setupMenu() {
        menu = NSMenu()

        // Duration submenu
        let durationMenu = NSMenu()
        durationMenu.addItem(NSMenuItem(title: "Indefinite", action: #selector(setIndefiniteDuration), keyEquivalent: ""))
        durationMenu.addItem(NSMenuItem(title: "15 minutes", action: #selector(set15MinDuration), keyEquivalent: ""))
        durationMenu.addItem(NSMenuItem(title: "1 hour", action: #selector(set1HourDuration), keyEquivalent: ""))
        durationMenu.addItem(NSMenuItem(title: "3 hours", action: #selector(set3HoursDuration), keyEquivalent: ""))
        durationMenu.addItem(NSMenuItem(title: "Custom...", action: #selector(setCustomDuration), keyEquivalent: ""))

        let durationMenuItem = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
        durationMenuItem.submenu = durationMenu
        menu.addItem(durationMenuItem)

        // Keep Display Awake
        menu.addItem(NSMenuItem(title: "Keep Display Awake", action: #selector(toggleKeepDisplayAwake), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Start at Login
        menu.addItem(NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Actions

    @objc private func toggleAwakeMode() {
        do {
            try powerManager.toggle(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: settings.awakeDuration)
        } catch {
            showAssertionError(error)
        }
    }

    @objc private func toggleKeepDisplayAwake() {
        applyAwakeSettings(keepDisplayAwake: !settings.keepDisplayAwake, durationMinutes: settings.awakeDuration)
    }

    @objc private func setIndefiniteDuration() {
        applyAwakeSettings(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: 0)
    }

    @objc private func set15MinDuration() {
        applyAwakeSettings(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: 15)
    }

    @objc private func set1HourDuration() {
        applyAwakeSettings(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: 60)
    }

    @objc private func set3HoursDuration() {
        applyAwakeSettings(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: 180)
    }

    @objc private func setCustomDuration() {
        let alert = NSAlert()
        alert.messageText = "Custom Duration"
        alert.informativeText = "Enter duration in minutes:"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.placeholderString = "Minutes"
        alert.accessoryView = inputTextField

        if alert.runModal() == .alertFirstButtonReturn,
           let minutes = Int(inputTextField.stringValue), minutes > 0 {
            applyAwakeSettings(keepDisplayAwake: settings.keepDisplayAwake, durationMinutes: minutes)
        }
    }

    private func applyAwakeSettings(keepDisplayAwake: Bool, durationMinutes: Int) {
        do {
            if powerManager.isActive {
                try powerManager.activate(keepDisplayAwake: keepDisplayAwake, durationMinutes: durationMinutes)
            }
            settings.keepDisplayAwake = keepDisplayAwake
            settings.awakeDuration = durationMinutes
            updateMenuCheckmarks()
        } catch {
            showAssertionError(error)
        }
    }

    @objc private func toggleStartAtLogin() {
        LaunchAtLoginManager.shared.toggle()
        updateMenuCheckmarks()
    }

    private func showAssertionError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Change Awake Mode"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - UI Updates

    private static func statusIcon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "CaffeineMate")
        image?.isTemplate = true
        return image
    }

    private func updateStatusBarDisplay(remainingSeconds: Int?) {
        guard let button = statusItem.button else { return }

        let isActive = powerManager.isActive
        let icon = isActive ? activeIcon : inactiveIcon
        if button.image !== icon {
            button.image = icon
        }

        guard isActive else {
            button.title = ""
            button.toolTip = "CaffeineMate (Inactive)\nClick to activate"
            return
        }

        let mode = powerManager.keepDisplayAwake ? "System & Display" : "System"
        let countdown = remainingSeconds.map(formatCountdown)
        button.title = countdown.map { " \($0)" } ?? ""
        let duration = countdown.map { "\($0) remaining" } ?? "Indefinite"
        button.toolTip = "CaffeineMate Active (\(mode))\n\(duration)"
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, secs)
        } else {
            return String(format: "%ld:%02ld", minutes, secs)
        }
    }

    private func updateMenuCheckmarks() {
        guard let menu = menu else { return }

        // Update Keep Display Awake checkmark
        menu.item(withTitle: "Keep Display Awake")?.state = settings.keepDisplayAwake ? .on : .off

        // Update duration checkmarks
        if let durationMenuItem = menu.item(withTitle: "Duration"),
           let durationSubmenu = durationMenuItem.submenu {
            for item in durationSubmenu.items {
                item.state = .off
            }

            switch settings.awakeDuration {
            case 0:
                durationSubmenu.item(withTitle: "Indefinite")?.state = .on
            case 15:
                durationSubmenu.item(withTitle: "15 minutes")?.state = .on
            case 60:
                durationSubmenu.item(withTitle: "1 hour")?.state = .on
            case 180:
                durationSubmenu.item(withTitle: "3 hours")?.state = .on
            default:
                durationSubmenu.item(withTitle: "Custom...")?.state = .on
            }
        }

        // Update launch at login checkmark
        menu.item(withTitle: "Start at Login")?.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
    }
}
