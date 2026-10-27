import Foundation
import ApplicationServices

public struct Tier2_EventPipelineTests {
    public static func registerTests(to runner: TestRegistry) {
        runner.register(tier: 2, id: "TC-PIPE-01", name: "Trackpad Scroll Phase Began Isolation") {
            let pipeline = SpecificationEventPipeline()
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -2,
                pointDeltaY: -24.0,
                fixedPtDeltaY: -2.4,
                scrollPhase: 1 // kCGScrollPhaseBegan
            )

            let result = pipeline.processEvent(event)
            check(!result.consumed, "Trackpad began event must not be consumed by wheel smoother")
            guard let outEvent = result.outputEvent else {
                fatalError("Output event missing for passthrough")
            }
            // Deliberate invariant: Trackpad deltas must remain unmodified (no reversal applied)
            assertEqual(outEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
            assertNear(outEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), -24.0)
            assertNear(outEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -2.4)
        }

        runner.register(tier: 2, id: "TC-PIPE-02", name: "Trackpad Scroll Phase Changed & Ended Isolation") {
            let pipeline = SpecificationEventPipeline()
            for phase in [Int64(2), Int64(4)] { // Changed, Ended
                let event = CGEventTestFactory.makeScrollWheelEvent(
                    deltaY: -3,
                    pointDeltaY: -30.0,
                    scrollPhase: phase
                )
                let result = pipeline.processEvent(event)
                check(!result.consumed, "Phase \(phase) must not be consumed")
                guard let out = result.outputEvent else { fatalError("Out event missing") }
                assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
                assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), -30.0)
            }
        }

        runner.register(tier: 2, id: "TC-PIPE-03", name: "Trackpad Momentum Phase Isolation") {
            let pipeline = SpecificationEventPipeline()
            for mPhase in [Int64(1), Int64(2), Int64(3)] { // Begin, Continue, End
                let event = CGEventTestFactory.makeScrollWheelEvent(
                    deltaY: 5,
                    pointDeltaY: 50.0,
                    momentumPhase: mPhase
                )
                let result = pipeline.processEvent(event)
                check(!result.consumed, "Momentum phase \(mPhase) must pass through untouched")
                guard let out = result.outputEvent else { fatalError("Out event missing") }
                assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), 5)
            }
        }

        runner.register(tier: 2, id: "TC-PIPE-04", name: "Trackpad Scroll Count Acceleration Isolation") {
            let pipeline = SpecificationEventPipeline()
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -1,
                pointDeltaY: -15.0,
                scrollCount: 3 // Trackpad accelerated tick count
            )
            let result = pipeline.processEvent(event)
            check(!result.consumed, "Accelerated scroll count must pass through")
            guard let out = result.outputEvent else { fatalError("Out event missing") }
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1)
        }

        runner.register(tier: 2, id: "TC-PIPE-05", name: "Remote Desktop Continuous Gesture Passthrough") {
            let pipeline = SpecificationEventPipeline()
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -4,
                pointDeltaY: -40.0,
                isContinuous: 1, // Pre-smoothed continuous stream from VNC/remote desktop
                scrollPhase: 0,
                momentumPhase: 0
            )
            let result = pipeline.processEvent(event)
            check(!result.consumed, "Continuous remote gesture must pass through without double smoothing")
            guard let out = result.outputEvent else { fatalError("Out event missing") }
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), -40.0)
        }

        runner.register(tier: 2, id: "TC-PIPE-06", name: "Non-Smooth Vertical Reversal Across All 3 Axes") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = false
            pipeline.reverse = true

            // Raw input: wheel down (-1, -10.0, -1.0)
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -1,
                pointDeltaY: -10.0,
                fixedPtDeltaY: -1.0
            )

            let result = pipeline.processEvent(event)
            check(!result.consumed, "Non-smooth mode must emit transformed event immediately")
            guard let out = result.outputEvent else { fatalError("Output event missing") }

            // Reversal must invert all 3 vertical axis representations synchronously
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1, "DeltaAxis1 must be inverted to +1")
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 10.0, "PointDeltaAxis1 must be inverted to +10.0")
            assertNear(out.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 1.0, "FixedPtDeltaAxis1 must be inverted to +1.0")
        }

        runner.register(tier: 2, id: "TC-PIPE-07", name: "Non-Smooth Horizontal Reversal Across All 3 Axes") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = false
            pipeline.reverse = true

            // Raw input: wheel right (-2, -16.0, -1.6)
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaX: -2,
                pointDeltaX: -16.0,
                fixedPtDeltaX: -1.6
            )

            let result = pipeline.processEvent(event)
            check(!result.consumed)
            guard let out = result.outputEvent else { fatalError("Output event missing") }

            // Reversal must invert all 3 horizontal axis representations synchronously
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis2), 2, "DeltaAxis2 must be inverted to +2")
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis2), 16.0, "PointDeltaAxis2 must be inverted to +16.0")
            assertNear(out.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 1.6, "FixedPtDeltaAxis2 must be inverted to +1.6")
        }

        runner.register(tier: 2, id: "TC-PIPE-08", name: "Reversal Invariant (Double Reversal)") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = false
            pipeline.reverse = true

            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -5,
                pointDeltaY: -50.0,
                fixedPtDeltaY: -5.0
            )

            _ = pipeline.processEvent(event) // First reverse -> +5, +50.0, +5.0
            _ = pipeline.processEvent(event) // Second reverse -> back to -5, -50.0, -5.0

            assertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -5, "Double reverse must restore original delta")
            assertNear(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), -50.0)
            assertNear(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -5.0)
        }

        runner.register(tier: 2, id: "TC-PIPE-09", name: "Option Key (Dash) 5.0x Amplification") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = true
            pipeline.reverse = false
            pipeline.step = 33.6
            pipeline.speed = 1.0

            // Normal notch
            let eventNormal = CGEventTestFactory.makeScrollWheelEvent(pointDeltaY: 33.6)
            _ = pipeline.processEvent(eventNormal)
            let normalBuffer = pipeline.stepper.buffer.y
            assertNear(normalBuffer, 33.6)

            pipeline.reset()

            // Notch with Option key held (.maskAlternate)
            let eventDash = CGEventTestFactory.makeScrollWheelEvent(
                pointDeltaY: 33.6,
                flags: [.maskAlternate]
            )
            _ = pipeline.processEvent(eventDash)
            let dashBuffer = pipeline.stepper.buffer.y
            assertNear(dashBuffer, 33.6 * 5.0, "Option key must amplify scroll buffer by 5.0x")
        }

        runner.register(tier: 2, id: "TC-PIPE-10", name: "Shift Key (Toggle) Axis Swap") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = false
            pipeline.reverse = false

            // Vertical wheel notch with Shift held (.maskShift)
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: 1,
                pointDeltaY: 34.0,
                fixedPtDeltaY: 3.36,
                flags: [.maskShift]
            )

            let result = pipeline.processEvent(event)
            guard let out = result.outputEvent else { fatalError("Out event missing") }

            // Vertical axis must be zeroed; horizontal axis receives the vertical distance
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0, "Vertical deltaAxis must be 0 after Shift swap")
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 0.0, "Vertical pointDelta must be 0 after Shift swap")

            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis2), 1, "Horizontal deltaAxis must receive vertical delta")
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis2), 34.0, "Horizontal pointDelta must receive vertical point delta")
            assertNear(out.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 3.36)
        }

        runner.register(tier: 2, id: "TC-PIPE-11", name: "Shift Key Dual-Axis Preservation") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = false
            pipeline.reverse = false

            // Event with BOTH vertical and horizontal movement (e.g. MX Master thumb wheel active)
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: 1,
                pointDeltaY: 10.0,
                deltaX: 2,
                pointDeltaX: 20.0,
                flags: [.maskShift]
            )

            let result = pipeline.processEvent(event)
            guard let out = result.outputEvent else { fatalError("Out event missing") }

            // If horizontal is already active natively, Shift does NOT cross-swap
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 10.0)
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis2), 2)
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis2), 20.0)
        }

        runner.register(tier: 2, id: "TC-PIPE-12", name: "Command Key (Block) Smooth Bypass") {
            let pipeline = SpecificationEventPipeline()
            pipeline.smooth = true
            pipeline.reverse = true

            // Wheel event with Command held (.maskCommand, e.g. for Zoom in Safari/Figma)
            let event = CGEventTestFactory.makeScrollWheelEvent(
                deltaY: -1,
                pointDeltaY: -10.0,
                flags: [.maskCommand]
            )

            let result = pipeline.processEvent(event)
            check(!result.consumed, "Command key must block smooth buffer accumulation")
            guard let out = result.outputEvent else { fatalError("Out event missing") }

            // Reversal must still be active even when smoothing is blocked
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1, "Reversal must remain active during Command block")
            assertNear(out.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 10.0)
            check(!pipeline.stepper.hasActiveMomentum, "Smooth buffer must remain empty during Command block")
        }
    }
}
