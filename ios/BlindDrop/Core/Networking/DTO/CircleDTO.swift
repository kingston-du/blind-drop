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
