import Foundation
import AppKit
import ApplicationServices

// MARK: - Assertion Utilities

public func check(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "Assertion failed",
    file: StaticString = #file,
    line: UInt = #line
) {
    if !condition() {
        fatalError("FAIL [\(file):\(line)]: \(message)")
    }
}

public func assertEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    if actual != expected {
        fatalError("FAIL [\(file):\(line)]: Expected '\(expected)', got '\(actual)'. \(message)")
    }
}

public func assertNear(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double = 0.001,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    let diff = abs(actual - expected)
    if diff > accuracy {
        fatalError("FAIL [\(file):\(line)]: Expected '\(expected)' (±\(accuracy)), got '\(actual)' (diff: \(diff)). \(message)")
    }
}

public func assertMonotonic(
    _ sequence: [Double],
    expectedSign: Double,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    for (index, val) in sequence.enumerated() {
        if expectedSign > 0 && val < -1e-6 {
            fatalError("FAIL [\(file):\(line)]: Non-monotonic progression at index \(index): expected >= 0, got \(val). \(message)")
        } else if expectedSign < 0 && val > 1e-6 {
            fatalError("FAIL [\(file):\(line)]: Non-monotonic progression at index \(index): expected <= 0, got \(val). \(message)")
        }
    }
}

// MARK: - CGEvent Test Factory

public enum CGEventTestFactory {
    public static func makeScrollWheelEvent(
        deltaY: Int64 = 0,
        pointDeltaY: Double = 0.0,
        fixedPtDeltaY: Double = 0.0,
        deltaX: Int64 = 0,
        pointDeltaX: Double = 0.0,
        fixedPtDeltaX: Double = 0.0,
        isContinuous: Int64 = 0,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0,
        scrollCount: Int64 = 0,
        targetPID: pid_t = 1234,
        flags: CGEventFlags = []
    ) -> CGEvent {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else {
            fatalError("Failed to allocate CGEvent in memory")
        }

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: deltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pointDeltaY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixedPtDeltaY)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: deltaX)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaX)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtDeltaX)

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: isContinuous)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: scrollCount)

        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        event.flags = flags
        return event
    }

    public static func makeMouseEvent(
        type: CGEventType,
        buttonNumber: Int64,
        targetPID: pid_t = 1234
    ) -> CGEvent {
        let mouseType: CGMouseButton = buttonNumber == 0 ? .left : (buttonNumber == 1 ? .right : .center)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: 100, y: 100),
            mouseButton: mouseType
        ) else {
            fatalError("Failed to allocate mouse CGEvent in memory")
        }
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        return event
    }

    public static func makeKeyEvent(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        targetPID: pid_t = 1234
    ) -> CGEvent {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: (type == .keyDown)
        ) else {
            fatalError("Failed to allocate keyboard CGEvent in memory")
        }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        return event
    }
}

// MARK: - Reference Math Implementations (Derived from Mos & Requirements)

/// Authoritative reference implementation of Mos Interpolator math (Mos/ScrollCore/Interpolator.swift)
public enum SpecInterpolator {
    public static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        let x = dest - src
        return x * trans
    }

    public static func smoothStep2(src: Double, dest: Double) -> Double {
        let x = (dest - src) / dest
        return x * x * (3.0 - 2.0 * x)
    }

    public static func smoothStep3(src: Double, dest: Double) -> Double {
        let x = (dest - src) / dest
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }
}

/// Authoritative reference implementation of Mos 5-point polish jitter filter (Mos/ScrollCore/ScrollFilter.swift)
public final class SpecScrollFilter {
    public var curveWindowY = [0.0, 0.0]
    public var curveWindowX = [0.0, 0.0]

    public init() {}

    public func fill(with nextValue: (y: Double, x: Double)) -> (y: Double, x: Double) {
        curveWindowY = polish(curveWindowY, with: nextValue.y)
        curveWindowX = polish(curveWindowX, with: nextValue.x)
        return value()
    }

    public func value() -> (y: Double, x: Double) {
        return (y: curveWindowY[0], x: curveWindowX[0])
    }

    public func reset() {
        curveWindowY = [0.0, 0.0]
        curveWindowX = [0.0, 0.0]
    }

    public func polish(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first + 0.23 * diff, first + 0.5 * diff, first + 0.77 * diff, nextValue]
    }
}

// MARK: - Virtual Frame Stepper for Deterministic Clock Simulation

public struct FrameOutput {
    public let dy: Double
    public let dx: Double
    public let isSettled: Bool
    public let event: CGEvent?
}

/// Headless deterministic frame clock simulating 60Hz, 120Hz, 144Hz display interpolation
public final class VirtualFrameStepper {
    public static let syntheticMarker: Int64 = 0x5241504F4F464C57

    public var buffer: (y: Double, x: Double) = (0.0, 0.0)
    public var current: (y: Double, x: Double) = (0.0, 0.0)
    public var filter = SpecScrollFilter()
    public var deadZone: Double = 1.00
    public var durationTransition: Double = 0.085

    public var hasActiveMomentum: Bool {
        abs(buffer.y - current.y) > deadZone || abs(buffer.x - current.x) > deadZone
    }

    public init(deadZone: Double = 1.00, durationTransition: Double = 0.085) {
        self.deadZone = deadZone
        self.durationTransition = durationTransition
    }

    public func reset() {
        buffer = (0.0, 0.0)
        current = (0.0, 0.0)
        filter.reset()
    }

    public func addInput(y: Double, x: Double, step: Double, speed: Double, amplification: Double = 1.0) {
        let normalizedY = ScrollMotion.distance(point: y, fixed: 0, line: 0, minimum: step)
        let normalizedX = ScrollMotion.distance(point: x, fixed: 0, line: 0, minimum: step)

        let targetY = normalizedY * speed * amplification
        let targetX = normalizedX * speed * amplification

        // Instant opposite direction cancellation: overwrite buffer & zero current
        if targetY != 0 {
            if buffer.y * targetY < 0 {
                buffer.y = targetY
                current.y = 0.0
                filter.reset()
            } else {
                buffer.y += targetY
            }
        }

        if targetX != 0 {
            if buffer.x * targetX < 0 {
                buffer.x = targetX
                current.x = 0.0
                filter.reset()
            } else {
                buffer.x += targetX
            }
        }
    }

    public func stepFrame() -> FrameOutput {
        guard hasActiveMomentum else {
            reset()
            return FrameOutput(dy: 0.0, dx: 0.0, isSettled: true, event: nil)
        }

        let rawDeltaY = SpecInterpolator.lerp(src: current.y, dest: buffer.y, trans: durationTransition)
        let rawDeltaX = SpecInterpolator.lerp(src: current.x, dest: buffer.x, trans: durationTransition)

        let smoothed = filter.fill(with: (y: rawDeltaY, x: rawDeltaX))
        current.y += smoothed.y
        current.x += smoothed.x

        // DeadZone cutoff
        if abs(buffer.y - current.y) <= deadZone {
            current.y = buffer.y
        }
        if abs(buffer.x - current.x) <= deadZone {
            current.x = buffer.x
        }

        let isSettled = !hasActiveMomentum
        let synthEvent = CGEventTestFactory.makeScrollWheelEvent(
            deltaY: 0,
            pointDeltaY: smoothed.y,
            fixedPtDeltaY: smoothed.y / 10.0,
            deltaX: 0,
            pointDeltaX: smoothed.x,
            fixedPtDeltaX: smoothed.x / 10.0,
            isContinuous: 1
        )
        synthEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)

        return FrameOutput(dy: smoothed.y, dx: smoothed.x, isSettled: isSettled, event: synthEvent)
    }
}

// MARK: - Headless Event Pipeline Test Double (Specification Compliant)

public final class SpecificationEventPipeline {
    public static let syntheticMarker: Int64 = 0x5241504F4F464C57

    public var smooth: Bool = true
    public var reverse: Bool = true
    public var step: Double = 33.6
    public var speed: Double = 2.70
    public var buttonRemap: Bool = true
    public var excludedApps: Set<String> = []
    public var currentAppBundleID: String = "com.apple.finder"

    public var stepper = VirtualFrameStepper()
    public private(set) var dispatchedKeyCodes: [UInt16] = []
    public private(set) var recentRapooHIDTime: [Int64: CFAbsoluteTime] = [:]
    private var suppressedMouseUps = Set<Int64>()
    private var suppressedKeyUps = Set<Int64>()

    public init() {}

    public func reset() {
        stepper.reset()
        dispatchedKeyCodes.removeAll()
        recentRapooHIDTime.removeAll()
        suppressedMouseUps.removeAll()
        suppressedKeyUps.removeAll()
    }

    public func recordRapooHIDUsage(_ usage: Int64, time: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        if usage == 0x06 { recentRapooHIDTime[8] = time }
        if usage == 0x19 { recentRapooHIDTime[9] = time }
    }

    /// Process a CGEvent in memory, matching InputEngine pipeline specifications
    public func processEvent(_ event: CGEvent) -> (consumed: Bool, outputEvent: CGEvent?, dispatchedSynthetic: [CGEvent]) {
        // Synthetic loop prevention
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return (false, event, [])
        }

        // App exclusion check
        if excludedApps.contains(currentAppBundleID) {
            stepper.reset()
            return (false, event, [])
        }

        switch event.type {
        case .scrollWheel:
            return processScrollWheel(event)
        case .otherMouseDown, .otherMouseUp:
            return processMouseButton(event)
        case .keyDown, .keyUp:
            return processKey(event)
        case .leftMouseDown:
            // Left click momentum brake
            stepper.reset()
            return (false, event, [])
        default:
            return (false, event, [])
        }
    }

    private func processScrollWheel(_ event: CGEvent) -> (consumed: Bool, outputEvent: CGEvent?, dispatchedSynthetic: [CGEvent]) {
        // Trackpad isolation: any scrollPhase != 0, momentumPhase != 0, scrollCount != 0, or isContinuous != 0
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let scrollCount = event.getIntegerValueField(.scrollWheelEventScrollCount)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)

        if scrollPhase != 0 || momentumPhase != 0 || scrollCount != 0 || isContinuous != 0 {
            stepper.reset() // Halts mouse wheel momentum on trackpad gesture
            return (false, event, [])
        }

        let flags = event.flags
        let multiplier: Double = reverse ? -1.0 : 1.0
        let amp: Double = flags.contains(.maskAlternate) ? 5.0 : 1.0
        let shift: Bool = flags.contains(.maskShift) &&
            event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) == 0 &&
            event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0

        // Extract raw values
        var ptY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var fixY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        var lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))

        var ptX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        var fixX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

        // Apply 3-axis reversal & shift
        ptY *= multiplier
        fixY *= multiplier
        lineY *= multiplier

        ptX *= multiplier
        fixX *= multiplier
        lineX *= multiplier

        if shift {
            ptX = ptY; ptY = 0
            fixX = fixY; fixY = 0
            lineX = lineY; lineY = 0
        }

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(lineY))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: ptY)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixY)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lineX))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: ptX)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixX)

        // Command key bypasses smooth buffering while retaining reversal
        if flags.contains(.maskCommand) || !smooth {
            return (false, event, [])
        }

        // Add to smooth stepper
        let chosenY = ScrollMotion.distance(point: ptY, fixed: fixY, line: lineY, minimum: step)
        let chosenX = ScrollMotion.distance(point: ptX, fixed: fixX, line: lineX, minimum: step)

        stepper.addInput(y: chosenY, x: chosenX, step: step, speed: speed, amplification: amp)
        return (true, nil, [])
    }

    private func processMouseButton(_ event: CGEvent) -> (consumed: Bool, outputEvent: CGEvent?, dispatchedSynthetic: [CGEvent]) {
        guard buttonRemap else { return (false, event, []) }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard button == 3 || button == 4 else { return (false, event, []) }

        if event.type == .otherMouseDown {
            suppressedMouseUps.insert(button)
            let code: UInt16 = (button == 4) ? 9 : 8 // Forward -> Paste (9), Back -> Copy (8)
            dispatchedKeyCodes.append(code)
            return (true, nil, [])
        } else if event.type == .otherMouseUp {
            if suppressedMouseUps.remove(button) != nil {
                return (true, nil, [])
            }
        }
        return (false, event, [])
    }

    private func processKey(_ event: CGEvent) -> (consumed: Bool, outputEvent: CGEvent?, dispatchedSynthetic: [CGEvent]) {
        guard buttonRemap else { return (false, event, []) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 8 || code == 9 else { return (false, event, []) }

        if event.type == .keyUp {
            if suppressedKeyUps.remove(code) != nil { return (true, nil, []) }
            return (false, event, [])
        }

        guard event.flags.contains(.maskControl),
              let rawTime = recentRapooHIDTime[code],
              CFAbsoluteTimeGetCurrent() - rawTime < 0.12 else {
            return (false, event, [])
        }

        recentRapooHIDTime.removeValue(forKey: code)
        suppressedKeyUps.insert(code)
        dispatchedKeyCodes.append(UInt16(code))
        return (true, nil, [])
    }
}
