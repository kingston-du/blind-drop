import Foundation
import XCTest

/// E14-04 / AC-10. The server waits are controlled and excluded; taps, typing, search debounce,
/// and the seal animation are measured. Every failure prints the per-step ledger so the slow
/// interaction names itself instead of leaving one opaque 90-second number.
@MainActor
final class FullLoopUITests: XCTestCase {
    private let fixture = URL(string: "http://127.0.0.1:8787")!

    func testFullLoopUnder90Seconds() async throws {
        try await runLoop(reducedMotion: false)
    }

    func testReducedMotionFullLoop() async throws {
        try await runLoop(reducedMotion: true)
    }

    /// AC-2's UI half: a foreign process timezone must not move the phase or group-local day.
    /// The ±5-year clock arithmetic itself is injected deterministically in ServerClockTests;
    /// this launch proves the rendered phase still follows the server under the hostile zone.
    func testForeignTimezoneStillFollowsTheServer() async throws {
        try await requireControllableFixture()
        try await setPhase("open_nosub")

        let app = makeApp(reducedMotion: false)
        app.launchEnvironment["TZ"] = "Pacific/Kiritimati"
        app.launch()

        XCTAssertTrue(app.textFields["Search for a song"].waitForExistence(timeout: 5),
                      "the server's open phase must win over the hostile device context")
        XCTAssertEqual(app.staticTexts["round.dateHeadline"].label, "Monday, August 10",
                      "the date is the group's local_date, not the device timezone's day")
    }

    func testSealedAndRecordControlsHaveLabels() async throws {
        try await requireControllableFixture()
        try await setPhase("open")

        let sealed = makeApp(reducedMotion: false)
        sealed.launch()
        require(sealed.buttons["Replace song"], within: 5, message: "sealed screen never appeared")
        assertVisibleControlsHaveLabels(sealed, screen: "sealed")
        sealed.terminate()

        let record = makeApp(reducedMotion: false)
        record.launchArguments.append("-uiTestRecord")
        record.launch()
        XCTAssertTrue(record.staticTexts["The Record"].waitForExistence(timeout: 5),
                      "record screen never appeared")
        assertVisibleControlsHaveLabels(record, screen: "record")
    }

    private func runLoop(reducedMotion: Bool) async throws {
        try await requireControllableFixture()
        try await setPhase("open_nosub")

        let app = makeApp(reducedMotion: reducedMotion)
        app.launchEnvironment["TZ"] = "Pacific/Kiritimati"
        app.launch()

        var budget = InteractionBudget()
        let search = app.textFields["Search for a song"]
        require(search, within: 5, message: "submit screen never appeared")
        assertVisibleControlsHaveLabels(app, screen: "open")
        budget.type("first search key", "r", into: search)

        let result = app.buttons["Ribs by Lorde"]
        let searchStarted = ContinuousClock.now
        budget.type("second search key", "i", into: search)
        XCTAssertTrue(result.waitForExistence(timeout: 2), "first search result never appeared")
        let searchLatency = ContinuousClock.now - searchStarted
        let searchDelay = try XCTUnwrap(
            Int(result.value as? String ?? ""),
            "the debug app did not expose its search-delay token"
        )
        XCTAssertLessThan(searchDelay, 400, "the client search delay exceeded 400ms")
        budget.tap("choose search result", result)

        let seal = app.buttons["Seal it"]
        require(seal, within: 3, message: "confirm screen never appeared")
        assertVisibleControlsHaveLabels(app, screen: "confirm")
        budget.recordTap()
        budget.measure("seal animation") {
            seal.tap()
            XCTAssertTrue(app.buttons["Replace song"].waitForExistence(timeout: 5),
                          "seal never landed")
        }

        // Scripted server time advances outside the interaction ledger.
        try await setPhase("revealed")
        refresh(app)

        let firstCard = app.descendants(matching: .any)["flightCard.1"]
        require(firstCard, within: 5, message: "reveal never appeared")
        assertVisibleControlsHaveLabels(app, screen: "reveal")
        budget.tap("focus first card", firstCard)

        let members = [
            "a0000000-0000-4000-8000-000000000004", // Dee
            "a0000000-0000-4000-8000-000000000002", // Ben
            "a0000000-0000-4000-8000-000000000008", // Hal
            "a0000000-0000-4000-8000-000000000007", // Gus
            "a0000000-0000-4000-8000-000000000003", // Cal
            "a0000000-0000-4000-8000-000000000005", // Eli
            "a0000000-0000-4000-8000-000000000006", // Fay
        ]
        for (offset, member) in members.enumerated() {
            let chip = app.descendants(matching: .any)["nameChip.\(member)"]
            require(chip, within: 3, message: "name chip \(member) is unreachable")
            budget.tap("assign guess \(offset + 1)", chip)
        }

        let lock = app.buttons["Lock in guesses"]
        require(lock, within: 3, message: "guess action is unreachable")
        budget.tap("lock guesses", lock)

        try await setPhase("scored")
        refresh(app)
        XCTAssertTrue(app.staticTexts["Answers"].waitForExistence(timeout: 5),
                      "results never appeared")
        assertVisibleControlsHaveLabels(app, screen: "results")

        let breakdown = budget.breakdown(searchLatency: searchLatency)
        print("E14 full-loop ledger: \(breakdown)")
        XCTAssertLessThanOrEqual(budget.tapCount, 18, breakdown)
        XCTAssertLessThan(budget.total, .seconds(90), breakdown)
    }

    private func makeApp(reducedMotion: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-apiBaseURL", fixture.absoluteString,
            "-fixtureSession",
        ]
        if reducedMotion { app.launchArguments.append("-uiTestReduceMotion") }
        return app
    }

    private func refresh(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        app.activate()
    }

    private func require(
        _ element: XCUIElement,
        within timeout: TimeInterval,
        message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message(), file: file, line: line)
    }

    /// Absent on a developer's machine, the fixture is a missing convenience and these tests
    /// skip. In CI it is always started before the suite, so absence means something is broken
    /// — and a skip there would report AC-10 as passing while proving nothing. Fail instead.
    ///
    /// Read as `CI`, but the workflow must export it as `TEST_RUNNER_CI`. UI test code runs
    /// inside the runner app on the simulator — a different process from the one `xcodebuild`
    /// was launched in — and only `TEST_RUNNER_`-prefixed variables are forwarded into it, with
    /// the prefix stripped on the way. So a workflow that exports a bare `CI` leaves this nil,
    /// the suite skips, and the run still reports success: the exact failure this guard exists
    /// to prevent. See the UI test step in `.github/workflows/ci.yml`.
    private static let isCI = ProcessInfo.processInfo.environment["CI"] != nil

    private func unavailableFixture(_ reason: String) -> Error {
        if Self.isCI {
            return FixtureUnavailable(reason: reason)
        }
        return XCTSkip(reason)
    }

    private struct FixtureUnavailable: Error, CustomStringConvertible {
        let reason: String
        var description: String {
            "AC-10 cannot be proved without the fixture server: \(reason)"
        }
    }

    private func requireControllableFixture() async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(
                from: fixture.appending(path: "__fixture")
            )
        } catch {
            throw unavailableFixture("fixture server is not running on \(fixture.absoluteString)")
        }
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try XCTUnwrap(json["data"] as? [String: Any])
        if http.statusCode != 200 || body["control"] as? Bool != true {
            throw unavailableFixture("start ios/Fixtures/server.ts with FIXTURE_CONTROL=1")
        }
    }

    /// A compact VoiceOver walk at each phase boundary. XCTest only exposes accessibility-tree
    /// elements here, so a visible control with an empty label is exactly the class of regression
    /// this check is intended to catch.
    private func assertVisibleControlsHaveLabels(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controlTypes: [XCUIElement.ElementType] = [
            .button, .link, .textField, .secureTextField, .switch, .slider, .stepper,
        ]
        let controls = controlTypes.flatMap {
            app.descendants(matching: $0).allElementsBoundByIndex
        }.filter(\.isHittable)
        XCTAssertFalse(controls.isEmpty, "\(screen) exposed no accessible controls", file: file, line: line)
        for control in controls {
            guard control.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            // SwiftUI `Menu` bridges through UIKit as two coincident accessibility nodes: the
            // labelled SwiftUI control and an unlabeled platform button. It is not a second
            // reachable action. Only forgive an empty node when its exact frame has a labelled
            // peer; the two real missing search-field labels caught during E14 had no such peer.
            let hasLabelledPeer = controls.contains {
                $0.frame.equalTo(control.frame)
                    && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            XCTAssertTrue(
                hasLabelledPeer,
                "\(screen) has an unlabeled \(control.elementType.rawValue): \(control.debugDescription)",
                file: file,
                line: line
            )
        }
    }

    private func setPhase(_ phase: String) async throws {
        var request = URLRequest(url: fixture.appending(path: "__fixture/phase"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["phase": phase])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200,
                       "fixture refused phase \(phase)")
    }
}

@MainActor
private struct InteractionBudget {
    private(set) var tapCount = 0
    private(set) var steps: [(String, Duration)] = []

    var total: Duration { steps.reduce(.zero) { $0 + $1.1 } }

    mutating func recordTap() { tapCount += 1 }

    mutating func tap(_ name: String, _ element: XCUIElement) {
        recordTap()
        measure(name) { element.tap() }
    }

    mutating func type(_ name: String, _ text: String, into element: XCUIElement) {
        measure(name) { element.typeText(text) }
    }

    mutating func measure(_ name: String, _ action: () -> Void) {
        let started = ContinuousClock.now
        action()
        steps.append((name, ContinuousClock.now - started))
    }

    func breakdown(searchLatency: Duration) -> String {
        let rows = steps.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
        return "taps=\(tapCount), interaction=\(total), search=\(searchLatency); \(rows)"
    }
}
