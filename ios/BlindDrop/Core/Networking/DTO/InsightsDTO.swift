import Foundation

/// One person's scored reads of another active member in the current circle.
struct InsightReadDTO: Decodable, Sendable, Equatable, Identifiable {
    let member: MemberDTO
    let correct: Int
    let possible: Int

    var id: String { member.userID }
    var rate: Double { Double(correct) / Double(possible) }
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

/// A history-gated lens over the circle's wrong guesses. Pairs are empty below the stated
/// threshold, while the counts let the UI plainly describe the remaining history needed.
struct InsightConfusionDTO: Decodable, Sendable, Equatable {
    let scoredRounds: Int
    let minimumRounds: Int
    let pairs: [InsightConfusionPairDTO]

    var hasEnoughHistory: Bool { scoredRounds >= minimumRounds }

    enum CodingKeys: String, CodingKey {
        case scoredRounds = "scored_rounds"
        case minimumRounds = "minimum_rounds"
        case pairs
    }
}

/// `GET /groups/{group_id}/insights`. Every value is circle-scoped and derived only from scored
/// rounds; empty values mean the circle has not yet produced that kind of relationship.
struct InsightsDTO: Decodable, Sendable, Equatable {
    let youKnowBest: InsightReadDTO?
    let knowsYouBest: InsightReadDTO?
    let hardestToRead: InsightReadDTO?
    let mutualRecognition: [InsightPairDTO]
    let mutualMisses: [InsightPairDTO]
    let confusion: InsightConfusionDTO

    enum CodingKeys: String, CodingKey {
        case youKnowBest = "you_know_best"
        case knowsYouBest = "knows_you_best"
        case hardestToRead = "hardest_to_read"
        case mutualRecognition = "mutual_recognition"
        case mutualMisses = "mutual_misses"
        case confusion
    }
}
