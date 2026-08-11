import Foundation

/// The caller's own guess on one card, once the answers are out.
struct MyGuessDTO: Decodable, Sendable, Equatable {
    let guessedUserID: String
    let displayName: String
    let isCorrect: Bool

    enum CodingKeys: String, CodingKey {
        case guessedUserID = "guessed_user_id"
        case displayName = "display_name"
        case isCorrect = "is_correct"
    }
}

/// One card, resolved: the song, whose it was, and how the room did on it (`docs/04` §4).
///
/// `eligibleGuesserCount` is `S − 1` on **every** card — every other submitter, whether or not
/// they opened the sheet (`docs/02` §4.1). A denominator that shrank to the people who tried
/// would quietly turn readability into a measure of enthusiasm.
struct ResultCardDTO: Decodable, Sendable, Equatable, Identifiable {
    let cardNumber: Int
    let track: TrackDTO
    let owner: MemberDTO
    let correctGuessCount: Int
    let eligibleGuesserCount: Int
    /// `nil` when the caller did not guess this card, or could not guess at all.
    let myGuess: MyGuessDTO?

    var id: Int { cardNumber }

    enum CodingKeys: String, CodingKey {
        case cardNumber = "card_no"
        case track, owner
        case correctGuessCount = "correct_guess_count"
        case eligibleGuesserCount = "eligible_guesser_count"
        case myGuess = "my_guess"
    }
}

/// The caller's own two numbers, each with the fraction behind it.
///
/// **`nil` means *not applicable*, never *zero*** (`docs/04` §4). A `nil` ear renders as "—"
/// above "You sat this one out"; a `0` would render as "0%" above "0 of 7 correct". One of
/// those is a statement about a night somebody spent elsewhere and the other is a judgement
/// this product refuses to make — which is why the counts beside a rate go `nil` with it.
struct PersonalScoreDTO: Decodable, Sendable, Equatable {
    /// `nil` if the caller did not submit — no card of theirs was in the room.
    let readability: Double?
    let readabilityCorrect: Int?
    let readabilityPossible: Int?
    /// `nil` if the caller assigned nothing. Never guessing is not the same as guessing badly.
    let ear: Double?
    let earCorrect: Int?
    let earPossible: Int?

    enum CodingKeys: String, CodingKey {
        case readability
        case readabilityCorrect = "readability_correct"
        case readabilityPossible = "readability_possible"
        case ear
        case earCorrect = "ear_correct"
        case earPossible = "ear_possible"
    }
}

/// One submitter's two rates, for the room-at-a-glance list.
struct PersonScoreDTO: Decodable, Sendable, Equatable, Identifiable {
    let userID: String
    let displayName: String
    let readability: Double?
    let ear: Double?

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case readability, ear
    }
}

/// `GET /rounds/{round_id}/results` — `docs/04` §4. Available for any past round, which is how
/// The Record links back into a night from three weeks ago.
///
/// Rates are decimals in `0…1` and the client formats them. No percentage arrives
/// pre-rendered, because a formatted string is a decision made in the wrong place.
struct ResultsDTO: Decodable, Sendable, Equatable {
    let roundID: String
    let localDate: String
    let submitterCount: Int
    let cards: [ResultCardDTO]
    let me: PersonalScoreDTO
    let people: [PersonScoreDTO]

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case localDate = "local_date"
        case submitterCount = "submitter_count"
        case cards, me, people
    }
}

/// How legible somebody is, in words (`docs/02` §4.5).
enum ReadabilityBand: String, Decodable, Sendable, Equatable {
    case openBook = "open_book"
    case legible
    case mixedSignals = "mixed_signals"
    case hardToPlace = "hard_to_place"
    case unreadable
}

/// A row of Best Ear. Ranked, ties sharing a rank and the next rank skipping (`docs/04` §4).
struct EarStandingDTO: Decodable, Sendable, Equatable, Identifiable {
    let rank: Int
    let userID: String
    let displayName: String
    let earAllTime: Double
    let earCorrectTotal: Int

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case rank
        case userID = "user_id"
        case displayName = "display_name"
        case earAllTime = "ear_all_time"
        case earCorrectTotal = "ear_correct_total"
    }
}

/// A row of the readability list, which **has no `rank` and must never gain one**.
///
/// `docs/02` §4.5 makes that a product rule rather than a presentation preference: guessing
/// well is a scoreboard, being hard to read is a trait, and low readability is its own kind of
/// win. The server does not send a rank; this type has nowhere to put one if it did, which is
/// the client-side half of the same rule.
struct ReadabilityStandingDTO: Decodable, Sendable, Equatable, Identifiable {
    let userID: String
    let displayName: String
    let readabilityAllTime: Double
    let band: ReadabilityBand

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case readabilityAllTime = "readability_all_time"
        case band
    }
}

/// `GET /groups/current/standings` — two lists that deliberately do not have the same shape.
struct StandingsDTO: Decodable, Sendable, Equatable {
    let roundsPlayed: Int
    let bestEar: [EarStandingDTO]
    let readability: [ReadabilityStandingDTO]

    enum CodingKeys: String, CodingKey {
        case roundsPlayed = "rounds_played"
        case bestEar = "best_ear"
        case readability
    }
}
