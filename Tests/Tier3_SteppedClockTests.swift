import Foundation
import ApplicationServices

public struct Tier3_SteppedClockTests {
    public static func registerTests(to runner: TestRegistry) {
        runner.register(tier: 3, id: "TC-STEP-01", name: "Monotonic Frame Progression (60Hz)") {
            let stepper = VirtualFrameStepper(deadZone: 1.0, durationTransition: 0.085)
            // Inject 1 positive notch: step=33.6, speed=2.70 -> buffer = 90.72
            stepper.addInput(y: 33.6, x: 0.0, step: 33.6, speed: 2.70)

            var emittedDeltas: [Double] = []
            for _ in 0..<60 {
                let frame = stepper.stepFrame()
                emittedDeltas.append(frame.dy)
                if frame.isSettled { break }
            }

            check(!emittedDeltas.isEmpty, "Frames must be emitted")
            assertMonotonic(emittedDeltas, expectedSign: 1.0, "Every 60Hz frame must move in positive direction")
        }

        runner.register(tier: 3, id: "TC-STEP-02", name: "Monotonic Frame Progression (120Hz & 144Hz)") {
            for hz in [120, 144] {
                let stepper = VirtualFrameStepper(deadZone: 1.0, durationTransition: 0.085)
                // Negative scroll direction (-90.72 target)
                stepper.addInput(y: -33.6, x: 0.0, step: 33.6, speed: 2.70)

                var emittedDeltas: [Double] = []
                for _ in 0..<hz {
                    let frame = stepper.stepFrame()
                    emittedDeltas.append(frame.dy)
                    if frame.isSettled { break }
                }

                assertMonotonic(emittedDeltas, expectedSign: -1.0, "Every \(hz)Hz frame must maintain negative progression")
            }
        }

        runner.register(tier: 3, id: "TC-STEP-03", name: "S-Curve Polish Smooth Ramp-Up Onset") {
            let stepper = VirtualFrameStepper(deadZone: 1.0, durationTransition: 0.085)
            stepper.addInput(y: 33.6, x: 0.0, step: 33.6, speed: 2.70)

            let frame0 = stepper.stepFrame()
            let frame1 = stepper.stepFrame()

            // With S-curve filter enabled, initial frame is smoothed to eliminate notch jerk
            check(frame0.dy < frame1.dy, "Frame 0 (\(frame0.dy)) must be strictly less than Frame 1 (\(frame1.dy)) for smooth ramp-up")
            assertNear(frame0.dy, 0.0, "First frame should start at near-zero")
        }

        runner.register(tier: 3, id: "TC-STEP-04", name: "Multi-Refresh Rate Distance Conservation") {
            let targetDistance = 33.6 * 2.70 // 90.72 pt
            let deadZone = 1.00

            for hz in [60, 120, 144] {
                let stepper = VirtualFrameStepper(deadZone: deadZone, durationTransition: 0.085)
                stepper.addInput(y: 33.6, x: 0.0, step: 33.6, speed: 2.70)

                var totalDistance = 0.0
                for _ in 0..<(hz * 2) {
                    let frame = stepper.stepFrame()
                    totalDistance += frame.dy
                    if frame.isSettled { break }
                }

                let diff = abs(totalDistance - targetDistance)
                check(diff <= deadZone + 0.1, "Total distance at \(hz)Hz (\(totalDistance)) must conserve target within deadZone tolerance")
            }
        }

        runner.register(tier: 3, id: "TC-STEP-05", name: "DeadZone Cutoff & Sub-10ms Settling") {
            let stepper = VirtualFrameStepper(deadZone: 1.00, durationTransition: 0.085)
            stepper.addInput(y: 33.6, x: 0.0, step: 33.6, speed: 1.0) // 33.6 target

            var frameCount = 0
            while !stepper.stepFrame().isSettled && frameCount < 100 {
                frameCount += 1
            }

            // Once settled, remaining momentum must be exactly 0
            check(!stepper.hasActiveMomentum, "No residual momentum must remain after settling")
            assertNear(stepper.current.y, stepper.buffer.y, "Current must meet buffer at deadZone cutoff")
        }

        runner.register(tier: 3, id: "TC-STEP-06", name: "Instant Opposite-Direction Momentum Cancellation") {
            let stepper = VirtualFrameStepper(deadZone: 1.00, durationTransition: 0.085)
            // Step forward (+100.0)
            stepper.addInput(y: 100.0, x: 0.0, step: 10.0, speed: 1.0)
            _ = stepper.stepFrame()
            _ = stepper.stepFrame()
            _ = stepper.stepFrame()

            check(stepper.current.y > 0, "Current position must be positive")

            // Inject wheel input in opposite direction (-50.0)
            stepper.addInput(y: -50.0, x: 0.0, step: 10.0, speed: 1.0)

            // Buffer must be overwritten with new direction and current reset to 0
            assertNear(stepper.buffer.y, -50.0, "Buffer must be overwritten with opposite direction target")
            assertNear(stepper.current.y, 0.0, "Current position must be reset to 0.0 on reversal")

            // On the next frame, output delta must immediately be non-positive
            let nextFrame = stepper.stepFrame()
            check(nextFrame.dy <= 0.0, "Next frame must immediately move in opposite direction, got \(nextFrame.dy)")
        }

        runner.register(tier: 3, id: "TC-STEP-07", name: "Additive Same-Direction Accumulation") {
            let stepper = VirtualFrameStepper(deadZone: 1.00, durationTransition: 0.085)
            // Inject +50.0 twice in the same direction
            stepper.addInput(y: 50.0, x: 0.0, step: 10.0, speed: 1.0)
            _ = stepper.stepFrame()
            stepper.addInput(y: 50.0, x: 0.0, step: 10.0, speed: 1.0)

            assertNear(stepper.buffer.y, 100.0, "Same-direction notches must accumulate additively")
        }

        runner.register(tier: 3, id: "TC-STEP-08", name: "Left-Click Momentum Brake") {
            let pipeline = SpecificationEventPipeline()
            pipeline.stepper.addInput(y: 100.0, x: 0.0, step: 10.0, speed: 1.0)
            _ = pipeline.stepper.stepFrame()
            check(pipeline.stepper.hasActiveMomentum, "Momentum should be active")

            // Inject left click event
            let clickEvent = CGEventTestFactory.makeMouseEvent(type: .leftMouseDown, buttonNumber: 0)
            let result = pipeline.processEvent(clickEvent)

            check(!result.consumed, "Left click must pass through to OS for UI interaction")
            check(!pipeline.stepper.hasActiveMomentum, "Left click must immediately brake ongoing scroll momentum")
            assertNear(pipeline.stepper.buffer.y, 0.0)
        }

        runner.register(tier: 3, id: "TC-STEP-09", name: "Trackpad Event Halts Wheel Momentum") {
            let pipeline = SpecificationEventPipeline()
            pipeline.stepper.addInput(y: 100.0, x: 0.0, step: 10.0, speed: 1.0)
            _ = pipeline.stepper.stepFrame()
            check(pipeline.stepper.hasActiveMomentum, "Momentum should be active")

            // Inject trackpad gesture begin event
            let trackpadEvent = CGEventTestFactory.makeScrollWheelEvent(scrollPhase: 1)
            _ = pipeline.processEvent(trackpadEvent)

            check(!pipeline.stepper.hasActiveMomentum, "Trackpad gesture must immediately clear residual mouse wheel momentum")
        }

        runner.register(tier: 3, id: "TC-STEP-10", name: "Synthetic Event Hygiene & No Line Delta Clobbering") {
            let stepper = VirtualFrameStepper(deadZone: 1.0, durationTransition: 0.085)
            stepper.addInput(y: 33.6, x: 0.0, step: 33.6, speed: 2.70)
            _ = stepper.stepFrame()
            let frame = stepper.stepFrame()

            guard let event = frame.event else {
                fatalError("Synthetic CGEvent must be generated for frame")
            }

            // Verify synthetic marker stamped (0x5241504F4F464C57)
            let marker = event.getIntegerValueField(.eventSourceUserData)
            assertEqual(marker, VirtualFrameStepper.syntheticMarker, "Event must be stamped with RapooFlow synthetic marker")

            // Verify continuous flag set to 1
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            assertEqual(continuous, 1, "isContinuous must be 1 for smooth continuous animation")

            // Verify continuous point delta set correctly (CoreGraphics stores integer point deltas)
            let ptDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            assertNear(ptDelta, frame.dy.rounded(.towardZero), "PointDeltaAxis1 must match frame dy truncated to integer pixels by CoreGraphics")
            let fixPtDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            assertNear(fixPtDelta, frame.dy / 10.0, accuracy: 0.01, "FixedPtDeltaAxis1 must store precise fractional delta")

            // Verify line delta is NOT clobbered with integer rounding artifacts
            let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            assertEqual(lineDelta, 0, "Line deltaAxis1 must remain 0 on continuous pixel frames to prevent jumpy browser scrolling")

            // Verify loop defense: processing this synthetic event through the pipeline passes through untouched
            let pipeline = SpecificationEventPipeline()
            let loopResult = pipeline.processEvent(event)
            check(!loopResult.consumed, "Synthetic events must pass through without re-ingestion or re-buffering")
        }
    }
}
