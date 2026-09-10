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
    /// The `user_id`s this card offers: its owner and up to three others, never the caller.
    /// Chosen by the server and stable for the life of the round (`_shared/shortlist.ts`).
    ///
    /// Near enough the same four for everybody: the card has one canonical list, and only the
    /// members who appear in it get a substitute in their own slot. The client does not need to
    /// know that — it renders what it is given — but it is why two people can compare a card.
    ///
    /// **This is a narrowing, not a rule.** The owner is always among them, so a name from
    /// outside is always wrong — but it is never *illegal*, and the API accepts it. That is why
    /// nothing in the client blocks a tap: the sheet still supports naming somebody from the
    /// full pool first and choosing a card second, and the shortlist just means the card-first
    /// path stops asking a question with eleven answers.
    ///
    /// Empty when the payload predates this field, which is the honest fallback: an empty
    /// shortlist means "no opinion", and every consumer widens back to the full pool.
    let shortlist: [String]

    var id: Int { cardNumber }

    enum CodingKeys: String, CodingKey {
        case cardNumber = "card_no"
        case track
        case shortlist
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardNumber = try container.decode(Int.self, forKey: .cardNumber)
        track = try container.decode(TrackDTO.self, forKey: .track)
        shortlist = try container.decodeIfPresent([String].self, forKey: .shortlist) ?? []
    }

    /// Tests and previews. The decoder above is the only path a real card takes.
    init(cardNumber: Int, track: TrackDTO, shortlist: [String] = []) {
        self.cardNumber = cardNumber
        self.track = track
        self.shortlist = shortlist
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

/// One cue attached to some rounds (`docs/18-CUES.md` §8): a short, neutral line identical for
/// every member, that steers what people drop without changing how the game is scored. It is a
/// value the server sends — `key` is for joins and future localisation, `text` is what shipped
/// that night and is what every surface renders.
///
/// `key` is `nil` on a cue an admin wrote by hand (`§11.6`, owner amendment 2026-09-09): a
/// custom line has no catalog entry and is never promoted into one. Nothing in the app reads
/// `key`, which is exactly why a keyless cue renders identically to a catalog one.
struct CueDTO: Decodable, Sendable, Equatable {
    let key: String?
    let text: String
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
    /// Tonight's cue, present (or absent) identically across all four phases — it sits on the
    /// base keys, not inside `RevealPayload`, because it is the same value on every screen
    /// (`docs/18-CUES.md` §8). `nil` when the round has none.
    let cue: CueDTO?
    /// The cue of the round *before* this one, sent only during the dark hours and only when
    /// that round had one (`docs/18-CUES.md` §7).
    ///
    /// Between local midnight and `opensAt` this round is the **coming** night's — the screen
    /// over it says *"Tonight's round is done."*, and the round it means is the one that just
    /// finished. `cue` there is a brief nobody has answered yet; this is the one that screen is
    /// talking about. `nil` on every other phase, and on a circle's first night.
    let previousCue: CueDTO?
    /// The id of the round *before* this one, sent only during the dark hours and only when that
    /// round is `scored` (`docs/18-CUES.md` §7).
    ///
    /// The one thing on that screen it cannot get from `id`: at 3 a.m. `id` is the **coming**
    /// night's round, and *"Tonight's round is done."* is about the night that just ended. This
    /// is how that screen links to the results it is talking about.
    ///
    /// Independent of `previousCue` in both directions — a `voided` night has a cue and no
    /// results, an uncued night that scored has results and no cue — which is why it is its own
    /// optional rather than a property of the cue.
    let previousRoundID: String?
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

    /// The same round with the caller's own submission replaced.
    ///
    /// `PUT /rounds/current/submission` returns the sealed submission (`docs/04` §4), and this is
    /// how the screen adopts it without a second round trip — which is what lets the confirm sheet
    /// dismiss onto an already-sealed card rather than onto a submit screen that corrects itself a
    /// moment later (`docs/08` §3.2).
    ///
    /// **It cannot change the phase, and that is structural rather than careful.** Each branch
    /// rebuilds its own case and there is no parameter to pass a different one, so this method has
    /// no way to express "and now the round is revealed". `CLAUDE.md` §2.2 says the client never
    /// decides a phase; the only thing being replaced here is the caller's own data, which the
    /// server has just handed back.
    func adopting(mySubmission submission: SubmissionDTO) -> RoundDTO {
        let adopted: Phase = switch phase {
        case .open: .open(mySubmission: submission)
        case .voided: .voided(mySubmission: submission)
        case .scored: .scored(mySubmission: submission)
        case let .revealed(_, payload): .revealed(mySubmission: submission, payload: payload)
        }
        return RoundDTO(
            id: id, localDate: localDate,
            opensAt: opensAt, revealsAt: revealsAt, scoresAt: scoresAt,
            cue: cue, previousCue: previousCue, previousRoundID: previousRoundID,
            phase: adopted
        )
    }

    /// **Private on purpose.** `docs/13` §2: *"There is exactly one place `RoundDTO.state` is
    /// assigned, and it is the decoder."* Keeping the memberwise initialiser unreachable is what
    /// makes that true of the type rather than of everybody's discipline — including in tests,
    /// which build rounds by decoding the contract's own JSON and therefore exercise the decoder
    /// they are relying on.
    private init(
        id: String, localDate: String,
        opensAt: Date, revealsAt: Date, scoresAt: Date,
        cue: CueDTO?, previousCue: CueDTO?, previousRoundID: String?,
        phase: Phase
    ) {
        self.id = id
        self.localDate = localDate
        self.opensAt = opensAt
        self.revealsAt = revealsAt
        self.scoresAt = scoresAt
        self.cue = cue
        self.previousCue = previousCue
        self.previousRoundID = previousRoundID
        self.phase = phase
    }

    enum CodingKeys: String, CodingKey {
        case id = "round_id"
        case localDate = "local_date"
        case state
        case opensAt = "opens_at"
        case revealsAt = "reveals_at"
        case scoresAt = "scores_at"
        case cue
        case previousCue = "previous_cue"
        case previousRoundID = "previous_round_id"
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
        // A base key, decoded before the phase switch alongside `id`/`localDate`/etc. — it is
        // present (or absent) identically on every phase, and `decodeIfPresent` reads a missing
        // key as `nil` with nothing to throw (`docs/18-CUES.md` §8).
        cue = try container.decodeIfPresent(CueDTO.self, forKey: .cue)
        // Absent on every payload but a dark-hours one, and read as `nil` there too when the
        // circle has no finished round behind it — same silent absence `cue` itself has.
        previousCue = try container.decodeIfPresent(CueDTO.self, forKey: .previousCue)
        // Same window, separate gate: the server sends this only when the night behind these
        // hours actually scored, so `nil` here covers a first night, a voided night, and every
        // phase that is not the dark hours at all.
        previousRoundID = try container.decodeIfPresent(String.self, forKey: .previousRoundID)

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
