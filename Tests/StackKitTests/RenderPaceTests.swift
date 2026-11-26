import Testing
@testable import StackKit

@Suite("Render pace")
struct RenderPaceTests {

    @Test("Thirty frames a second redraw twice a second")
    func pacesThePreview() {
        var pace = RenderPace(gap: RenderPace.preview)
        let admitted = (0..<300).filter { pace.admit(Double($0) / 30) }.count
        #expect(admitted == 20)
    }

    @Test("The first frame is drawn at once, and so is the first of a new session")
    func firstFrameAndNewClock() {
        var pace = RenderPace(gap: 2)
        let first = pace.admit(100)
        let tooSoon = pace.admit(101)
        let newSession = pace.admit(5)
        #expect(first)
        #expect(!tooSoon)
        #expect(newSession)
    }
}
