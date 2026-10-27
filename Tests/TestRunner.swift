import Foundation

public struct TestCase {
    public let tier: Int
    public let id: String
    public let name: String
    public let body: () throws -> Void

    public init(tier: Int, id: String, name: String, body: @escaping () throws -> Void) {
        self.tier = tier
        self.id = id
        self.name = name
        self.body = body
    }
}

public final class TestRegistry {
    public static let shared = TestRegistry()
    public private(set) var tests: [TestCase] = []

    public init() {}

    public func register(tier: Int, id: String, name: String, body: @escaping () throws -> Void) {
        tests.append(TestCase(tier: tier, id: id, name: name, body: body))
    }
}

public struct TestRunner {
    public static func runAll(arguments: [String] = CommandLine.arguments) -> Int32 {
        let registry = TestRegistry.shared

        // Register all test tiers
        Tier1_UnitMathTests.registerTests(to: registry)
        Tier2_EventPipelineTests.registerTests(to: registry)
        Tier3_SteppedClockTests.registerTests(to: registry)
        Tier4_IntegrationTests.registerTests(to: registry)

        // Parse command line arguments
        var tierFilter: Int? = nil
        var nameFilter: String? = nil

        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--tier", i + 1 < arguments.count {
                tierFilter = Int(arguments[i + 1])
                i += 2
            } else if arg == "--filter", i + 1 < arguments.count {
                nameFilter = arguments[i + 1]
                i += 2
            } else if arg == "-h" || arg == "--help" {
                print("Usage: rapooflow-tests [--tier 1|2|3|4] [--filter <pattern>]")
                return 0
            } else {
                i += 1
            }
        }

        var testsToRun = registry.tests
        if let tf = tierFilter {
            testsToRun = testsToRun.filter { $0.tier == tf }
        }
        if let nf = nameFilter {
            testsToRun = testsToRun.filter { $0.id.contains(nf) || $0.name.contains(nf) }
        }

        print("=================================================================")
        print("          RapooFlow Multi-Tier Automated Test Suite              ")
        print("=================================================================")
        print("Discovered \(registry.tests.count) total test cases across Tiers 1-4.")
        if tierFilter != nil || nameFilter != nil {
            print("Filter active: running \(testsToRun.count) matching tests.")
        }
        print("-----------------------------------------------------------------")

        var passedCount = 0
        var failedCount = 0
        var currentTier = -1
        let startTime = CFAbsoluteTimeGetCurrent()

        for test in testsToRun {
            if test.tier != currentTier {
                currentTier = test.tier
                let tierName: String
                switch currentTier {
                case 1: tierName = "Tier 1: Unit Math & Filters"
                case 2: tierName = "Tier 2: In-Memory Headless CGEvent Pipeline"
                case 3: tierName = "Tier 3: Deterministic Frame Stepping Simulation"
                case 4: tierName = "Tier 4: Integration, Hardware Remapping & Packaging"
                default: tierName = "Tier \(currentTier)"
                }
                print("\n[\(tierName)]")
            }

            let testStart = CFAbsoluteTimeGetCurrent()
            let idPad = test.id.padding(toLength: 12, withPad: " ", startingAt: 0)
            let namePad = test.name.padding(toLength: 52, withPad: " ", startingAt: 0)
            do {
                try test.body()
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - testStart) * 1000.0
                let msStr = String(format: "%5.2f ms", elapsedMs)
                print("  ✓ \(idPad) \(namePad) (\(msStr))")
                passedCount += 1
            } catch {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - testStart) * 1000.0
                let msStr = String(format: "%5.2f ms", elapsedMs)
                print("  ✗ \(idPad) \(namePad) (\(msStr))")
                print("    Error: \(error)")
                failedCount += 1
            }
        }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("\n-----------------------------------------------------------------")
        print("Test Summary:")
        print("  Total Executed : \(testsToRun.count)")
        print("  Passed         : \(passedCount)")
        print("  Failed         : \(failedCount)")
        print(String(format: "  Execution Time : %.3f s", totalElapsed))
        print("=================================================================")

        if failedCount == 0 {
            print("RESULT: ALL \(passedCount) TESTS PASSED SUCCESSFULLY! ✓\n")
            return 0
        } else {
            print("RESULT: \(failedCount) TEST(S) FAILED! ✗\n")
            return 1
        }
    }
}
