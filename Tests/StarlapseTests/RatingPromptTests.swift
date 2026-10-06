import Testing
@testable import Starlapse

/// When the rating prompt is earned. The first save is a test shot; the second is a
/// person who came back.
@Suite("Asking for a rating")
struct RatingPromptTests {

    @Test("Never on the first save, once on the second")
    func secondSaveAsks() async {
        await #expect(!RatingPrompt.shouldAsk(saves: 1, askedVersion: nil, currentVersion: "1.0.3"))
        await #expect(RatingPrompt.shouldAsk(saves: 2, askedVersion: nil, currentVersion: "1.0.3"))
        await #expect(!RatingPrompt.shouldAsk(saves: 3, askedVersion: nil, currentVersion: "1.0.3"))
    }

    @Test("Once asked, not again until a new version, and then only every fifth save")
    func onceAskedWaitsForNewVersion() async {
        await #expect(!RatingPrompt.shouldAsk(saves: 10, askedVersion: "1.0.3", currentVersion: "1.0.3"))
        await #expect(!RatingPrompt.shouldAsk(saves: 11, askedVersion: "1.0.3", currentVersion: "1.0.4"))
        await #expect(RatingPrompt.shouldAsk(saves: 15, askedVersion: "1.0.3", currentVersion: "1.0.4"))
    }
}
