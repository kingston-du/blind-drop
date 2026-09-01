import Foundation
import Testing
@testable import BlindDrop

/// `E38-02` — joining a circle when you already have one.
///
/// The store that the sheet is built on. Its whole job is the thing the app could not do until
/// this slice: take a code from somebody who is already `.ready` and answer with the id of the
/// circle to switch to, or with words for why not.
final class JoinCircleStub: RecordingStub, @unchecked Sendable {
    private static let shared = Channel()
    override class var channel: Channel { shared }

    static func arm(_ replies: [Reply]) { shared.arm(replies) }
    static var taken: [Taken] { shared.taken }
}

@MainActor
@Suite(.serialized) struct JoinCircleStoreTests {

    private static let group = #"""
    {"id":"b0000000-0000-4000-8000-000000000002","name":"After Hours","timezone":"America/New_York",
     "reveal_hour":20,"invite_code":"K7MQ2X","is_admin":false,"members":[]}
    """#

    private static let circles = #"""
    {"circles":[{"id":"b0000000-0000-4000-8000-000000000002","name":"After Hours",
                 "my_state":"drop","needs_action":true}]}
    """#

    private static func envelope(_ payload: String) -> Data {
        Data(#"{"server_now":"2026-08-10T18:42:07Z","data":\#(payload)}"#.utf8)
    }

    private static func ok(_ payload: String) -> JoinCircleStub.Reply {
        .init(status: 200, body: envelope(payload))
    }

    private static func failure(_ status: Int, _ code: String) -> JoinCircleStub.Reply {
        .init(
            status: status,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"}}"#.utf8)
        )
    }

    private static func harness() -> (JoinCircleStore, CircleStore, APIClient) {
        let session = SessionStore(auth: FakeAuth(), secrets: MemorySecrets())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JoinCircleStub.self]
        let api = APIClient(
            baseURL: URL(string: "https://fixture.test/functions/v1")!,
            clock: ServerClock(),
            session: session,
            transport: APIClient.makeTransport(configuration)
        )
        session.attach(api)
        let circles = CircleStore(api: api, flags: LocalFlags(defaults: RoundFixture.scratchDefaults()))
        return (JoinCircleStore(api: api, circles: circles), circles, api)
    }

    // MARK: - The field

    /// The same normalisation `OnboardingStore` does, for the same reason: the field is not
    /// where a wrong code is discovered, only where a *shaped* one is assembled (`docs/14` §7).
    @Test func theFieldHoldsOnlyWhatACodeCouldBe() {
        let (store, _, api) = Self.harness()
        _ = api

        store.setCode("k7mq2x")
        #expect(store.code == "K7MQ2X")

        // The commonest way an invite arrives is the whole link, pasted.
        store.setCode("https://blinddrop-site.vercel.app/j/K7MQ2X")
        #expect(store.code == "K7MQ2X")

        // Over-length, plus `o` — one of the five characters `docs/03` §2 excludes.
        store.setCode("aaa222o")
        #expect(store.code == "AAA222")
    }

    @Test func joiningIsGatedOnSixCharacters() {
        let (store, _, api) = Self.harness()
        _ = api
        store.setCode("K7MQ2")
        #expect(!store.canJoin)
        store.setCode("K7MQ2X")
        #expect(store.canJoin)
    }

    // MARK: - Joining

    /// Success answers with the id to switch to, and refreshes the circle list first — the
    /// caller is about to select that id, and selecting one `CircleStore` has never heard of
    /// resolves back to the old circle.
    @Test func joiningAnswersWithTheCircleToSwitchTo() async {
        let (store, circles, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.ok(Self.group), Self.ok(Self.circles)])

        store.setCode("K7MQ2X")
        let id = await store.join()

        #expect(id == "b0000000-0000-4000-8000-000000000002")
        #expect(store.failure == nil)
        #expect(circles.circles.count == 1, "the list was refreshed before the caller selects")
    }

    /// A code that names nothing gets `onboarding.group.code.error` — *"No group with that
    /// code"* — and not `error.notfound`'s *"That doesn't exist"*, which leaves somebody
    /// wondering what did not.
    @Test func anUnknownCodeSaysSo() async {
        let (store, _, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.failure(404, "NOT_FOUND")])

        store.setCode("K7MQ2X")
        let id = await store.join()

        #expect(id == nil)
        #expect(store.failure == "onboarding.group.code.error")
    }

    /// **The case this whole slice exists around.** Under one circle per person,
    /// `ALREADY_IN_GROUP` meant "you are in a group" and onboarding swallowed it. Under ADR-011
    /// it means "you are in *that* group" — a fact worth stating, on a sheet that stays open
    /// with the code still in it so the caller can correct a mistyped character.
    @Test func alreadyInThatCircleIsStatedRatherThanSwallowed() async {
        let (store, _, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.failure(409, "ALREADY_IN_GROUP")])

        store.setCode("K7MQ2X")
        let id = await store.join()

        #expect(id == nil)
        #expect(store.failure == "error.alreadyingroup")
        #expect(store.code == "K7MQ2X", "the sheet stays usable")
    }

    /// ADR-011's cap, reported as itself rather than as a generic failure.
    @Test func theCircleCapIsReportedAsTheCap() async {
        let (store, _, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.failure(409, "CIRCLE_LIMIT_REACHED")])

        store.setCode("K7MQ2X")
        #expect(await store.join() == nil)
        #expect(store.failure == "error.circlelimitreached")
    }

    /// Typing again clears the last answer: an error under a field the caller is actively
    /// correcting is an error about a code that no longer exists.
    @Test func editingTheCodeClearsTheFailure() async {
        let (store, _, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.failure(404, "NOT_FOUND")])

        store.setCode("K7MQ2X")
        _ = await store.join()
        #expect(store.failure != nil)

        store.setCode("K7MQ2")
        #expect(store.failure == nil)
    }

    /// `POST /groups/join` is rate-limited at ten an hour because it is the invite-code
    /// brute-force surface (`docs/04` §8). One tap must cost one attempt — `Endpoint.joinGroup`
    /// carries `retry: .never` and this is the test that keeps it that way.
    @Test func joiningIsNeverRetried() async {
        let (store, _, api) = Self.harness()
        _ = api
        JoinCircleStub.arm([Self.failure(500, "INTERNAL")])

        store.setCode("K7MQ2X")
        _ = await store.join()

        #expect(JoinCircleStub.taken.filter { $0.path.hasSuffix("/groups/join") }.count == 1)
    }
}
