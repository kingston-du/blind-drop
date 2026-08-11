import Testing
@testable import BlindDrop

/// The Unit target's proof of life. The real cast — PaletteContrastTests, ServerClockTests,
/// ScoringFormatTests, ShareHeadlineTests, MotionTokenTests, A11yLabelTests — arrives with
/// E08 and after (docs/13 §1).
@Suite struct AppSkeleton {
    @Test func theAppTargetLinks() {
        #expect(RootView() is RootView)
    }
}
