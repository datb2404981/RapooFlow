import AppKit
import ApplicationServices

private final class PresetConfig: NSObject {
    let name: String
    let step: Double
    let speed: Double
    let duration: Double

    init(name: String, step: Double, speed: Double, duration: Double) {
        self.name = name
        self.step = step
        self.speed = speed
        self.duration = duration
        super.init()
    }
}

final class MenuController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let input = InputEngine.shared
    private let prefs = Preferences.shared

    private let presets: [PresetConfig] = [
        PresetConfig(name: "Mos Default", step: 33.6, speed: 2.70, duration: 4.35),
        PresetConfig(name: "Smooth", step: 35.0, speed: 2.50, duration: 4.50),
        PresetConfig(name: "Responsive", step: 30.0, speed: 3.00, duration: 3.50),
        PresetConfig(name: "Quick", step: 25.0, speed: 3.50, duration: 2.00)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        input.onStatusChanged = { [weak self] in self?.refreshStatus() }
        input.start()
        refreshStatus()
    }

    private func refreshStatus() {
        statusItem?.button?.title = input.isActive ? "R↕" : "R!"
        statusItem?.button?.toolTip = input.isActive
            ? "RapooFlow active" : "RapooFlow needs Accessibility permission"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(
            title: input.isActive ? "RapooFlow active" : "RapooFlow inactive",
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        addToggle(to: menu, "Smooth scrolling", prefs.smooth, #selector(toggleSmooth))
        addToggle(to: menu, "Natural scrolling (wheel)", prefs.reverse, #selector(toggleReverse))
        addToggle(to: menu, "Rapoo Forward → Paste, Back → Copy", prefs.buttonRemap, #selector(toggleButtons))
        menu.addItem(.separator())

        // Presets submenu
        let presetsMenuItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let presetsMenu = NSMenu()
        for preset in presets {
            let item = NSMenuItem(
                title: preset.name,
                action: #selector(setPreset(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            let matches = abs(prefs.step - preset.step) < 0.05 &&
                          abs(prefs.speed - preset.speed) < 0.05 &&
                          abs(prefs.duration - preset.duration) < 0.05
            item.state = matches ? .on : .off
            presetsMenu.addItem(item)
        }
        menu.setSubmenu(presetsMenu, for: presetsMenuItem)
        menu.addItem(presetsMenuItem)

        // Scroll duration submenu
        let duration = NSMenuItem(title: "Scroll duration", action: nil, keyEquivalent: "")
        let durationMenu = NSMenu()
        for value in [1.0, 2.0, 3.5, 4.35, 5.0] {
            let label = abs(value - 4.35) < 0.01 ? "4.35 s (Mos)" : String(format: "%.1f s", value)
            let item = NSMenuItem(
                title: label,
                action: #selector(setDuration(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(prefs.duration - value) < 0.05 ? .on : .off
            durationMenu.addItem(item)
        }
        menu.setSubmenu(durationMenu, for: duration)
        menu.addItem(duration)

        // Scroll distance submenu
        let distance = NSMenuItem(title: "Scroll distance", action: nil, keyEquivalent: "")
        let distanceMenu = NSMenu()
        for value in [20.0, 33.6, 50.0, 75.0] {
            let label = abs(value - 33.6) < 0.01 ? "33.6 px (Mos)" : "\(Int(value)) px"
            let item = NSMenuItem(
                title: label,
                action: #selector(setStep(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(prefs.step - value) < 0.05 ? .on : .off
            distanceMenu.addItem(item)
        }
        menu.setSubmenu(distanceMenu, for: distance)
        menu.addItem(distance)

        // Speed submenu
        let speed = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for value in [1.5, 2.70, 4.0, 6.0] {
            let label = abs(value - 2.70) < 0.01 ? "2.70 (Mos)" : String(format: "%.1f", value)
            let item = NSMenuItem(
                title: label,
                action: #selector(setSpeed(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value
            item.state = abs(prefs.speed - value) < 0.05 ? .on : .off
            speedMenu.addItem(item)
        }
        menu.setSubmenu(speedMenu, for: speed)
        menu.addItem(speed)

        menu.addItem(.separator())
        if let current = NSWorkspace.shared.frontmostApplication,
           let bundleID = current.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let excluded = prefs.excludedApps.contains(bundleID)
            let title = excluded
                ? "Use RapooFlow in \(current.localizedName ?? bundleID)"
                : "Exclude \(current.localizedName ?? bundleID)"
            let item = NSMenuItem(
                title: title, action: #selector(toggleCurrentApp(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = bundleID
            menu.addItem(item)
        }
        if !input.isActive {
            addAction(to: menu, "Grant Accessibility permission", #selector(requestPermission))
            addAction(to: menu, "Retry input monitor", #selector(retry))
        }
        menu.addItem(.separator())
        addAction(to: menu, "Quit RapooFlow", #selector(quit))
    }

    private func addToggle(to targetMenu: NSMenu, _ title: String, _ enabled: Bool, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.state = enabled ? .on : .off
        targetMenu.addItem(item)
    }

    private func addAction(to targetMenu: NSMenu, _ title: String, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        targetMenu.addItem(item)
    }

    @objc private func toggleSmooth() { prefs.smooth.toggle() }
    @objc private func toggleReverse() { prefs.reverse.toggle() }
    @objc private func toggleButtons() { prefs.buttonRemap.toggle() }
    @objc private func setPreset(_ item: NSMenuItem) {
        guard let preset = item.representedObject as? PresetConfig else { return }
        prefs.step = preset.step
        prefs.speed = preset.speed
        prefs.duration = preset.duration
    }
    @objc private func setDuration(_ item: NSMenuItem) {
        if let num = item.representedObject as? NSNumber {
            prefs.duration = num.doubleValue
        } else if let value = item.representedObject as? Double {
            prefs.duration = value
        }
    }
    @objc private func setStep(_ item: NSMenuItem) {
        if let num = item.representedObject as? NSNumber {
            prefs.step = num.doubleValue
        } else if let value = item.representedObject as? Double {
            prefs.step = value
        }
    }
    @objc private func setSpeed(_ item: NSMenuItem) {
        if let num = item.representedObject as? NSNumber {
            prefs.speed = num.doubleValue
        } else if let value = item.representedObject as? Double {
            prefs.speed = value
        }
    }
    @objc private func toggleCurrentApp(_ item: NSMenuItem) {
        guard let bundleID = item.representedObject as? String else { return }
        var excluded = prefs.excludedApps
        if excluded.contains(bundleID) { excluded.remove(bundleID) }
        else { excluded.insert(bundleID) }
        prefs.excludedApps = excluded
    }
    @objc private func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc private func retry() { input.start() }
    @objc private func quit() {
        input.stop()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let controller = MenuController()
app.delegate = controller
app.run()
