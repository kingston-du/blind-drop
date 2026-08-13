import Foundation
import Testing
@testable import BlindDrop

/// `E12-03`. The two lists, and the asymmetry between them that is a **product rule** rather
/// than a layout preference (`docs/02` §4.5).
///
/// > **Readability has no rank position and no arrow.**
///
/// The client half of that rule is enforced by shape: `ReadabilityStandingDTO` has nowhere to
/// put a rank, and `ReadabilityRow` has nothing to draw one from. These tests are what keep
/// both true — `docs/04` §4 says *"do not add a rank to this array — a client that receives one
/// will render it"*, and this is the test that would fail the day one appears.
@MainActor
@Suite struct StandingsTests {

    // MARK: - The readability list has no rank

    /// **The spec violation, as a test rather than a comment** (`E12-03`).
    ///
    /// Asserted on the type, because that is where it is actually prevented: no property of a
    /// readability row is a position, so no view can print one. A `rank` key arriving on the
    /// wire is ignored by the decoder rather than surfacing somewhere it could be rendered.
    @Test func aReadabilityRowHasNowhereToPutARank() throws {
        let withARank = Data("""
        {"user_id":"u_ana","display_name":"Ana","readability_all_time":0.83,
         "band":"open_book","rank":1}
        """.utf8)

        let row = try JSONDecoder.api.decode(ReadabilityStandingDTO.self, from: withARank)

        #expect(row.displayName == "Ana")
        #expect(row.band == .openBook)
        // The whole assertion: a mirror of the row carries four values and none of them is the
        // rank the server was told not to send.
        let labels = Mirror(reflecting: row).children.compactMap(\.label)
        #expect(labels == ["userID", "displayName", "readabilityAllTime", "band"])
        #expect(!labels.contains("rank"))
    }

    /// The list is **sorted, not ranked**. The order the server sent is the order rendered, and
    /// there is no number in front of any of it.
    @Test func theReadabilityListKeepsTheServersOrder() throws {
        let standings = try StandingsFixture.standings()
        #expect(standings.readability.map(\.displayName)
                == ["Ana", "Hal", "Ben", "Dee", "Cal", "Fay", "Eli", "Gus"])
    }

    // MARK: - Best Ear is ranked, and the rank is the server's

    /// **Ties share a rank and the next one skips** (`docs/04` §4).
    ///
    /// The client prints `rank` and never an index. Two people on 0.68 are both second and
    /// nobody is third; enumerating the array would renumber them 2 and 3, which is a different
    /// claim about the same fortnight.
    @Test func aTieSharesARankAndTheNextRankSkips() throws {
        let tied = Data("""
        {"rounds_played":14,
         "best_ear":[
           {"rank":1,"user_id":"u_cal","display_name":"Cal","ear_all_time":0.79,"ear_correct_total":77},
           {"rank":2,"user_id":"u_ana","display_name":"Ana","ear_all_time":0.68,"ear_correct_total":67},
           {"rank":2,"user_id":"u_hal","display_name":"Hal","ear_all_time":0.68,"ear_correct_total":67},
           {"rank":4,"user_id":"u_fay","display_name":"Fay","ear_all_time":0.55,"ear_correct_total":54}],
         "readability":[]}
        """.utf8)

        let standings = try JSONDecoder.api.decode(StandingsDTO.self, from: tied)

        #expect(standings.bestEar.map(\.rank) == [1, 2, 2, 4])
        // And it is emphatically not the index: the third row is No. 2 and the fourth is No. 4.
        #expect(standings.bestEar.enumerated().contains { $0.offset + 1 != $0.element.rank })
    }

    @Test func theBestEarListCarriesTheRawCountBehindTheRate() throws {
        let standings = try StandingsFixture.standings()
        let leader = try #require(standings.bestEar.first)

        #expect(leader.rank == 1)
        #expect(ScoringFormat.percent(leader.earAllTime) == "79%")
        #expect(Copy.format("results.standings.ear.detail", leader.earCorrectTotal) == "77 correct")
    }

    // MARK: - The store

    /// Both routes, and neither failure takes the other down: the answers are one night and the
    /// standings are the whole group.
    @Test func theStoreLoadsBothRoutes() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm(routes: [
            "/results": try RoundFixture.envelope("results"),
            "/standings": try RoundFixture.envelope("standings"),
        ])
        let store = ResultsStore(api: env.api, roundID: "r")

        await store.load()

        #expect(store.cards.count == 8)
        #expect(store.standings.value?.bestEar.count == 7)
        #expect(store.standings.value?.readability.count == 8)
    }

    /// A standings route that fails leaves the answers on screen. A section that did not load is
    /// a section that is not drawn, not a screen that is not.
    @Test func aFailedStandingsDoesNotTakeTheAnswersDown() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm(routes: [
            "/results": try RoundFixture.envelope("results"),
            "/standings": RoundFixture.failure(500, "INTERNAL"),
        ])
        let store = ResultsStore(api: env.api, roundID: "r")

        await store.load()

        #expect(store.cards.count == 8)
        #expect(store.standings.value == nil)
        #expect(store.viewState(resolve: nil).standings == nil)
        #expect(store.viewState(resolve: nil).cards.count == 8)
    }
}

@MainActor
enum StandingsFixture {
    static func standings() throws -> StandingsDTO {
        try JSONDecoder.api.decode(StandingsDTO.self, from: RoundFixture.payload("standings"))
    }
}
