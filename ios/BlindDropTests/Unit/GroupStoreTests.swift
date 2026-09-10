import Foundation
import Testing
@testable import BlindDrop

/// `E24-01`. The circle's roster, ranked by all-time Ear.
@MainActor
@Suite struct GroupStoreTests {

    /// Both routes, and neither failure takes the other down — the same split `ResultsStore`
    /// makes between the answers and the standings (`StandingsTests`).
    @Test func theStoreLoadsBothRoutes() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        session.armExact("/groups/\(groupID)", try RoundFixture.envelope("group_current"))
        session.armExact("/groups/\(groupID)/standings", try RoundFixture.envelope("standings"))
        let store = GroupStore(api: env.api, circles: env.circles)

        await store.load()

        #expect(store.members.count == 9)
        #expect(store.bestEar.count == 7)
        #expect(store.readabilityByUserID.count == 8)
    }

    /// A standings route that fails leaves the roster on screen — a section that did not load
    /// is a section that is not drawn, not a screen that is not.
    @Test func aFailedStandingsDoesNotTakeTheRosterDown() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        session.armExact("/groups/\(groupID)", try RoundFixture.envelope("group_current"))
        session.armExact("/groups/\(groupID)/standings", RoundFixture.failure(500, "INTERNAL"))
        let store = GroupStore(api: env.api, circles: env.circles)

        await store.load()

        #expect(store.members.count == 9)
        #expect(store.standings.value == nil)
        #expect(store.bestEar.isEmpty)
    }

    // MARK: - Thin history

    /// Below `GroupStore.thinHistoryThreshold` rounds, the leaderboard does not print a ranked
    /// percentage (`tasks/E24-leaderboard-profiles.md`: *"do not print a confident percentage
    /// over four data points"*).
    @Test func aCircleBelowTheThresholdIsThin() throws {
        let thin = try StandingsDTO.fixture(roundsPlayed: 3)
        #expect(GroupStore.thinHistoryThreshold == 5)
        #expect(thin.roundsPlayed < GroupStore.thinHistoryThreshold)
    }

    @Test func aCircleAtTheThresholdIsNotThin() throws {
        let notThin = try StandingsDTO.fixture(roundsPlayed: 5)
        #expect(notThin.roundsPlayed >= GroupStore.thinHistoryThreshold)
    }

    /// `E28-06`, amendment A1: the test stage shows every stat, however little history is behind
    /// it, so the leaderboard's thin-history swap is switched off — `isThinHistory` is `false`
    /// whatever `roundsPlayed` says, both before and after a load. `thinHistoryThreshold` itself
    /// stays defined (the two tests above still pin it) so the gate is a one-line revert rather
    /// than a number to relearn.
    @Test func theStoreNeverReportsThinHistoryWhileTheGateIsOff() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        session.armExact("/groups/\(groupID)", try RoundFixture.envelope("group_current"))
        session.armExact(
            "/groups/\(groupID)/standings",
            RoundFixture.envelope(StandingsDTO.payload(roundsPlayed: 2))
        )
        let store = GroupStore(api: env.api, circles: env.circles)

        #expect(store.isThinHistory == false)

        await store.load()

        #expect(store.isThinHistory == false)
        #expect(store.standings.value?.roundsPlayed == 2)
    }
}

/// A tiny standings payload, built rather than borrowed from `ios/Fixtures/payloads/standings.json`
/// — the fixture's own 14 rounds is deliberately past the thin-history threshold, so a test of
/// the threshold itself needs a value on the other side of it.
extension StandingsDTO {
    static func payload(roundsPlayed: Int) -> Data {
        // A circle this young has not reached the fourteen-round window, so `window_rounds` is
        // its whole life rather than the constant — the case the standings header has to print
        // honestly instead of claiming a fortnight.
        Data("""
        {"rounds_played":\(roundsPlayed),"window_rounds":\(min(14, roundsPlayed)),
         "best_ear":[
           {"rank":1,"user_id":"u_ana","display_name":"Ana","ear_reads":1,"ear_all_time":0.5,"ear_correct_total":1}],
         "readability":[]}
        """.utf8)
    }

    static func fixture(roundsPlayed: Int) throws -> StandingsDTO {
        try JSONDecoder.api.decode(StandingsDTO.self, from: payload(roundsPlayed: roundsPlayed))
    }
}
