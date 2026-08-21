import Foundation

/// One person's scored reads of another active member in the current circle.
///
/// `lowerBound`/`upperBound` are the server's Wilson score interval on `correct/possible` at
/// 95% confidence (`E28-07`) — carried alongside the raw counts so the same array can be sorted
/// two different ways client-side: by `lowerBound` for "best" (a well-supported 8-of-12 always
/// outranks a thin 3-of-4), by `upperBound`, ascending, for "hardest" (the most generous bound a
/// thin sample can support, so one unlucky round does not credibly top that list).
struct InsightReadDTO: Decodable, Sendable, Equatable, Hashable, Identifiable {
    let member: MemberDTO
    let correct: Int
    let possible: Int
    let lowerBound: Double
    let upperBound: Double

    var id: String { member.userID }
    var rate: Double { Double(correct) / Double(possible) }

    enum CodingKeys: String, CodingKey {
        case member, correct, possible
        case lowerBound = "lower_bound"
        case upperBound = "upper_bound"
    }
}

/// A mutual relationship. `possible` includes both directions, so it is twice their shared rounds.
struct InsightPairDTO: Decodable, Sendable, Equatable, Identifiable {
    let members: [MemberDTO]
    let correct: Int
    let possible: Int

    var id: String { members.map(\.userID).joined(separator: ":") }
    var rate: Double { Double(correct) / Double(possible) }
}

/// A repeated wrong attribution in a scored circle round. Correct duplicate-track guesses are
/// intentionally absent: they are correct reads under docs/02 §4.3, not confusion.
struct InsightConfusionPairDTO: Decodable, Sendable, Equatable, Identifiable {
    let actualMember: MemberDTO
    let mistakenForMember: MemberDTO
    let count: Int

    var id: String { "\(actualMember.userID):\(mistakenForMember.userID)" }

    enum CodingKeys: String, CodingKey {
        case actualMember = "actual_member"
        case mistakenForMember = "mistaken_for_member"
        case count
    }
}

/// A history-gated lens over the circle's wrong guesses. Pairs used to be empty below the
/// stated threshold; the counts stay on the wire either way.
struct InsightConfusionDTO: Decodable, Sendable, Equatable {
    let scoredRounds: Int
    let minimumRounds: Int
    let pairs: [InsightConfusionPairDTO]

    // Restore before public beta (`E28-06`/`E28-07`, amendment A1): `scoredRounds >=
    // minimumRounds`. The server stopped gating `pairs` behind this at the same time, so pinning
    // it to `true` here keeps the two in agreement — showing the minimum-history sentence over a
    // list the server already sent would be a worse bug than showing the gate too early.
    var hasEnoughHistory: Bool { true }

    enum CodingKeys: String, CodingKey {
        case scoredRounds = "scored_rounds"
        case minimumRounds = "minimum_rounds"
        case pairs
    }
}

/// `GET /groups/{group_id}/insights`. Every value is circle-scoped and derived only from scored
/// rounds; empty values mean the circle has not yet produced that kind of relationship.
///
/// **`E28-07` replaced three server-picked bests with two full, ranked arrays.** `yourReads` is
/// the caller's read of every co-scored member, sorted by the server on `lowerBound`, descending
/// — `you read best` is `yourReads.first`, and the same array sorted here on `upperBound`,
/// ascending, is `hardest to read` and its own leaderboard (`hardestToReadRanked`). `readsYou` is
/// the mirror: every co-scored member's read of the caller, and `reads you best` is its first
/// element.
struct InsightsDTO: Decodable, Sendable, Equatable {
    let yourReads: [InsightReadDTO]
    let readsYou: [InsightReadDTO]
    let mutualRecognition: [InsightPairDTO]
    let mutualMisses: [InsightPairDTO]
    let confusion: InsightConfusionDTO

    enum CodingKeys: String, CodingKey {
        case yourReads = "your_reads"
        case readsYou = "reads_you"
        case mutualRecognition = "mutual_recognition"
        case mutualMisses = "mutual_misses"
        case confusion
    }

    var youKnowBest: InsightReadDTO? { yourReads.first }
    var knowsYouBest: InsightReadDTO? { readsYou.first }
    /// Ascending on the upper bound — the most generous rate the sample can support, lowest
    /// first — re-sorting the very array `youKnowBest` came from rather than a second fetch.
    var hardestToReadRanked: [InsightReadDTO] { yourReads.sorted { $0.upperBound < $1.upperBound } }
    var hardestToRead: InsightReadDTO? { hardestToReadRanked.first }
}
