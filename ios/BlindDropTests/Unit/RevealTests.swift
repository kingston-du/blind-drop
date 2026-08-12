import Foundation
import Testing
@testable import BlindDrop

/// `E11-01`. The reveal screen's two decisions that are not pixels: what order the cards come
/// in, and what each one says about the caller's guess.
///
/// Both are tested on `RevealViewState` rather than through the view, because both are rules
/// rather than layout — and a rule that is only checked by a golden PNG is a rule that fails as
/// "3.1% of pixels differ".
@Suite struct RevealViewStateTests {

    // MARK: - Order

    /// *"Cards render in ascending `card_no`, exactly as the server ordered them."*
    ///
    /// The state hands the view its array untouched. There is no `sorted()` anywhere in
    /// `Features/Reveal/`, and this test plus `theStateDoesNotReorderWhatTheServerSent` below
    /// are what keep it that way: `card_no` is the server's shuffle (`E03-04`), identical for
    /// every member, and a client that re-sorted it would be inventing a second opinion about
    /// the one number the whole group refers to songs by.
    @Test func cardsArriveAscendingAndStayThatWay() {
        let state = RevealFixture.state(cardCount: 8)
        #expect(state.cards.map(\.cardNumber) == Array(1...8))
    }

    /// The state is a passthrough, proven by handing it an order no server would send: if
    /// anything in here ever starts sorting, this is the test that says so.
    @Test func theStateDoesNotReorderWhatTheServerSent() {
        let scrambled = [5, 1, 3].map { RevealFixture.card(number: $0) }
        let state = RevealFixture.state(cards: scrambled)
        #expect(state.cards.map(\.cardNumber) == [5, 1, 3])
    }

    // MARK: - Assignment

    /// The caller's own card is `.mine` — it keeps its place in the numbering and loses its
    /// chip (`docs/08` §6).
    @Test func myOwnCardIsMineAndNotGuessable() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: 4)
        #expect(state.assignment(for: 4) == .mine)
    }

    /// **Own card beats every other rule.** A non-submitter has no own card, so the two can only
    /// collide through a bug — and if they ever do, the caller's own song must not be the thing
    /// that gets relabelled.
    @Test func myOwnCardStaysMineEvenWhenTheCallerCannotGuess() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: 2, canGuess: false)
        #expect(state.assignment(for: 2) == .mine)
    }

    /// A non-submitter's cards carry **no chip at all**, rather than a disabled-looking one.
    /// `docs/08` §6 wants the apparatus visible and inert; `FlightCard` draws `.unavailable` as
    /// nothing, because there is no control coming that a disabled chip could be promising.
    @Test func aNonSubmitterGetsNoChip() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: nil, canGuess: false)
        for number in 1...6 {
            #expect(state.assignment(for: number) == .unavailable)
        }
    }

    @Test func anUnguessedCardAsksItsQuestion() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: 4)
        #expect(state.assignment(for: 1) == .unguessed)
    }

    @Test func aGuessedCardCarriesTheName() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: 4, guesses: [1: "Cal"])
        #expect(state.assignment(for: 1) == .guessed(name: "Cal"))
        #expect(state.assignment(for: 2) == .unguessed)
    }

    /// A guess against the caller's own card would be a server-side impossibility (`docs/04` §4
    /// rule 4 rejects it), so the client does not render one either. `.mine` wins.
    @Test func aGuessOnMyOwnCardIsIgnoredRatherThanDrawn() {
        let state = RevealFixture.state(cardCount: 6, myCardNumber: 4, guesses: [4: "Cal"])
        #expect(state.assignment(for: 4) == .mine)
    }

    // MARK: - The count

    /// *"8 songs"* is the number of cards, which is `S`. Printing it here is not a leak: the
    /// round is `revealed`, and the count stopped being a secret at the moment the cards did.
    @Test func theSongCountIsTheNumberOfCards() {
        #expect(RevealFixture.state(cardCount: 12).songCount == 12)
    }
}

// MARK: - Fixtures

/// Rounds of an arbitrary size.
///
/// Its own fixture rather than the snapshot suite's, because `BlindDropTests/Unit` and
/// `BlindDropTests/Snapshot` are **separate targets** (each folder is its own
/// `PBXFileSystemSynchronizedRootGroup`) and share no code. That is the right split: what these
/// tests need from a track is that it exists, and building it here keeps a rule test from
/// depending on the artwork URL template a golden happens to be drawn with.
///
/// `@MainActor`-free on purpose: none of this touches a view, so the rule tests above run
/// without one.
enum RevealFixture {

    /// A fixed instant. Nothing here reads a clock — `answersAt` is carried by the state and
    /// only the snapshots draw it.
    static let answersAt = Date(timeIntervalSince1970: 1_786_006_139)

    /// The one track these tests need. They are about numbers and chips, not about songs.
    static let track = TrackDTO(
        trackKey: "isrc:NZUM71300123",
        isrc: "NZUM71300123",
        title: "Ribs",
        artist: "Lorde",
        album: "Pure Heroine",
        artworkURL: "https://example.test/{w}x{h}bb.jpg",
        artworkBackgroundColor: "1d2b3a",
        durationMilliseconds: 249_000,
        previewURL: nil,
        appleMusicID: "1440857781",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/ribs/1440857781")!,
        spotifyID: nil,
        spotifyURL: nil
    )

    static func card(number: Int) -> CardDTO {
        CardDTO(cardNumber: number, track: track)
    }

    static func state(
        cardCount: Int,
        myCardNumber: Int? = nil,
        canGuess: Bool = true,
        guesses: [Int: String] = [:]
    ) -> RevealViewState {
        state(
            cards: (1...cardCount).map(card(number:)),
            myCardNumber: myCardNumber,
            canGuess: canGuess,
            guesses: guesses
        )
    }

    static func state(
        cards: [CardDTO],
        myCardNumber: Int? = nil,
        canGuess: Bool = true,
        guesses: [Int: String] = [:]
    ) -> RevealViewState {
        RevealViewState(
            cards: cards,
            myCardNumber: myCardNumber,
            canGuess: canGuess,
            guesses: guesses,
            answersAt: answersAt
        )
    }
}
