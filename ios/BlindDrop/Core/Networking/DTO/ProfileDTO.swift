import Foundation

/// A profile is a view of one active member inside one circle. Every rate carries the number of
/// scored rounds behind it, so presentation can withhold a confident percentage for thin history.
struct ProfileRateDTO: Decodable, Sendable, Equatable {
    let value: Double?
    let samples: Int
}

struct PairwiseReadDTO: Decodable, Sendable, Equatable {
    let correct: Int
    let possible: Int

    var rate: Double? {
        guard possible > 0 else { return nil }
        return Double(correct) / Double(possible)
    }
}

struct ProfileTrackDTO: Decodable, Sendable, Equatable, Identifiable {
    let localDate: String
    let track: TrackDTO

    var id: String { "\(localDate)-\(track.trackKey)" }

    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case track
    }
}

/// `GET /groups/{group_id}/members/{user_id}/profile`.
/// The server has already excluded open, revealed and voided rounds from every field.
struct MemberProfileDTO: Decodable, Sendable, Equatable {
    let member: MemberDTO
    let ear: ProfileRateDTO
    let readability: ProfileRateDTO
    let dropCount: Int
    let recentTracks: [ProfileTrackDTO]
    let youReadThem: PairwiseReadDTO?
    let theyReadYou: PairwiseReadDTO?

    enum CodingKeys: String, CodingKey {
        case member, ear, readability
        case dropCount = "drop_count"
        case recentTracks = "recent_tracks"
        case youReadThem = "you_read_them"
        case theyReadYou = "they_read_you"
    }
}
