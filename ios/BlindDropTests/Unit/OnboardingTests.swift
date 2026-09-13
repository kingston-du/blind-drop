import Foundation
import Testing
@testable import BlindDrop

// MARK: - Validation

/// `docs/14` §7's display-name rule, on the client side.
///
/// The cases below are **the server's cases**, copied from
/// `server/supabase/tests/functions/me.test.ts`. That is the point of the whole type: the client
/// cleans a name so the person typing sees what will actually be saved, and a client that
/// cleaned it *differently* would be worse than one that did not clean it at all — the field
/// would promise one name and the guess sheet would show another.
@Suite struct DisplayNameTests {

    /// Verbatim from `PUT /me strips control, zero-width and RTL-override characters`.
    @Test(arguments: [
        ("Ana\u{202E}Ben", "AnaBen"),        // right-to-left override: reorders the guess sheet
        ("Ana\u{200B}Ben", "AnaBen"),        // zero width space: two visually identical names
        ("Ana\u{200D}\u{2066}Ben", "AnaBen"), // joiner and isolate
        ("An\u{0000}a", "Ana"),              // NUL
        // Newlines are *stripped*, not turned into spaces: the name is one line by
        // construction, and gluing the words is the honest result of pasting two.
        ("Ana\nBen", "AnaBen"),
        ("Ana\tBen", "AnaBen"),
        ("Ana\u{00AD}Ben", "AnaBen"),        // soft hyphen
        ("\u{FEFF}Ana", "Ana"),              // byte order mark
    ])
    func cleaningMatchesTheServer(_ sent: String, _ stored: String) {
        #expect(DisplayName.clean(sent) == stored)
    }

    /// Ordinary whitespace is collapsed and trimmed rather than stripped — it is the one kind
    /// of space a person types on purpose.
    @Test func whitespaceIsCollapsedAndTrimmed() {
        #expect(DisplayName.clean("  Ana  ") == "Ana")
        #expect(DisplayName.clean("Ana   Lee") == "Ana Lee")
        #expect(DisplayName.clean("\u{00A0}Ana\u{00A0}Lee") == "Ana Lee", "non-breaking space too")
    }

    /// NFC, so `e` + combining acute and the precomposed `é` are one name and not two.
    @Test func namesAreNormalised() {
        #expect(DisplayName.clean("Ane\u{0301}s") == DisplayName.clean("Anés"))
        #expect(DisplayName.length(DisplayName.clean("Ane\u{0301}s")) == 4)
    }

    /// A name that is *only* invisible characters cleans down to nothing, and nothing is not a
    /// name — the server refuses it with a 400 and the button must not have been live.
    @Test func anAllInvisibleNameIsEmpty() {
        #expect(DisplayName.clean("\u{200B}\u{200B}\u{202E}").isEmpty)
        #expect(DisplayName.problem(with: "\u{200B}\u{200B}\u{202E}") == .empty)
        #expect(DisplayName.problem(with: "   ") == .empty)
        #expect(DisplayName.problem(with: "") == .empty)
    }

    /// Twenty-four characters is twenty-four characters, emoji included (`docs/04` §2, and the
    /// server test of the same name). Counted as characters and not UTF-16 units: `"🎧"` is one
    /// of the former and two of the latter, and telling somebody their 24-emoji name is 48
    /// characters long is a validation error they cannot act on.
    @Test func lengthIsCountedInCharacters() {
        #expect(DisplayName.problem(with: String(repeating: "🎧", count: 24)) == nil)
        #expect(DisplayName.problem(with: String(repeating: "🎧", count: 25)) == .tooLong)
        #expect(DisplayName.problem(with: String(repeating: "a", count: 24)) == nil)
        #expect(DisplayName.problem(with: String(repeating: "a", count: 25)) == .tooLong)
        // The length is measured on the *cleaned* string, so invisibles do not spend budget.
        let padded = String(repeating: "a", count: 24) + String(repeating: "\u{200B}", count: 10)
        #expect(DisplayName.problem(with: padded) == nil)
    }

    /// Both problems have a line in `docs/11`. A missing key renders as the key itself, which
    /// is the one failure mode a user cannot act on.
    @Test func bothProblemsHaveCopy() {
        for problem in [DisplayName.Problem.empty, .tooLong] {
            #expect(Copy.string(problem.copyKey) != problem.copyKey)
        }
    }
}

/// The invite code as the field treats it (`docs/03` §2, `docs/14` §7).
@Suite struct InviteCodeTests {

    @Test func typingIsNormalisedAsItGoes() {
        #expect(InviteCode.normalise("k7mq2x") == "K7MQ2X")
        #expect(InviteCode.normalise("K7MQ2XZZZ") == "K7MQ2X", "six characters, no more")
        #expect(InviteCode.normalise("K7M-Q2X") == "K7MQ2X", "a separator somebody read aloud")
        #expect(InviteCode.normalise(" k7 mq 2x ") == "K7MQ2X")
        #expect(InviteCode.normalise("") == "")
    }

    /// The alphabet excludes `I`, `L`, `O`, `0` and `1`, so those characters cannot be part of
    /// a code and are dropped rather than kept as something that can never match.
    @Test func charactersOutsideTheAlphabetAreDropped() {
        #expect(InviteCode.normalise("K7MQ2X!") == "K7MQ2X")
        #expect(InviteCode.normalise("IL0O1K") == "K")
        #expect(InviteCode.normalise("🎧K7MQ2X") == "K7MQ2X")
    }

    /// The commonest way an invite arrives is as a link. Filtered character by character,
    /// `https://blinddrop.app/j/K7MQ2X` would come out as six characters of nonsense that look
    /// exactly like a code — so the link is recognised first.
    @Test func aPastedLinkYieldsItsCode() {
        #expect(InviteCode.normalise("https://blinddrop.app/j/K7MQ2X") == "K7MQ2X")
        #expect(InviteCode.normalise("https://blinddrop.app/j/k7mq2x") == "K7MQ2X")
        #expect(InviteCode.normalise("blinddrop://join/K7MQ2X") == "K7MQ2X")
        #expect(InviteCode.normalise(" https://blinddrop.app/j/K7MQ2X ") == "K7MQ2X")
        // A link we do not recognise is not mined for characters either.
        #expect(InviteCode.normalise("https://example.com/j/K7MQ2X") == "")
    }

    @Test func completenessIsSixCharacters() {
        #expect(!InviteCode.isComplete("K7MQ2"))
        #expect(InviteCode.isComplete("K7MQ2X"))
    }

    /// **Share invite** shares the URL, not the bare code (`docs/05` §5): six characters in a
    /// message are six characters somebody has to be told what to do with.
    @Test func theShareTargetIsTheInviteURL() {
        #expect(InviteCode.inviteURL(for: "K7MQ2X")?.absoluteString
                == "https://blinddrop.app/j/K7MQ2X")
        #expect(InviteCode.inviteURL(for: "k7mq2x")?.absoluteString
                == "https://blinddrop.app/j/K7MQ2X", "shared uppercase, whatever was held")
        // And what it produces is a link the app itself accepts — the round trip is the point.
        let url = InviteCode.inviteURL(for: "K7MQ2X")
        #expect(url.flatMap(DeepLink.init) == .join(code: "K7MQ2X"))
    }

    /// VoiceOver spells the code rather than pronouncing it.
    @Test func theCodeIsSpelledForVoiceOver() {
        #expect(JoinOrCreateScreen.spelled("K7MQ2X") == "K 7 M Q 2 X")
    }
}

/// The reveal hour, and the day it implies (`docs/02` §1, `docs/08` §1.4).
@Suite struct RevealHourTests {

    /// Pinned to a locale, because the point is that the picker shows a **clock**, not a number.
    ///
    /// Compared with the space before the meridiem normalised: iOS sets it as a narrow no-break
    /// space (U+202F), which is correct typography and is what should be drawn. Asserting the
    /// literal character would be asserting a Foundation implementation detail — the claim
    /// here is about the digits and the *"PM"*, which is what `docs/08` §1.4 writes.
    @Test func hoursAreShownAsAPersonReadsThem() {
        let english = Locale(identifier: "en_US")
        #expect(Self.spaceNormalised(RevealHour.formatted(18, locale: english)) == "6:00 PM")
        #expect(Self.spaceNormalised(RevealHour.formatted(20, locale: english)) == "8:00 PM")
        #expect(Self.spaceNormalised(RevealHour.formatted(21, locale: english)) == "9:00 PM")
    }

    private static func spaceNormalised(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// `docs/04` §3: optional, default 20, range 18…21.
    @Test func theRangeIsTheContract() {
        #expect(RevealHour.default == 20)
        #expect(RevealHour.allowed == 18...21)
        #expect(RevealHour.allowed.contains(RevealHour.default))
    }

    /// The consequence the copy states: songs open ten hours before, answers land two after.
    @Test func theHourImpliesTheWholeDay() {
        #expect(RevealHour.opensHour(revealHour: 20) == 10)
        #expect(RevealHour.scoresHour(revealHour: 20) == 22)
        #expect(RevealHour.opensHour(revealHour: 18) == 8)
        // 21:00 + 2 is 23:00, still the same day; the wrap is there for arithmetic honesty
        // rather than because the allowed range reaches it.
        #expect(RevealHour.scoresHour(revealHour: 21) == 23)
    }
}

// MARK: - The store

/// A `URLProtocol` answering from a queue, recording the path and the **body** of everything it
/// was asked.
///
/// The body is read here, inside `startLoading`, and not off the `URLRequest` afterwards.
/// `URLSession` moves an `httpBody` into an `httpBodyStream` before a protocol sees it, and the
/// stream is spent by the time a test could look — a suite that read the request later would
/// assert against `nil` and think it had proved something.
class RecordingStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var body: Data = Data()
    }

    /// One taken request, flattened to the two things a test asks about.
    struct Taken: Sendable {
        let path: String
        let body: Data
    }

    /// The per-subclass queue. Each stub class is its own answering machine, so two suites
    /// running at once cannot answer each other's requests — the convention `AuthStub` sets.
    final class Channel: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [Reply] = []
        private var last = Reply()
        private var requests: [Taken] = []

        func arm(_ replies: [Reply]) {
            lock.lock(); defer { lock.unlock() }
            queue = replies
            last = replies.last ?? Reply()
            requests = []
        }

        func next() -> Reply {
            lock.lock(); defer { lock.unlock() }
            return queue.isEmpty ? last : queue.removeFirst()
        }

        func record(_ taken: Taken) {
            lock.lock(); defer { lock.unlock() }
            requests.append(taken)
        }

        var taken: [Taken] {
            lock.lock(); defer { lock.unlock() }
            return requests
        }
    }

    /// Overridden by each concrete stub. The base class has none — it is never registered.
    class var channel: Channel { fatalError("RecordingStub is abstract") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let channel = Self.channel
        channel.record(Taken(path: request.url?.path() ?? "", body: Self.body(of: request)))
        let reply = channel.next()
        let http = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4_096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(contentsOf: buffer[..<read])
        }
        return data
    }
}

/// The onboarding store's channel.
final class OnboardingStub: RecordingStub, @unchecked Sendable {
    private static let shared = Channel()
    override class var channel: Channel { shared }

    static func arm(_ replies: [Reply]) { shared.arm(replies) }
    static var taken: [Taken] { shared.taken }
}

/// The session-routing suite's channel. A second class and not a second queue on the first,
/// so the two suites can run at the same time and still each count their own requests.
final class RoutingStub: RecordingStub, @unchecked Sendable {
    private static let shared = Channel()
    override class var channel: Channel { shared }

    static func arm(_ replies: [Reply]) { shared.arm(replies) }
    static var taken: [Taken] { shared.taken }
}

/// A store wired to a stubbed client, with the session reachable.
@MainActor
struct OnboardingHarness {
    let session: SessionStore
    let store: OnboardingStore
    /// Held so the client outlives the test — `SessionStore` keeps only a weak reference.
    let api: APIClient

    private let taken: () -> [RecordingStub.Taken]

    init(stub: RecordingStub.Type = OnboardingStub.self) {
        let session = SessionStore(auth: FakeAuth(), secrets: MemorySecrets())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        let api = APIClient(
            baseURL: URL(string: "https://fixture.test/functions/v1")!,
            clock: ServerClock(),
            session: session,
            transport: APIClient.makeTransport(configuration)
        )
        session.attach(api)
        self.session = session
        self.api = api
        self.store = OnboardingStore(api: api, session: session)
        self.taken = { stub.channel.taken }
    }

    /// The paths of every request the run actually made, in order — which is how "the session
    /// was **not** re-read" becomes a countable fact rather than an intention.
    var paths: [String] { taken().map(\.path) }

    var bodies: [Data] { taken().map(\.body) }
}

/// `docs/08` §1.2–1.5, as a state machine.
///
/// `.serialized` because `OnboardingStub` is process-wide: one queue of canned replies and one
/// list of requests, which is what makes "one request, not two" countable.
@MainActor
@Suite(.serialized) struct OnboardingStoreTests {

    private static func envelope(_ payload: String) -> Data {
        Data(#"{"server_now":"2026-08-10T18:42:07Z","data":\#(payload)}"#.utf8)
    }

    private static func ok(_ payload: String) -> OnboardingStub.Reply {
        .init(status: 200, body: envelope(payload))
    }

    private static func failure(_ status: Int, _ code: String) -> OnboardingStub.Reply {
        .init(
            status: status,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"}}"#.utf8)
        )
    }

    private static let meNoGroup = #"{"user_id":"u_ana","display_name":"Ana","has_group":false}"#
    private static let meReady = #"{"user_id":"u_ana","display_name":"Ana","has_group":true}"#
    private static let group = """
        {"id":"g_1","name":"The Cove","timezone":"America/New_York","reveal_hour":20,
         "invite_code":"K7MQ2X","is_admin":true,
         "members":[{"user_id":"u_ana","display_name":"Ana"}]}
        """

    // MARK: - 1.2, the name

    /// **Continue** is disabled until the name is valid (`docs/08` §1.2), and "valid" is
    /// measured on what will actually be stored.
    @Test func continueIsGatedOnTheCleanedName() {
        let h = OnboardingHarness()
        #expect(!h.store.canContinue, "an empty field is not a name")

        h.store.name = "   "
        #expect(!h.store.canContinue)

        h.store.name = "\u{200B}\u{202E}"
        #expect(!h.store.canContinue, "invisible characters are not a name either")

        h.store.name = String(repeating: "a", count: 25)
        #expect(!h.store.canContinue)
        #expect(h.store.nameError == "onboarding.name.error.long",
                "the line explains the button that just went grey")

        h.store.name = "  Ana  "
        #expect(h.store.canContinue)
        #expect(h.store.cleanedName == "Ana")
        #expect(h.store.nameError == nil, "a field nobody has failed at shows no error")
    }

    /// The name that goes to the server is the cleaned one — what the help line promised the
    /// user their friends would be guessing with.
    @Test func savingSendsTheCleanedNameAndRereadsTheSession() async throws {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.ok(Self.meNoGroup), Self.ok(Self.meNoGroup)])

        h.store.name = "  Ana\u{200B}  Lee  "
        await h.store.saveName()

        let body = try #require(h.bodies.first)
        #expect(String(decoding: body, as: UTF8.self) == #"{"display_name":"Ana Lee"}"#)
        #expect(h.paths == ["/functions/v1/me", "/functions/v1/me"],
                "the save, then the server deciding what comes next")
        #expect(h.session.state == .noGroup, "the server routed, not the client")
    }

    /// A refusal is shown inline and the flow stays where it is. It also clears the moment the
    /// user types, because an error about a name they have since changed is noise.
    @Test func aRefusedNameShowsItsLineAndClearsOnTheNextKeystroke() async {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.failure(400, "INVALID_INPUT")])

        h.store.name = "Ana"
        await h.store.saveName()

        #expect(h.store.nameError != nil)
        #expect(h.session.state == .unknown, "a rejected name is not a routed session")

        h.store.name = "Ana Lee"
        #expect(h.store.nameError == nil)
    }

    // MARK: - 1.3, joining

    @Test func joiningIsGatedOnSixCharacters() {
        let h = OnboardingHarness()
        h.store.setCode("K7MQ2")
        #expect(!h.store.canJoin)
        h.store.setCode("K7MQ2X")
        #expect(h.store.canJoin)
    }

    /// The field holds only things a code could be, whatever is typed or pasted into it.
    ///
    /// `setCode(_:)` rather than `code =`, since `E38-02` — `code` is `private(set)` and the
    /// screen's field is bound through this setter, which is what makes the normalisation
    /// actually reach the text field. See `OnboardingStore.code`.
    @Test func theFieldNormalisesWhatIsPutInIt() {
        let h = OnboardingHarness()
        h.store.setCode("k7mq2x")
        #expect(h.store.code == "K7MQ2X")

        h.store.setCode("https://blinddrop.app/j/K7MQ2X")
        #expect(h.store.code == "K7MQ2X")

        // Over-length, and characters the alphabet excludes (`I`, `L`, `O`, `0`, `1`).
        h.store.setCode("aaa222o")
        #expect(h.store.code == "AAA222")
    }

    /// *"Lands straight on today's round after joining — no confirmation, no welcome"*
    /// (`docs/08` §1.5).
    @Test func joiningLandsStraightOnTheRound() async {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.ok(Self.group), Self.ok(Self.meReady)])

        h.store.setCode("K7MQ2X")
        await h.store.join()

        #expect(h.paths == ["/functions/v1/groups/join", "/functions/v1/me"])
        #expect(h.session.state == .ready)
        #expect(h.store.step == .joinOrCreate, "no invite screen for a joiner")
    }

    /// `NOT_FOUND` renders `onboarding.group.code.error` and not the generic *"That doesn't
    /// exist"* — the user needs to know it was the **code**.
    @Test func anUnknownCodeGetsItsOwnLine() async {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.failure(404, "NOT_FOUND")])

        h.store.setCode("K7MQ2X")
        await h.store.join()

        #expect(h.store.joinFailure == "onboarding.group.code.error")
        #expect(Copy.string("onboarding.group.code.error") != "onboarding.group.code.error")
        #expect(h.session.state == .unknown)
        #expect(h.paths.count == 1, "a join is never retried — it is the brute-force surface")
    }

    /// ADR-005, one group per user. Being told *"you're already in a group"* is not something
    /// the user can act on — they are in a group, which is where they were going.
    @Test func alreadyInAGroupRoutesRatherThanErrors() async {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.failure(409, "ALREADY_IN_GROUP"), Self.ok(Self.meReady)])

        h.store.setCode("K7MQ2X")
        await h.store.join()

        #expect(h.store.joinFailure == nil, "no error the user can do anything about")
        #expect(h.session.state == .ready)
    }

    // MARK: - 1.4, creating

    /// The one that the whole store exists for: creating a group makes `GET /me` answer
    /// `has_group: true`, so re-reading the session here would route the creator **past** their
    /// invite code to today's round. It is not re-read, and the request count proves it.
    @Test func creatingStopsOnTheInviteCodeRatherThanTheRound() async throws {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.ok(Self.group)])

        h.store.groupName = "The Cove"
        h.store.timezone = "America/New_York"
        h.store.revealHour = 20
        await h.store.create()

        #expect(h.paths == ["/functions/v1/groups"], "no GET /me — that would skip the code")
        #expect(h.session.state == .unknown, "the session is deliberately not moved on yet")
        guard case .invite(let created) = h.store.step else {
            Issue.record("expected the invite step, got \(h.store.step)")
            return
        }
        #expect(created.inviteCode == "K7MQ2X")

        // And **Go to today's round** is the one thing that moves it on.
        OnboardingStub.arm([Self.ok(Self.meReady)])
        await h.store.finish()
        #expect(h.session.state == .ready)
    }

    @Test func creatingSendsTheFormAsChosen() async throws {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.ok(Self.group)])

        h.store.groupName = "  The Cove  "
        h.store.timezone = "Europe/Lisbon"
        h.store.revealHour = 19
        await h.store.create()

        let body = try #require(h.bodies.first)
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(decoded["name"] as? String == "The Cove")
        #expect(decoded["timezone"] as? String == "Europe/Lisbon")
        #expect(decoded["reveal_hour"] as? Int == 19)
    }

    /// The device's timezone is a default, not a decision — but it has to be the default, or
    /// the commonest case is a picker somebody has to go find.
    @Test func theTimezoneDefaultsToTheDevice() {
        let h = OnboardingHarness()
        #expect(h.store.timezone == TimeZone.current.identifier)
        #expect(h.store.revealHour == RevealHour.default)
        #expect(!h.store.canCreate, "a group with no name is not a group")

        h.store.groupName = "   "
        #expect(!h.store.canCreate)
        h.store.groupName = "The Cove"
        #expect(h.store.canCreate)
    }

    @Test func creatingIsReachableAndCancellable() {
        let h = OnboardingHarness()
        #expect(h.store.step == .joinOrCreate)
        h.store.startCreating()
        #expect(h.store.step == .create)
        h.store.cancelCreating()
        #expect(h.store.step == .joinOrCreate, "a create form with no way out is a trap")
    }

    // MARK: - The link

    /// *"A deep link is a navigation hint, not an authorization"* (`docs/05` §5). The code is
    /// prefilled; **nothing is joined** until somebody taps the button.
    @Test func aLinkPrefillsAndDoesNotJoin() {
        let h = OnboardingHarness()
        OnboardingStub.arm([Self.ok(Self.group)])

        h.store.prefill(code: "K7MQ2X")

        #expect(h.store.code == "K7MQ2X")
        #expect(h.store.canJoin)
        #expect(OnboardingStub.taken.isEmpty, "a link joins nothing on its own")
    }

    /// A link that lands while somebody is halfway through typing a different code does not
    /// eat their work.
    @Test func aLinkDoesNotOverwriteACodeBeingTyped() {
        let h = OnboardingHarness()
        h.store.setCode("ABC")
        h.store.prefill(code: "K7MQ2X")
        #expect(h.store.code == "ABC")
    }

    /// And it puts the user on the join step, wherever they had wandered to.
    @Test func aLinkReturnsToTheJoinStep() {
        let h = OnboardingHarness()
        h.store.startCreating()
        h.store.prefill(code: "K7MQ2X")
        #expect(h.store.step == .joinOrCreate)
    }

    /// E09-04's verify line, as far as a test can carry it: *"`blinddrop://join/K7MQ2X`
    /// prefills the field."*
    ///
    /// Every link in the chain, from the URL the system hands `.onOpenURL` to a field holding a
    /// complete code and a live button — the parse, the router's hold, the consume at
    /// `.noGroup`, and the flow's hand-off. The two ends are checked elsewhere and neither is
    /// this: `DeepLinkTests` proves the parse and the golden `JoinOrCreate-prefilled` proves
    /// the pixels. What is only true here is that the pieces are actually joined up.
    ///
    /// The universal link is walked alongside it, because `applinks` reaches the router by a
    /// different door (`.onContinueUserActivity`) and arriving at a different place would be a
    /// bug nobody would find until an invite was shared.
    @Test(arguments: ["blinddrop://join/K7MQ2X", "https://blinddrop.app/j/K7MQ2X"])
    func aLinkTravelsAllTheWayToTheField(_ raw: String) throws {
        let h = OnboardingHarness()
        let router = Router()

        router.receive(DeepLink(URL(string: raw)!))
        #expect(router.pendingInviteCode == nil, "held, not applied — a link navigates nothing")

        // The session settles on `.noGroup`, which is the only state the code is for.
        router.consume(session: .noGroup, roundIsLoaded: false)
        let pending = try #require(router.pendingInviteCode)

        // What `OnboardingFlow` does with it.
        h.store.prefill(code: pending)
        router.clearPendingInviteCode()

        #expect(h.store.code == "K7MQ2X")
        #expect(h.store.canJoin, "the button is live; the user still has to press it")
        #expect(router.pendingInviteCode == nil, "consumed once, so returning does not re-prefill")
        #expect(OnboardingStub.taken.isEmpty, "and nothing was joined on the way")
    }
}

// MARK: - Routing on what the server said

/// `docs/04` §2: the client routes on `NO_PROFILE` **from any endpoint**, not only from
/// `GET /me`. E09-02's last checkbox, and the reason `SessionStore.noteServerSaid(_:)` exists.
@MainActor
@Suite(.serialized) struct SessionRoutingTests {

    private func harness() -> OnboardingHarness { OnboardingHarness(stub: RoutingStub.self) }

    /// A `NO_PROFILE` from a route that has nothing to do with identity still lands the user on
    /// step 1.2. Asserted through `GET /rounds/current`, which is where it would actually
    /// happen: a person who deleted their profile on another device is looking at a round.
    @Test func noProfileFromAnyEndpointRoutesToNaming() async {
        let h = harness()
        RoutingStub.arm([.init(
            status: 409,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"NO_PROFILE","message":"x"}}"#.utf8)
        )])

        _ = try? await h.api.send(.round("g1"))

        #expect(h.session.state == .noProfile)
        #expect(RootDestination(session: h.session.state) == .displayName)
    }

    /// And `NO_GROUP` lands them back on 1.3 — *"landing back on 1.3 when a user has a profile
    /// but no group (they left a group)"* (E09-04).
    @Test func noGroupFromAnyEndpointRoutesToJoining() async {
        let h = harness()
        RoutingStub.arm([.init(
            status: 409,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"NO_GROUP","message":"x"}}"#.utf8)
        )])

        _ = try? await h.api.send(.round("g1"))

        #expect(h.session.state == .noGroup)
        #expect(RootDestination(session: h.session.state) == .joinOrCreate)
    }

    /// Every other code says something about a **request**, not about a person. A session that
    /// moved on a `WRONG_PHASE` would be a session that sent somebody to onboarding because a
    /// song lookup came back at the wrong moment.
    @Test(arguments: ["WRONG_PHASE", "NOT_FOUND", "RATE_LIMITED", "UPSTREAM_UNAVAILABLE", "INTERNAL"])
    func otherFailuresLeaveTheSessionAlone(_ code: String) async {
        let h = harness()
        RoutingStub.arm([.init(
            status: 409,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"}}"#.utf8)
        )])

        _ = try? await h.api.send(.round("g1"))

        #expect(h.session.state == .unknown)
    }
}
