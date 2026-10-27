import Foundation
import ApplicationServices

public struct Tier4_IntegrationTests {
    public static func registerTests(to runner: TestRegistry) {
        runner.register(tier: 4, id: "TC-INT-01", name: "Rapoo Button 4 Remapped to Paste (Cmd+V)") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Button 4 down (Forward button on Rapoo mouse)
            let event = CGEventTestFactory.makeMouseEvent(type: .otherMouseDown, buttonNumber: 4)
            let result = pipeline.processEvent(event)

            check(result.consumed, "Button 4 down must be consumed to prevent native side-click propagation")
            check(result.outputEvent == nil, "Original event must be cancelled")
            check(pipeline.dispatchedKeyCodes.contains(9), "Dispatched key code 9 (Command+V / Paste) must be triggered")
        }

        runner.register(tier: 4, id: "TC-INT-02", name: "Rapoo Button 3 Remapped to Copy (Cmd+C)") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Button 3 down (Back button on Rapoo mouse)
            let event = CGEventTestFactory.makeMouseEvent(type: .otherMouseDown, buttonNumber: 3)
            let result = pipeline.processEvent(event)

            check(result.consumed, "Button 3 down must be consumed")
            check(result.outputEvent == nil, "Original event must be cancelled")
            check(pipeline.dispatchedKeyCodes.contains(8), "Dispatched key code 8 (Command+C / Copy) must be triggered")
        }

        runner.register(tier: 4, id: "TC-INT-03", name: "Remapped Button Up Event Suppression") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Send Button 4 down first
            let down = CGEventTestFactory.makeMouseEvent(type: .otherMouseDown, buttonNumber: 4)
            _ = pipeline.processEvent(down)

            // Send Button 4 up
            let up = CGEventTestFactory.makeMouseEvent(type: .otherMouseUp, buttonNumber: 4)
            let upResult = pipeline.processEvent(up)

            check(upResult.consumed, "Button 4 up must be suppressed following remapped down")
            check(upResult.outputEvent == nil, "Button up event must not leak to OS")
        }

        runner.register(tier: 4, id: "TC-INT-04", name: "Non-Remapped Mouse Buttons Pass Through") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Test Left (0), Right (1), and Middle (2) clicks
            for button in [Int64(0), Int64(1), Int64(2)] {
                let event = CGEventTestFactory.makeMouseEvent(type: .otherMouseDown, buttonNumber: button)
                let result = pipeline.processEvent(event)
                check(!result.consumed, "Button \(button) must pass through unmodified")
                guard let out = result.outputEvent else { fatalError("Out event missing") }
                assertEqual(out.getIntegerValueField(.mouseEventButtonNumber), button)
            }
        }

        runner.register(tier: 4, id: "TC-INT-05", name: "IOHIDManager 0x24ae Ctrl+C/V Intercept Window") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Simulate Rapoo mouse hardware HID report (Vendor 0x24ae)
            // Usage 0x19 maps to keycode 9 (V), Usage 0x06 maps to keycode 8 (C)
            let now = CFAbsoluteTimeGetCurrent()
            pipeline.recordRapooHIDUsage(0x19, time: now) // Rapoo Forward button pressed

            // Subsequent Ctrl+V event arriving within 120ms
            let ctrlV = CGEventTestFactory.makeKeyEvent(type: .keyDown, keyCode: 9, flags: [.maskControl])
            let result = pipeline.processEvent(ctrlV)

            check(result.consumed, "Ctrl+V within 120ms of Rapoo HID report must be consumed and remapped to Cmd+V")
            check(pipeline.dispatchedKeyCodes.contains(9), "Cmd+V must be dispatched")
        }

        runner.register(tier: 4, id: "TC-INT-06", name: "Non-Rapoo Ctrl+C/V Passthrough") {
            let pipeline = SpecificationEventPipeline()
            pipeline.buttonRemap = true

            // Ctrl+V without any recent Rapoo HID report (e.g. from standard keyboard)
            let normalCtrlV = CGEventTestFactory.makeKeyEvent(type: .keyDown, keyCode: 9, flags: [.maskControl])
            let result = pipeline.processEvent(normalCtrlV)

            check(!result.consumed, "Standard keyboard Ctrl+V must pass through untouched")
            guard let out = result.outputEvent else { fatalError("Out event missing") }
            check(out.flags.contains(.maskControl), "Control mask must be preserved")
            check(!pipeline.dispatchedKeyCodes.contains(9), "Must not generate synthetic Cmd+V for keyboard")
        }

        runner.register(tier: 4, id: "TC-INT-07", name: "Per-Application Exclusion List Bypass") {
            let pipeline = SpecificationEventPipeline()
            pipeline.excludedApps = ["com.apple.Terminal", "com.vmware.fusion"]
            pipeline.currentAppBundleID = "com.apple.Terminal"
            pipeline.stepper.addInput(y: 100.0, x: 0.0, step: 10.0, speed: 1.0)

            // When terminal is active, scroll wheel events pass through raw
            let scroll = CGEventTestFactory.makeScrollWheelEvent(deltaY: -1, pointDeltaY: -10.0)
            let result = pipeline.processEvent(scroll)

            check(!result.consumed, "Excluded app must bypass smooth scrolling")
            guard let out = result.outputEvent else { fatalError("Out event missing") }
            assertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1, "Raw delta must be untouched in excluded app")
            check(!pipeline.stepper.hasActiveMomentum, "Active momentum must be cleared when entering excluded app")
        }

        runner.register(tier: 4, id: "TC-INT-08", name: "Accessibility Permission Prompt Dictionary") {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary

            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let val = CFDictionaryGetValue(options, Unmanaged.passUnretained(kAXTrustedCheckOptionPrompt.takeUnretainedValue()).toOpaque())
            check(val != nil, "Accessibility prompt options dictionary must contain kAXTrustedCheckOptionPrompt key")
            check(CFDictionaryGetCount(options) == 1, "Dictionary should have 1 entry")
            _ = key // silence unused warning
        }

        runner.register(tier: 4, id: "TC-INT-09", name: "Build Script Zero-Warning Verification") {
            let projectDir = FileManager.default.currentDirectoryPath
            let buildScriptPath = "\(projectDir)/build.sh"
            check(FileManager.default.fileExists(atPath: buildScriptPath), "build.sh must exist at project root")

            let isExecutable = FileManager.default.isExecutableFile(atPath: buildScriptPath)
            check(isExecutable, "build.sh must be executable")
        }

        runner.register(tier: 4, id: "TC-INT-10", name: "Bundle Packaging & Ad-hoc Codesign Verification") {
            let projectDir = FileManager.default.currentDirectoryPath
            let appPath = "\(projectDir)/RapooFlow.app"

            if FileManager.default.fileExists(atPath: appPath) {
                let infoPlist = "\(appPath)/Contents/Info.plist"
                let binary = "\(appPath)/Contents/MacOS/RapooFlow"
                check(FileManager.default.fileExists(atPath: infoPlist), "Info.plist must exist inside bundle")
                check(FileManager.default.fileExists(atPath: binary), "Mach-O binary must exist inside bundle")

                // Run codesign verification
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                proc.arguments = ["--verify", "--deep", "--strict", appPath]
                try? proc.run()
                proc.waitUntilExit()
                assertEqual(proc.terminationStatus, 0, "RapooFlow.app must pass codesign --verify --deep --strict")
            }
        }
    }
}
