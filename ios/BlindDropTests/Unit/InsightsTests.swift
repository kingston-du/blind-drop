import Foundation
import Testing
@testable import BlindDrop

@MainActor
@Suite struct InsightsTests {

    @Test func theInsightsContractDecodesAndUsesTheNamedCircleRoute() throws {
        let insights = try JSONDecoder.api.decode(InsightsDTO.self, from: RoundFixture.payload("insights"))
        #expect(insights.youKnowBest?.member.displayName == "Cal")
        #expect(insights.youKnowBest?.rate == 10.0 / 14.0)
        #expect(insights.mutualRecognition.first?.members.map(\.displayName) == ["Ana", "Hal"])
        #expect(insights.mutualMisses.first?.correct == 0)
        #expect(insights.confusion.hasEnoughHistory)
        #expect(insights.confusion.pairs.first?.actualMember.displayName == "Dee")

        let endpoint = Endpoint<InsightsDTO>.insights(in: "g_cove")
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/groups/g_cove/insights")
        #expect(endpoint.retry.backoff == [.milliseconds(200), .milliseconds(600)])
    }

    @Test func theStoreResolvesTheActiveCircleBeforeLoadingInsights() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        session.armExact("/groups/\(groupID)/insights", try RoundFixture.envelope("insights"))
        let store = InsightsStore(api: env.api, circles: env.circles)

        await store.load()

        #expect(store.state.value?.hardestToRead?.member.displayName == "Gus")
        #expect(session.count(matching: "/groups/\(groupID)/insights") == 1)
    }
}
