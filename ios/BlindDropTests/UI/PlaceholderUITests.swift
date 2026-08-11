import XCTest

/// FullLoopUITests (AC-10, the 90-second loop) and ReducedMotionUITests (AC-11) land in E14
/// and E11. Both run against the fixture server in `ios/Fixtures`, launched by this scheme
/// and reached through `-apiBaseURL`.
final class PlaceholderUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments += ["-apiBaseURL", "http://127.0.0.1:8787"]
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
