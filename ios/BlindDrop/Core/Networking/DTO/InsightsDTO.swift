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

/// `GET /groups/{group_id}/insights`. Every value is circle-scoped and derived only from scored
/// rounds; empty values mean the circle has not yet produced that kind of relationship.
struct InsightsDTO: Decodable, Sendable, Equatable {
    let youKnowBest: InsightReadDTO?
    let knowsYouBest: InsightReadDTO?
    let hardestToRead: InsightReadDTO?
    let mutualRecognition: [InsightPairDTO]
    let mutualMisses: [InsightPairDTO]

    enum CodingKeys: String, CodingKey {
        case youKnowBest = "you_know_best"
        case knowsYouBest = "knows_you_best"
        case hardestToRead = "hardest_to_read"
        case mutualRecognition = "mutual_recognition"
        case mutualMisses = "mutual_misses"
    }
}
