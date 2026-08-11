import Foundation

/// `GET /me` — `docs/04` §2.
///
/// `hasGroup` is the server's answer to "where does this person go next", and the client does
/// not compute it: `docs/13` §4 routes on what the server said, and a client that inferred a
/// group from a cached round would show the wrong screen to somebody who had just left one.
struct UserDTO: Decodable, Sendable, Equatable {
    let userID: String
    let displayName: String
    let hasGroup: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case hasGroup = "has_group"
    }
}

/// Somebody in the group, or in a round's name pool: who they are, and deliberately nothing
/// about what they have done.
///
/// **There is no `joined_at` here and there must never be one.** During `open`, a `joined_at`
/// that changed today next to a name missing from tonight's pool is an inference channel
/// (`docs/14` §3) — which is why the server does not send it and why this type has no place to
/// put it if it did.
struct MemberDTO: Decodable, Sendable, Equatable, Identifiable, Hashable {
    let userID: String
    let displayName: String

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

/// `GET /groups/current`, and the response to creating or joining one (`docs/04` §3).
///
/// `timezone` is the group's, and every date and hour the app prints is formatted in it —
/// never `TimeZone.current` (`docs/13` §5 rule 6). A member on a plane still plays on the
/// group's clock.
struct GroupDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let timezone: String
    let revealHour: Int
    let inviteCode: String
    let isAdmin: Bool
    let members: [MemberDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, timezone, members
        case revealHour = "reveal_hour"
        case inviteCode = "invite_code"
        case isAdmin = "is_admin"
    }
}

/// `PATCH /groups/current` — the group's keys, plus the day a changed reveal hour starts
/// applying (`docs/04` §3). The group is flattened into the payload rather than nested, so it
/// is decoded that way here too.
///
/// `effectiveFrom` is `nil` when the hour did not change. It exists because a reveal hour
/// never re-times a round that is already on the books (`docs/03` §4), so the honest answer to
/// "when does this take effect" is a date, and the UI states it.
struct GroupPatchDTO: Decodable, Sendable, Equatable {
    let group: GroupDTO
    let effectiveFrom: String?

    init(from decoder: any Decoder) throws {
        group = try GroupDTO(from: decoder)
        effectiveFrom = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent(String.self, forKey: .effectiveFrom)
    }

    enum CodingKeys: String, CodingKey {
        case effectiveFrom = "effective_from"
    }
}
