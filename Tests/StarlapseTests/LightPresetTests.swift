import Testing
@testable import Starlapse

/// Auto follows what the stack is, and the presets mean what their labels say.
@Suite("Light presets")
struct LightPresetTests {

    @Test("Auto: five minutes of pinpoint stars, half an hour of trails, two of landscape")
    func autoFollowsTheMode() {
        #expect(LightPreset.auto.seconds(for: .stars) == 300)
        #expect(LightPreset.auto.seconds(for: .trails) == 1800)
        #expect(LightPreset.auto.seconds(for: .smooth) == 120)
    }

    @Test("A fixed preset ignores the mode")
    func fixedIgnoresMode() {
        for mode in StackMode.allCases {
            #expect(LightPreset.fifteenMinutes.seconds(for: mode) == 900)
            #expect(LightPreset.oneHour.seconds(for: mode) == 3600)
        }
    }

    @Test("Every preset stays inside what the slider allows")
    func withinSliderRange() {
        for preset in LightPreset.allCases {
            for mode in StackMode.allCases {
                let seconds = preset.seconds(for: mode)
                #expect(seconds >= CaptureSettings.minimumTotalLight)
                #expect(seconds <= CaptureSettings.maximumTotalLight)
            }
        }
    }

    @Test("Said the way a person says it")
    func spoken() {
        #expect(LightPreset.spoken(3600) == "1 h")
        #expect(LightPreset.spoken(1800) == "30 min")
        #expect(LightPreset.spoken(45) == "45 s")
    }
}
