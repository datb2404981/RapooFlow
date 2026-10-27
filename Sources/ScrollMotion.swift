import Foundation

// MARK: - Mos Interpolator

public enum Interpolator {
    public static func lerp(src: Double, dest: Double, trans: Double) -> Double {
        let x = dest - src
        return x * trans
    }
}

// MARK: - Mos 5-Point S-Curve Polish Filter

public final class ScrollFilter {
    public var curveWindowY: [Double] = [0.0, 0.0]
    public var curveWindowX: [Double] = [0.0, 0.0]

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

// MARK: - ScrollMotion Core Motion Engine

public final class ScrollMotion {
    public var buffer: (y: Double, x: Double) = (0.0, 0.0)
    public var current: (y: Double, x: Double) = (0.0, 0.0)
    public var delta: (y: Double, x: Double) = (0.0, 0.0)
    public var filter = ScrollFilter()
    public var deadZone: Double = 1.00

    public var hasActiveMomentum: Bool {
        abs(buffer.y - current.y) > deadZone || abs(buffer.x - current.x) > deadZone
    }

    public var isEmpty: Bool {
        !hasActiveMomentum
    }

    public var y: Double { buffer.y - current.y }
    public var x: Double { buffer.x - current.x }

    public init(deadZone: Double = 1.00) {
        self.deadZone = deadZone
    }

    public func reset() {
        buffer = (0.0, 0.0)
        current = (0.0, 0.0)
        delta = (0.0, 0.0)
        filter.reset()
    }

    public func brake() {
        reset()
    }

    public func stop() {
        reset()
    }

    public func addInput(y: Double, x: Double, step: Double, speed: Double, amplification: Double = 1.0) {
        if !hasActiveMomentum {
            buffer = (0.0, 0.0)
            current = (0.0, 0.0)
            delta = (0.0, 0.0)
            filter.reset()
        }

        let normalizedY = ScrollMotion.distance(point: y, fixed: 0, line: 0, minimum: step)
        let normalizedX = ScrollMotion.distance(point: x, fixed: 0, line: 0, minimum: step)

        let targetY = normalizedY * speed * amplification
        let targetX = normalizedX * speed * amplification

        if targetY != 0 {
            if (y * delta.y <= 0) || (buffer.y * targetY < 0) {
                buffer.y = targetY
                current.y = 0.0
                filter.curveWindowY = [0.0, 0.0]
            } else {
                buffer.y += targetY
            }
            buffer.y = max(-8000.0, min(8000.0, buffer.y))
            delta.y = y
        }

        if targetX != 0 {
            if (x * delta.x <= 0) || (buffer.x * targetX < 0) {
                buffer.x = targetX
                current.x = 0.0
                filter.curveWindowX = [0.0, 0.0]
            } else {
                buffer.x += targetX
            }
            buffer.x = max(-8000.0, min(8000.0, buffer.x))
            delta.x = x
        }
    }

    // Compatibility method for existing InputEngine.swift caller
    public func add(y dy: Double, x dx: Double) {
        if !hasActiveMomentum {
            buffer = (0.0, 0.0)
            current = (0.0, 0.0)
            delta = (0.0, 0.0)
            filter.reset()
        }

        if dy != 0 {
            if (dy * delta.y <= 0) || (buffer.y * dy < 0) {
                buffer.y = dy
                current.y = 0.0
                filter.curveWindowY = [0.0, 0.0]
            } else {
                buffer.y += dy
            }
            buffer.y = max(-8000.0, min(8000.0, buffer.y))
            delta.y = dy
        }

        if dx != 0 {
            if (dx * delta.x <= 0) || (buffer.x * dx < 0) {
                buffer.x = dx
                current.x = 0.0
                filter.curveWindowX = [0.0, 0.0]
            } else {
                buffer.x += dx
            }
            buffer.x = max(-8000.0, min(8000.0, buffer.x))
            delta.x = dx
        }
    }

    @discardableResult
    public func advanceFrame() -> (dy: Double, dx: Double)? {
        advanceFrame(durationTransition: Preferences.shared.durationTransition, deadZone: Preferences.shared.deadZone)
    }

    @discardableResult
    public func advanceFrame(durationTransition: Double, deadZone: Double) -> (dy: Double, dx: Double)? {
        guard hasActiveMomentum else {
            reset()
            return nil
        }

        let rawDeltaY = Interpolator.lerp(src: current.y, dest: buffer.y, trans: durationTransition)
        let rawDeltaX = Interpolator.lerp(src: current.x, dest: buffer.x, trans: durationTransition)

        let smoothed = filter.fill(with: (y: rawDeltaY, x: rawDeltaX))
        current.y += rawDeltaY
        current.x += rawDeltaX

        if abs(buffer.y - current.y) <= deadZone {
            current.y = buffer.y
        }
        if abs(buffer.x - current.x) <= deadZone {
            current.x = buffer.x
        }

        return (dy: smoothed.y, dx: smoothed.x)
    }

    // Compatibility method for existing InputEngine.swift caller
    public func advance(seconds: Double, response: Double) -> (y: Double, x: Double) {
        let trans = Preferences.shared.durationTransition
        let dz = Preferences.shared.deadZone
        if let frame = advanceFrame(durationTransition: trans, deadZone: dz) {
            return (y: frame.dy, x: frame.dx)
        }
        return (y: 0.0, x: 0.0)
    }

    public static func direction(invertedBySystem: Bool, natural: Bool) -> Double {
        invertedBySystem == natural ? 1 : -1
    }

    public static func distance(point: Double, fixed: Double, line: Double, minimum: Double) -> Double {
        let value = point != 0 ? point : (fixed != 0 ? fixed : line)
        guard value.isFinite, value != 0 else { return 0 }
        return (value > 0 ? 1 : -1) * max(abs(value), minimum)
    }
}
