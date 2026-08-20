import Foundation

/// `GET /groups` — the switcher's entire data source (`docs/04` §3, `E18-02`).
///
/// `myState` is the caller's own next action in that circle, never anyone else's, and
/// `needsAction` is the only priority signal the server states — ordering the rows into a
/// "needs attention first" list is `E19-02`'s job, not this type's.
enum CircleState: String, Decodable, Sendable, Equatable {
    case drop, sealed, guess, answers, voided
}

struct CircleSummaryDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let myState: CircleState
    let needsAction: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case myState = "my_state"
        case needsAction = "needs_action"
    }
}

/// The bare envelope `GET /groups` answers with — `{"circles": […]}`, oldest-active-first
/// (`docs/04` §3). An empty list is a valid answer, not an error.
struct CirclesDTO: Decodable, Sendable, Equatable {
    let circles: [CircleSummaryDTO]
}

/// The people an inviter already knows through active shared groups (`E20-02`). The server
/// owns the recency ordering and sends no group count, membership timestamp, or round activity.
struct KnownPersonDTO: Decodable, Sendable, Equatable, Identifiable {
    let userID: String
    let displayName: String

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

struct KnownPeopleDTO: Decodable, Sendable, Equatable {
    let people: [KnownPersonDTO]
}

/// A pending direct invitation. It is not a membership, so it deliberately carries only the
/// group name and inviter identity until the recipient accepts it.
struct InvitationDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let group: InvitationGroupDTO
    let invitedBy: MemberDTO

    enum CodingKeys: String, CodingKey {
        case id, group
        case invitedBy = "invited_by"
    }
}

struct InvitationGroupDTO: Decodable, Sendable, Equatable {
    let id: String
    let name: String
}

struct InvitationsDTO: Decodable, Sendable, Equatable {
    let invitations: [InvitationDTO]
}
