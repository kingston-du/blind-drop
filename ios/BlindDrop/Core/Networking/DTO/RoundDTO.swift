import Foundation

/// A round's state, as the server names it. The client never assigns one (`CLAUDE.md` §2.2):
/// this type is decoded and read, and the only place it is written is the decoder below.
enum RoundState: String, Decodable, Sendable, Equatable {
    case open, revealed, scored, voided
}

/// The caller's own sealed song. Only ever the caller's own — there is no shape in this file
/// that can hold somebody else's submission before `revealed`, which is the blind window
/// expressed as a type rather than as a filter.
struct SubmissionDTO: Decodable, Sendable, Equatable {
    let track: TrackDTO
    /// When the thing that is *currently* sealed was sealed: a replacement moves it. Safe to
    /// show during `open` for one reason — it is the caller's own data (`docs/14` §3).
    let sealedAt: Date

    enum CodingKeys: String, CodingKey {
        case track
        case sealedAt = "sealed_at"
    }
}

/// One card on the reveal screen: a number and a song, and **no owner**. The owner is the
/// game; it arrives with the results and not one minute earlier.
struct CardDTO: Decodable, Sendable, Equatable, Identifiable {
    let cardNumber: Int
    let track: TrackDTO

    var id: Int { cardNumber }

    enum CodingKeys: String, CodingKey {
        case cardNumber = "card_no"
        case track
    }
}

/// One line of the caller's own saved sheet.
struct GuessDTO: Decodable, Sendable, Equatable, Identifiable {
    let cardNumber: Int
    let guessedUserID: String

    var id: Int { cardNumber }

    enum CodingKeys: String, CodingKey {
        case cardNumber = "card_no"
        case guessedUserID = "guessed_user_id"
    }
}

/// Why a member is looking at a revealed round they cannot play (`docs/04` §4).
enum CannotGuessReason: String, Decodable, Sendable, Equatable {
    /// They did not drop a song tonight. `docs/02` §3: only submitters guess.
    case notASubmitter = "not_a_submitter"
    /// They joined after the reveal. They are in from tomorrow.
    case joinedLate = "joined_late"
}

/// Everything a `revealed` round carries beyond the base keys.
///
/// It exists as its own type so that it can be the *payload of a case* — see `RoundDTO.Phase`.
/// A view holding an `open` round cannot reach any of this, because there is nowhere on an
/// `open` round for it to be.
struct RevealPayload: Sendable, Equatable {
    /// The caller's own card, or `nil` if they did not submit. The client removes it from the
    /// guessing sheet; the card itself stays in `cards`, because the numbering is the game's
    /// spine and must not have a hole in it (`docs/04` §4).
    let myCardNumber: Int?
    let canGuess: Bool
    /// Set exactly when `canGuess` is false.
    let cannotGuessReason: CannotGuessReason?
    /// Every card in the round, ascending, identical for every member.
    let cards: [CardDTO]
    /// Exactly this round's submitters, the caller **included**. The client removes itself;
    /// returning it whole is what keeps the client's arithmetic honest and makes `S`
    /// derivable for "6 of 7 assigned" (`docs/04` §4).
    let namePool: [MemberDTO]
    /// The caller's own sheet, and nobody else's. There is no URL in this phase that returns
    /// another member's guesses.
    let myGuesses: [GuessDTO]
}

/// `GET /rounds/current` — the workhorse (`docs/04` §4), decoded so that **impossible states
/// are unrepresentable** (`docs/13` §3).
///
/// The phase is an enum with associated values and the custom decoder below reads only the
/// keys that phase actually has. That is the blind window enforced by the compiler on the
/// client side: a view holding an `open` round has no `cards` property to read, no optional to
/// unwrap "just in case", and no way for a well-meaning refactor to render one early. The
/// server would never send them — this is the second lock.
struct RoundDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    /// The group-local calendar date this round belongs to, `YYYY-MM-DD`. A string, not a
    /// `Date`: it is a calendar day in the *group's* timezone (`docs/13` §5 rule 6), and
    /// parsing it into an instant here would silently reinterpret it in the device's.
    let localDate: String
    let opensAt: Date
    let revealsAt: Date
    let scoresAt: Date
    let phase: Phase

    /// The four phases, each carrying exactly what `docs/04` §4 says it carries.
    enum Phase: Sendable, Equatable {
        /// Tonight, before the reveal. The caller's own submission, or `nil` — and **nothing
        /// about anybody else**: no count, no roster of who has dropped, nothing derived from
        /// anyone's participation.
        case open(mySubmission: SubmissionDTO?)
        /// Fewer than three drops. Same shape as `open`, and specifically *not* a count of how
        /// many did submit — "only 2 dropped" identifies people in a group of eight
        /// (`docs/08` §5).
        case voided(mySubmission: SubmissionDTO?)
        /// The window is over: the cards, the name pool, and the caller's own sheet.
        case revealed(mySubmission: SubmissionDTO?, payload: RevealPayload)
        /// Scored. The base keys and nothing else; the results are their own route, which is
        /// what keeps the launch call small and lets a push deep-link into them.
        case scored(mySubmission: SubmissionDTO?)
    }

    var state: RoundState {
        switch phase {
        case .open: .open
        case .voided: .voided
        case .revealed: .revealed
        case .scored: .scored
        }
    }

    /// The caller's own song, in whatever phase. Always theirs, never anyone else's.
    var mySubmission: SubmissionDTO? {
        switch phase {
        case let .open(mine), let .voided(mine), let .scored(mine): mine
        case let .revealed(mine, _): mine
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "round_id"
        case localDate = "local_date"
        case state
        case opensAt = "opens_at"
        case revealsAt = "reveals_at"
        case scoresAt = "scores_at"
        case mySubmission = "my_submission"
        case myCardNumber = "my_card_no"
        case canGuess = "can_guess"
        case cannotGuessReason = "cannot_guess_reason"
        case cards
        case namePool = "name_pool"
        case myGuesses = "my_guesses"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        localDate = try container.decode(String.self, forKey: .localDate)
        opensAt = try container.decode(Date.self, forKey: .opensAt)
        revealsAt = try container.decode(Date.self, forKey: .revealsAt)
        scoresAt = try container.decode(Date.self, forKey: .scoresAt)

        let mine = try container.decodeIfPresent(SubmissionDTO.self, forKey: .mySubmission)

        // The switch is the whole point of this initialiser. Each branch reads *only* its own
        // phase's keys, so a `cards` array that somehow arrived on an `open` payload would be
        // dropped on the floor here rather than becoming reachable state.
        switch try container.decode(RoundState.self, forKey: .state) {
        case .open:
            phase = .open(mySubmission: mine)
        case .voided:
            phase = .voided(mySubmission: mine)
        case .scored:
            phase = .scored(mySubmission: mine)
        case .revealed:
            phase = .revealed(
                mySubmission: mine,
                payload: RevealPayload(
                    myCardNumber: try container.decodeIfPresent(Int.self, forKey: .myCardNumber),
                    canGuess: try container.decode(Bool.self, forKey: .canGuess),
                    cannotGuessReason: try container.decodeIfPresent(
                        CannotGuessReason.self, forKey: .cannotGuessReason),
                    cards: try container.decode([CardDTO].self, forKey: .cards),
                    namePool: try container.decode([MemberDTO].self, forKey: .namePool),
                    myGuesses: try container.decode([GuessDTO].self, forKey: .myGuesses)
                )
            )
        }
    }
}

/// The response to `PUT /rounds/current/guesses` — the caller's saved sheet and two counts,
/// both of which are about the caller (`docs/04` §4).
///
/// `assignableCount` is `S − 1`: every card except their own. Neither number says anything
/// about whether anybody else has opened their sheet, and there is no field here that could.
struct GuessSheetDTO: Decodable, Sendable, Equatable {
    let assignments: [GuessDTO]
    let assignedCount: Int
    let assignableCount: Int

    enum CodingKeys: String, CodingKey {
        case assignments
        case assignedCount = "assigned_count"
        case assignableCount = "assignable_count"
    }
}
