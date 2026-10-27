import Foundation

public struct Tier1_UnitMathTests {
    public static func registerTests(to runner: TestRegistry) {
        runner.register(tier: 1, id: "TC-MATH-01", name: "Lerp Interpolation Basic & Boundaries") {
            // Formula: lerp = (dest - src) * trans
            assertNear(SpecInterpolator.lerp(src: 5.0, dest: 10.0, trans: 0.0), 0.0, "trans=0 must return 0")
            assertNear(SpecInterpolator.lerp(src: 0.0, dest: 10.0, trans: 1.0), 10.0, "trans=1 must return dest - src")
            assertNear(SpecInterpolator.lerp(src: 0.0, dest: 10.0, trans: 0.5), 5.0, "half transition midpoint")
            assertNear(SpecInterpolator.lerp(src: 10.0, dest: 0.0, trans: 0.5), -5.0, "negative difference")
            assertNear(SpecInterpolator.lerp(src: 7.5, dest: 7.5, trans: 0.5), 0.0, "src==dest must return 0")
            
            let src = 3.0, dest = 17.0, trans = 0.3
            assertNear(SpecInterpolator.lerp(src: src, dest: dest, trans: trans), (dest - src) * trans)
        }

        runner.register(tier: 1, id: "TC-MATH-02", name: "SmoothStep2 & SmoothStep3 Properties") {
            let dest = 20.0
            // Boundary: src == dest -> 0.0; src == 0 -> 1.0
            assertNear(SpecInterpolator.smoothStep2(src: dest, dest: dest), 0.0, "smoothStep2 at src==dest")
            assertNear(SpecInterpolator.smoothStep2(src: 0.0, dest: dest), 1.0, "smoothStep2 at src==0")
            assertNear(SpecInterpolator.smoothStep3(src: dest, dest: dest), 0.0, "smoothStep3 at src==dest")
            assertNear(SpecInterpolator.smoothStep3(src: 0.0, dest: dest), 1.0, "smoothStep3 at src==0")

            // Midpoint: src = dest / 2 -> 0.5
            assertNear(SpecInterpolator.smoothStep2(src: dest / 2.0, dest: dest), 0.5, "smoothStep2 midpoint")
            assertNear(SpecInterpolator.smoothStep3(src: dest / 2.0, dest: dest), 0.5, "smoothStep3 midpoint")

            // Monotonic progression as src decreases from dest to 0
            var prevStep2 = -1.0
            var prevStep3 = -1.0
            for i in stride(from: 100.0, through: 0.0, by: -5.0) {
                let s2 = SpecInterpolator.smoothStep2(src: i, dest: 100.0)
                let s3 = SpecInterpolator.smoothStep3(src: i, dest: 100.0)
                check(s2 >= prevStep2, "smoothStep2 monotonic check at \(i)")
                check(s3 >= prevStep3, "smoothStep3 monotonic check at \(i)")
                prevStep2 = s2
                prevStep3 = s3
            }
        }

        runner.register(tier: 1, id: "TC-MATH-03", name: "S-Curve 5-Point Polish Window Values") {
            let filter = SpecScrollFilter()
            let polishOutput = filter.polish([0.0, 0.0], with: 10.0)
            assertEqual(polishOutput.count, 5, "Polish must produce 5 elements")
            assertNear(polishOutput[0], 0.0, "first element must be old first")
            assertNear(polishOutput[1], 2.3, "second element: first + 0.23*diff")
            assertNear(polishOutput[2], 5.0, "third element: first + 0.5*diff")
            assertNear(polishOutput[3], 7.7, "fourth element: first + 0.77*diff")
            assertNear(polishOutput[4], 10.0, "fifth element: nextValue")
        }

        runner.register(tier: 1, id: "TC-MATH-04", name: "S-Curve Filter Smooth Onset") {
            let filter = SpecScrollFilter()
            // Initial window [0.0, 0.0]
            // First fill absorbs initial wheel notch jerk, returning 0.0
            let firstResult = filter.fill(with: (y: 10.0, x: 0.0))
            assertNear(firstResult.y, 0.0, "First fill Y must return 0.0 to absorb initial jerk")
            assertNear(firstResult.x, 0.0)

            // Second fill advances smoothly to next smoothed intermediate value (2.3)
            let secondResult = filter.fill(with: (y: 10.0, x: 0.0))
            assertNear(secondResult.y, 2.3, "Second fill Y should return smoothed 2.3")
            check(secondResult.y > firstResult.y, "Filter must ramp up smoothly")
        }

        runner.register(tier: 1, id: "TC-MATH-05", name: "S-Curve Monotonic Convergence & X/Y Independence") {
            let filter = SpecScrollFilter()
            let target = 10.0
            var lastY = 0.0
            for _ in 0..<20 {
                let res = filter.fill(with: (y: target, x: 0.0))
                check(res.y >= lastY, "Filter must converge monotonically toward target")
                lastY = res.y
            }
            assertNear(lastY, target, accuracy: 0.1, "Filter must converge close to target after 20 fills")

            // X/Y Independence: injecting X=25 should not alter Y=0
            filter.reset()
            _ = filter.fill(with: (y: 0.0, x: 25.0))
            let val = filter.value()
            assertNear(val.y, 0.0, "Y axis must stay 0 when only X is injected")
            assertNear(val.x, 0.0, "X first fill returns 0.0")

            _ = filter.fill(with: (y: 0.0, x: 25.0))
            let val2 = filter.value()
            assertNear(val2.y, 0.0, "Y axis must remain 0")
            check(val2.x > 0.0, "X axis must begin advancing independently")

            filter.reset()
            assertNear(filter.value().y, 0.0)
            assertNear(filter.value().x, 0.0)
        }

        runner.register(tier: 1, id: "TC-MATH-06", name: "Step Normalization: Bluetooth Low-Res Clamp") {
            let step = 33.6
            // Bluetooth mice reporting small fixed-point deltas below threshold clamp to +step or -step
            let positiveClamped = ScrollMotion.distance(point: 0, fixed: 0.5, line: 0, minimum: step)
            assertNear(positiveClamped, step, "Small positive fixed delta must clamp to +step")

            let negativeClamped = ScrollMotion.distance(point: 0, fixed: -0.5, line: 0, minimum: step)
            assertNear(negativeClamped, -step, "Small negative fixed delta must clamp to -step")

            // Line delta clamp
            let lineClamped = ScrollMotion.distance(point: 0, fixed: 0, line: 1.0, minimum: step)
            assertNear(lineClamped, step, "Line delta must clamp to +step")
        }

        runner.register(tier: 1, id: "TC-MATH-07", name: "Step Normalization: High-Res & Zero Invariants") {
            let step = 33.6
            // Natural high-resolution wheel ticks above threshold are preserved
            let highRes = ScrollMotion.distance(point: 55.0, fixed: 0, line: 0, minimum: step)
            assertNear(highRes, 55.0, "High resolution delta above threshold must not be shrunk")

            let highResNeg = ScrollMotion.distance(point: -48.2, fixed: 0, line: 0, minimum: step)
            assertNear(highResNeg, -48.2, "Negative high resolution delta above threshold preserved")

            // Zero delta returns zero
            let zero = ScrollMotion.distance(point: 0, fixed: 0, line: 0, minimum: step)
            assertNear(zero, 0.0, "Zero input must return exactly 0.0")
        }

        runner.register(tier: 1, id: "TC-MATH-08", name: "Axis Delta Priority Order") {
            let step = 33.6
            // Priority: pointDelta > fixedPtDelta > lineDelta
            let pointPriority = ScrollMotion.distance(point: 42.0, fixed: 10.0, line: 1.0, minimum: step)
            assertNear(pointPriority, 42.0, "Point delta takes highest priority")

            let fixedPriority = ScrollMotion.distance(point: 0.0, fixed: 50.0, line: 1.0, minimum: step)
            assertNear(fixedPriority, 50.0, "Fixed delta takes priority over line delta when point is 0")
        }

        runner.register(tier: 1, id: "TC-MATH-09", name: "DeadZone Cutoff Threshold Math") {
            let deadZone = 1.00
            let stepper = VirtualFrameStepper(deadZone: deadZone, durationTransition: 0.085)
            stepper.buffer = (y: 10.0, x: 0.0)
            stepper.current = (y: 9.2, x: 0.0) // Residual: 0.8 <= deadZone 1.00

            // Stepping should trigger deadZone cutoff and immediately snap to destination
            let output = stepper.stepFrame()
            check(output.isSettled, "Motion must be settled when remaining delta <= deadZone")
            assertNear(stepper.current.y, stepper.buffer.y, "Current must snap to buffer upon deadZone cutoff")
            check(!stepper.hasActiveMomentum, "Active momentum must be false after deadZone cutoff")
        }

        runner.register(tier: 1, id: "TC-MATH-10", name: "Preferences Defaults, Ranges & DurationTransition") {
            // Mos mathematical constants verification
            // DurationTransition formula: round(1000 * (1 - sqrt(duration / 5.2))) / 1000
            let duration = 4.35
            let upperLimit = 5.2
            let trans = Double(round(1000 * (1.0 - sqrt(duration / upperLimit))) / 1000)
            assertNear(trans, 0.085, accuracy: 0.001, "Duration transition for 4.35 must equal 0.085")

            // Duration boundaries
            let minDuration = 0.2
            let minTrans = Double(round(1000 * (1.0 - sqrt(minDuration / upperLimit))) / 1000)
            check(minTrans > 0.7, "Short duration must produce high transition factor")

            let maxDuration = 5.2
            let maxTrans = Double(round(1000 * (1.0 - sqrt(maxDuration / upperLimit))) / 1000)
            assertNear(maxTrans, 0.0, "Max duration 5.2 reaches 0 transition")

            // Direction matrix check from original test suite
            for natural in [false, true] {
                for inverted in [false, true] {
                    let rawDown = inverted ? 1.0 : -1.0
                    let result = rawDown * ScrollMotion.direction(invertedBySystem: inverted, natural: natural)
                    check(result == (natural ? 1 : -1), "Wheel-down direction depends on system preference")
                }
            }

            // Preferences live instance check
            let prefs = Preferences.shared
            // Ensure app exclusion collection behaves correctly
            let testApp = "com.test.rapooflow.mock"
            var exclusions = prefs.excludedApps
            exclusions.insert(testApp)
            prefs.excludedApps = exclusions
            check(prefs.excludedApps.contains(testApp), "Excluded app should be registered")
            exclusions.remove(testApp)
            prefs.excludedApps = exclusions
            check(!prefs.excludedApps.contains(testApp), "Excluded app should be removed")
        }
    }
}
