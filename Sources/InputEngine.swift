import AppKit
import ApplicationServices
import IOKit.hid
import CoreVideo

@available(macOS, deprecated: 15.0)
private final class LegacyDisplayLinkWrapper {
    private var link: CVDisplayLink?
    private var signal: DispatchSourceUserDataAdd?

    func start(onTick: @escaping () -> Void) -> Bool {
        if signal == nil {
            let s = DispatchSource.makeUserDataAddSource(queue: .main)
            s.setEventHandler(handler: onTick)
            s.resume()
            signal = s
        }
        if link == nil {
            var newLink: CVDisplayLink?
            guard CVDisplayLinkCreateWithActiveCGDisplays(&newLink) == kCVReturnSuccess,
                  let validLink = newLink else {
                return false
            }
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let status = CVDisplayLinkSetOutputCallback(validLink, { _, _, _, _, _, ctx in
                guard let ctx else { return kCVReturnSuccess }
                let wrapper = Unmanaged<LegacyDisplayLinkWrapper>.fromOpaque(ctx).takeUnretainedValue()
                wrapper.signal?.add(data: 1)
                return kCVReturnSuccess
            }, context)
            guard status == kCVReturnSuccess else { return false }
            link = validLink
        }
        guard let link else { return false }
        if CVDisplayLinkIsRunning(link) { return true }
        return CVDisplayLinkStart(link) == kCVReturnSuccess
    }

    func stop() {
        if let link, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        signal?.cancel()
        signal = nil
        link = nil
    }
}

final class InputEngine: NSObject {
    static let shared = InputEngine()
    static let syntheticMarker: Int64 = 0x5241504F4F464C57 // "RAPOOFLW"

    private var motion = ScrollMotion()
    private var scrollTemplate: CGEvent?
    private var scrollTarget: pid_t = 0
    private var lastFrameTime = 0.0
    private var lastInputTime = 0.0

    // Frame clock management
    private var caDisplayLink: Any?
    private var legacyDisplayLink: AnyObject?
    private var timer: Timer?

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    private var recentRapooKeys: [Int64: CFAbsoluteTime] = [:]
    private var suppressedKeyUps = Set<Int64>()
    private var suppressedMouseUps = Set<Int64>()
    private(set) var isActive = false
    var onStatusChanged: (() -> Void)?

    private var diagnosticInputs = 0
    private var diagnosticFrames = 0
    private func diagnostic(_ text: String) {
        let path = "/private/tmp/rapooflow-scroll-diagnostic.txt"
        let data = Data((text + "\n").utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil,
                attributes: [.posixPermissions: 0o600])
        }
        if let file = FileHandle(forWritingAtPath: path) {
            file.seekToEndOfFile()
            file.write(data)
            try? file.close()
        }
    }

    private override init() {
        super.init()
    }

    func start() {
        guard !isActive else { return }
        diagnostic("START revised-display-buffer reverse=\(Preferences.shared.reverse) smooth=\(Preferences.shared.smooth) step=\(Preferences.shared.step) speed=\(Preferences.shared.speed)")
        guard AXIsProcessTrusted() else {
            onStatusChanged?()
            return
        }

        let types: [CGEventType] = [
            .scrollWheel, .leftMouseDown, .otherMouseDown, .otherMouseUp,
            .keyDown, .keyUp
        ]
        let mask = types.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let newTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: InputEngine.eventCallback,
            userInfo: context
        ) else {
            onStatusChanged?()
            return
        }
        tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        startRapooMonitor()
        isActive = true
        onStatusChanged?()
    }

    func stop() {
        clearScroll()
        if #available(macOS 15.0, *) {
            if let link = caDisplayLink as? CADisplayLink {
                link.invalidate()
            }
            caDisplayLink = nil
        }
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        }
        tapSource = nil
        tap = nil
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
        recentRapooKeys.removeAll()
        suppressedKeyUps.removeAll()
        suppressedMouseUps.removeAll()
        isActive = false
        onStatusChanged?()
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<InputEngine>.fromOpaque(context).takeUnretainedValue()
        return engine.handle(type: type, event: event)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .scrollWheel:
            return handleScroll(event)
        case .leftMouseDown:
            clearScroll()
            return Unmanaged.passUnretained(event)
        case .otherMouseDown, .otherMouseUp:
            return handleMouseButton(type: type, event: event)
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func isExcludedApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Preferences.shared.excludedApps.contains(bundleID)
    }

    func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if diagnosticInputs < 16 {
            diagnosticInputs += 1
            let inverted = (event.copy().flatMap { NSEvent(cgEvent: $0) })?.isDirectionInvertedFromDevice ?? false
            diagnostic("INPUT continuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous)) phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) point=\(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)) fixed=\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)) line=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) target=\(event.getIntegerValueField(.eventTargetUnixProcessID)) inverted=\(inverted) reverse=\(Preferences.shared.reverse) smooth=\(Preferences.shared.smooth)")
        }

        // 1. Robust trackpad and continuous gesture isolation:
        // Pass through trackpad gestures and remote continuous streams untouched,
        // clearing any residual mouse wheel momentum.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 ||
           event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 ||
           event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 ||
           event.getDoubleValueField(.scrollWheelEventScrollCount) != 0.0 {
            clearScroll()
            return Unmanaged.passUnretained(event)
        }

        // Excluded app check: passes raw events through unmodified
        guard !isExcludedApp() else {
            clearScroll()
            return Unmanaged.passUnretained(event)
        }

        let prefs = Preferences.shared
        let flags = event.flags

        // Extract raw 3-axis scroll values BEFORE any NSEvent calls to ensure complete defensive isolation
        var lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var fixY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var ptY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

        var lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        var fixX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var ptX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)

        let natural = (event.copy().flatMap { NSEvent(cgEvent: $0) })?.isDirectionInvertedFromDevice ?? false
        let dir = ScrollMotion.direction(invertedBySystem: natural, natural: prefs.reverse)
        let amp: Double = flags.contains(.maskAlternate) ? 5.0 : 1.0

        // 2. Full 3-axis direction reversal
        ptY *= dir
        fixY *= dir
        lineY *= dir

        ptX *= dir
        fixX *= dir
        lineX *= dir

        // 3. Shift key axis swap (Toggle):
        // Swap vertical delta to horizontal if horizontal delta is zero
        let hasHorizontal = (ptX != 0.0 || fixX != 0.0 || lineX != 0.0)
        let isShift = flags.contains(.maskShift) && !hasHorizontal

        if isShift {
            ptX = ptY; ptY = 0.0
            fixX = fixY; fixY = 0.0
            lineX = lineY; lineY = 0.0
        }

        // 4. Critical setter ordering:
        // Always invoke setIntegerValueField(.scrollWheelEventDeltaAxis...) BEFORE
        // setDoubleValueField(.scrollWheelEventPointDeltaAxis...) to prevent CoreGraphics from clobbering pixel deltas.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(lineY))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: ptY)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lineX))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: ptX)

        // 5. Command key block (Smooth Bypass) & non-smooth mode:
        // Pass through raw reversed/swapped event directly to OS without buffering
        let isCommand = flags.contains(.maskCommand)
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))

        guard prefs.smooth, !isCommand, target > 0 else {
            clearScroll()
            return Unmanaged.passUnretained(event)
        }

        // Normalize distance using ScrollMotion.distance priority
        let chosenY = ScrollMotion.distance(point: ptY, fixed: fixY, line: lineY, minimum: prefs.step)
        let chosenX = ScrollMotion.distance(point: ptX, fixed: fixX, line: lineX, minimum: prefs.step)

        guard (chosenY != 0.0 || chosenX != 0.0) else {
            clearScroll()
            return Unmanaged.passUnretained(event)
        }

        guard let template = event.copy(), startFrameClock() else {
            clearScroll()
            return Unmanaged.passUnretained(event)
        }

        // Clean template deltas so synthetic continuous frames never inherit line deltas
        template.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        template.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        template.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
        template.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
        template.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
        template.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0.0)
        template.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        template.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)

        let now = CFAbsoluteTimeGetCurrent()
        if target != scrollTarget || now - lastInputTime > 0.5 {
            motion.reset()
        }
        scrollTemplate = template
        scrollTarget = target
        lastInputTime = now
        if !motion.hasActiveMomentum {
            lastFrameTime = now - 1.0 / 120.0
        }

        motion.addInput(
            y: chosenY,
            x: chosenX,
            step: prefs.step,
            speed: prefs.speed,
            amplification: amp
        )

        return nil
    }

    @objc private func caDisplayLinkDidFire(_ link: Any) {
        tick()
    }

    private func startFrameClock() -> Bool {
        if #available(macOS 15.0, *) {
            if caDisplayLink == nil, let screen = NSScreen.main {
                let link = screen.displayLink(target: self, selector: #selector(caDisplayLinkDidFire(_:)))
                link.add(to: .main, forMode: .common)
                caDisplayLink = link
            }
            if let link = caDisplayLink as? CADisplayLink {
                link.isPaused = false
                return true
            }
        } else {
            let legacy = (legacyDisplayLink as? LegacyDisplayLinkWrapper) ?? LegacyDisplayLinkWrapper()
            legacyDisplayLink = legacy
            if legacy.start(onTick: { [weak self] in self?.tick() }) {
                return true
            }
        }

        // Clock fallback keeps scrolling available after display reconnect or headless execution
        if timer == nil {
            let clock = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(clock, forMode: .common)
            timer = clock
        }
        return timer != nil
    }

    private func stopFrameClock() {
        if #available(macOS 15.0, *) {
            if let link = caDisplayLink as? CADisplayLink {
                link.isPaused = true
            }
        } else {
            if let legacy = legacyDisplayLink as? LegacyDisplayLinkWrapper {
                legacy.stop()
            }
            legacyDisplayLink = nil
        }
        timer?.invalidate()
        timer = nil
    }

    private func clearScroll() {
        stopFrameClock()
        motion.reset()
        scrollTemplate = nil
        scrollTarget = 0
        lastFrameTime = 0
    }

    private func tick() {
        guard let template = scrollTemplate, scrollTarget > 0,
              Preferences.shared.smooth else {
            clearScroll()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastInputTime < 2.0, now - lastFrameTime < 0.25 else {
            clearScroll()
            return
        }
        guard let frameDelta = motion.advanceFrame(
            durationTransition: Preferences.shared.durationTransition,
            deadZone: Preferences.shared.deadZone
        ) else {
            clearScroll()
            return
        }
        lastFrameTime = now

        guard let frame = template.copy() else { clearScroll(); return }
        frame.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        frame.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        frame.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        frame.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        frame.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: frameDelta.dy)
        frame.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: frameDelta.dx)
        frame.timestamp = DispatchTime.now().uptimeNanoseconds

        if diagnosticFrames < 8 {
            diagnosticFrames += 1
            diagnostic("FRAME y=\(frameDelta.dy) target=\(scrollTarget)")
        }
        frame.postToPid(scrollTarget)
        if !motion.hasActiveMomentum {
            clearScroll()
        }
    }

    private func handleMouseButton(
        type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard Preferences.shared.buttonRemap, !isExcludedApp() else {
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard button == 3 || button == 4 else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseDown {
            suppressedMouseUps.insert(button)
            postCommandKey(button == 4 ? 9 : 8) // Forward Paste, Back Copy
            return nil
        }
        if suppressedMouseUps.remove(button) != nil { return nil }
        return Unmanaged.passUnretained(event)
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Preferences.shared.buttonRemap, !isExcludedApp() else {
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 8 || code == 9 else { return Unmanaged.passUnretained(event) }
        if type == .keyUp {
            if suppressedKeyUps.remove(code) != nil { return nil }
            return Unmanaged.passUnretained(event)
        }
        guard event.flags.contains(.maskControl),
              let rawTime = recentRapooKeys[code],
              CFAbsoluteTimeGetCurrent() - rawTime < 0.12 else {
            return Unmanaged.passUnretained(event)
        }
        recentRapooKeys.removeValue(forKey: code)
        suppressedKeyUps.insert(code)
        postCommandKey(UInt16(code))
        return nil
    }

    private func postCommandKey(_ code: UInt16) {
        DispatchQueue.main.async {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: false) else {
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func startRapooMonitor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x24ae,
            kIOHIDPrimaryUsagePageKey as String: 1,
            kIOHIDPrimaryUsageKey as String: 6
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(manager, InputEngine.hidCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            hidManager = manager
        } else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
        }
    }

    private static let hidCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let engine = Unmanaged<InputEngine>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 7,
              IOHIDValueGetIntegerValue(value) == 1 else { return }
        let usage = IOHIDElementGetUsage(element)
        if usage == 0x06 {
            engine.recentRapooKeys[8] = CFAbsoluteTimeGetCurrent()
        } else if usage == 0x19 {
            engine.recentRapooKeys[9] = CFAbsoluteTimeGetCurrent()
        }
    }
}
