import Foundation
import AppKit

public final class Preferences {
    public static let shared = Preferences()
    private let store = UserDefaults.standard

    public init() {
        store.register(defaults: [
            "smooth": true,
            "reverse": true,
            "buttonRemap": true,
            "step": 33.6,
            "speed": 2.70,
            "duration": 4.35,
            "deadZone": 1.00,
            "excludedApps": []
        ])
    }

    public var smooth: Bool {
        get { store.object(forKey: "smooth") == nil ? true : store.bool(forKey: "smooth") }
        set { store.set(newValue, forKey: "smooth") }
    }
    public var reverse: Bool {
        get { store.object(forKey: "reverse") == nil ? true : store.bool(forKey: "reverse") }
        set { store.set(newValue, forKey: "reverse") }
    }
    public var buttonRemap: Bool {
        get { store.object(forKey: "buttonRemap") == nil ? true : store.bool(forKey: "buttonRemap") }
        set { store.set(newValue, forKey: "buttonRemap") }
    }
    public var step: Double {
        get {
            let val = store.object(forKey: "step") == nil ? 33.6 : store.double(forKey: "step")
            return max(10.0, min(100.0, val))
        }
        set { store.set(max(10.0, min(100.0, newValue)), forKey: "step") }
    }
    public var speed: Double {
        get {
            let val = store.object(forKey: "speed") == nil ? 2.70 : store.double(forKey: "speed")
            return max(1.0, min(10.0, val))
        }
        set { store.set(max(1.0, min(10.0, newValue)), forKey: "speed") }
    }
    public var duration: Double {
        get {
            let val = store.object(forKey: "duration") == nil ? 4.35 : store.double(forKey: "duration")
            return max(0.2, min(5.0, val))
        }
        set { store.set(max(0.2, min(5.0, newValue)), forKey: "duration") }
    }
    public var deadZone: Double {
        get {
            let val = store.object(forKey: "deadZone") == nil ? 1.00 : store.double(forKey: "deadZone")
            return max(0.0, val)
        }
        set { store.set(max(0.0, newValue), forKey: "deadZone") }
    }
    public var durationTransition: Double {
        let raw = Double(round(1000 * (1.0 - sqrt(duration / 5.2))) / 1000)
        return max(0.010, raw)
    }
    public var excludedApps: Set<String> {
        get { Set(store.stringArray(forKey: "excludedApps") ?? []) }
        set { store.set(Array(newValue).sorted(), forKey: "excludedApps") }
    }
    public var excludedBundleIdentifiers: Set<String> {
        get { excludedApps }
        set { excludedApps = newValue }
    }
    public var isEnabledForActiveApp: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        return !excludedApps.contains(bundleID)
    }

    // Static accessors matching PROJECT.md interface contract
    public static var step: Double {
        get { shared.step }
        set { shared.step = newValue }
    }
    public static var speed: Double {
        get { shared.speed }
        set { shared.speed = newValue }
    }
    public static var duration: Double {
        get { shared.duration }
        set { shared.duration = newValue }
    }
    public static var reverse: Bool {
        get { shared.reverse }
        set { shared.reverse = newValue }
    }
    public static var smooth: Bool {
        get { shared.smooth }
        set { shared.smooth = newValue }
    }
    public static var deadZone: Double {
        get { shared.deadZone }
        set { shared.deadZone = newValue }
    }
    public static var durationTransition: Double {
        shared.durationTransition
    }
    public static var isEnabledForActiveApp: Bool {
        shared.isEnabledForActiveApp
    }
    public static var excludedApps: Set<String> {
        get { shared.excludedApps }
        set { shared.excludedApps = newValue }
    }
    public static var excludedBundleIdentifiers: Set<String> {
        get { shared.excludedBundleIdentifiers }
        set { shared.excludedBundleIdentifiers = newValue }
    }
}
