import Foundation
import Testing
@testable import Starlapse

/// The crash-loop guard: a format that was in hand when the process died is never
/// offered again, and one that survived leaves no trace.
@Suite("Quarantining formats that crash")
struct FormatQuarantineTests {

    static func fresh() throws -> FormatQuarantine {
        let suite = "quarantine-\(UUID().uuidString)"
        return FormatQuarantine(defaults: try #require(UserDefaults(suiteName: suite)))
    }

    @Test("A format the process survived is not blocked")
    func survivedLeavesNoTrace() throws {
        let quarantine = try Self.fresh()
        quarantine.begin("4032x3024-420f-30fps", in: "wide")
        quarantine.survived()

        #expect(quarantine.recoverFromCrash() == nil)
        #expect(quarantine.blocked(in: "wide").isEmpty)
    }

    @Test("A note that outlives the process blocks its format on the next launch")
    func deathBlocksTheFormat() throws {
        let quarantine = try Self.fresh()
        quarantine.begin("4032x3024-x420-30fps", in: "wide")
        // The process dies here: nothing calls survived().

        #expect(quarantine.recoverFromCrash() == "wide|4032x3024-x420-30fps")
        #expect(quarantine.blocked(in: "wide") == ["4032x3024-x420-30fps"])
        #expect(quarantine.recoverFromCrash() == nil)
    }

    @Test("A block on one lens says nothing about another")
    func blocksAreScopedToTheCamera() throws {
        let quarantine = try Self.fresh()
        quarantine.begin("4032x3024-420f-30fps", in: "wide")
        quarantine.recoverFromCrash()

        #expect(quarantine.blocked(in: "ultraWide").isEmpty)
    }

    @Test("A caught refusal at start condemns the format without a crash")
    func condemnedWithoutDying() throws {
        let quarantine = try Self.fresh()
        quarantine.begin("8064x6048-420f-15fps", in: "wide")
        quarantine.condemnPending()

        #expect(quarantine.blocked(in: "wide") == ["8064x6048-420f-15fps"])
        #expect(quarantine.recoverFromCrash() == nil)
    }
}
