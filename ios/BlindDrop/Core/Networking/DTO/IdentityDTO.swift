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
    /// `"member"` or `"admin"` — present only on `GroupDTO.members` (`docs/04` §3, `E21-01`).
    /// Every other place this type is decoded (`name_pool`, a results card's `owner`, a Record
    /// entry) never sends this key, and an absent key decodes an `Optional` to `nil` for free —
    /// no custom `init(from:)` needed to keep those payloads exactly the shape `docs/04`
    /// documents for them.
    let role: String?

    init(userID: String, displayName: String, role: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.role = role
    }

    var id: String { userID }
    var isAdmin: Bool { role == "admin" }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case role
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
    /// How often this circle's rounds carry a cue — `0` off, `1` every night, `2` every other
    /// night, `3` now and then (`docs/18-CUES.md` §4). Always present from the server; the
    /// decoder defaults to `2` (the product default) so fixtures that predate the field keep
    /// decoding rather than throwing.
    let cueCadence: Int
    /// The local date from which the current cadence is in effect (`docs/18-CUES.md` §10).
    /// Read-only; only the PATCH response is acted on.
    let cueEffectiveFrom: String?
    /// The local date from which `revealHour` first applies, and `nil` — the ordinary answer —
    /// when the very next round ahead already uses it (`docs/04` §3).
    ///
    /// A change re-times every round that has not yet opened (`docs/02` §1, owner amendment
    /// 2026-09-09), so the only round that can still be on the old hour is one that is *open* —
    /// somebody may have sealed a song against its clock. Change the hour in the morning and
    /// this is `nil`, because tonight is already the new hour; change it in the evening and it
    /// is tomorrow.
    ///
    /// The server answers on **every** read rather than only in the reply to the change, which
    /// is what lets the settings screen keep saying it — a member who changed the hour, left the
    /// screen and came back used to see the new hour with nothing to say tonight was still
    /// running on the old one.
    let revealEffectiveFrom: String?
    /// The next round's cue, and whether it can still be changed (`docs/18-CUES.md` §11.6).
    ///
    /// `nil` for a member: the server sends the key to an admin only, because handing out the
    /// *coming* night's brief today is the thing §7 spends the dark hours avoiding. `nil` for an
    /// admin too when the circle has no round ahead of it yet.
    let nextCue: NextCueDTO?

    init(
        id: String, name: String, timezone: String, revealHour: Int,
        inviteCode: String, isAdmin: Bool, members: [MemberDTO],
        cueCadence: Int = 2, cueEffectiveFrom: String? = nil,
        revealEffectiveFrom: String? = nil, nextCue: NextCueDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.timezone = timezone
        self.revealHour = revealHour
        self.inviteCode = inviteCode
        self.isAdmin = isAdmin
        self.members = members
        self.cueCadence = cueCadence
        self.cueEffectiveFrom = cueEffectiveFrom
        self.revealEffectiveFrom = revealEffectiveFrom
        self.nextCue = nextCue
    }

    enum CodingKeys: String, CodingKey {
        case id, name, timezone, members
        case revealHour = "reveal_hour"
        case inviteCode = "invite_code"
        case isAdmin = "is_admin"
        case cueCadence = "cue_cadence"
        case cueEffectiveFrom = "cue_effective_from"
        case revealEffectiveFrom = "reveal_effective_from"
        case nextCue = "next_cue"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        timezone = try c.decode(String.self, forKey: .timezone)
        revealHour = try c.decode(Int.self, forKey: .revealHour)
        inviteCode = try c.decode(String.self, forKey: .inviteCode)
        isAdmin = try c.decode(Bool.self, forKey: .isAdmin)
        members = try c.decode([MemberDTO].self, forKey: .members)
        cueCadence = try c.decodeIfPresent(Int.self, forKey: .cueCadence) ?? 2
        cueEffectiveFrom = try c.decodeIfPresent(String.self, forKey: .cueEffectiveFrom)
        revealEffectiveFrom = try c.decodeIfPresent(String.self, forKey: .revealEffectiveFrom)
        nextCue = try c.decodeIfPresent(NextCueDTO.self, forKey: .nextCue)
    }
}

/// The one round an admin may still write a cue onto (`docs/18-CUES.md` §11.6).
///
/// Not "tomorrow's": between local midnight and `editableUntil` the next unopened round is
/// *today's*, so `localDate` is the only label that is always true, and it is what the settings
/// row shows.
struct NextCueDTO: Decodable, Sendable, Equatable {
    /// The round's group-local calendar date, `YYYY-MM-DD`. A string for the same reason
    /// `RoundDTO.localDate` is one — parsing it here would reinterpret it in the device's zone.
    let localDate: String
    /// `nil` when the cadence gives that night no cue. Writing one anyway is allowed.
    let text: String?
    /// True when an admin wrote this line rather than the derivation assigning it — the only
    /// case where there is anything to revert.
    let isCustom: Bool
    /// When the round opens and the cue stops being editable. The server enforces this; the
    /// client only renders it, because a round that has opened may already have been sealed
    /// against a brief somebody read.
    let editableUntil: Date

    init(localDate: String, text: String?, isCustom: Bool, editableUntil: Date) {
        self.localDate = localDate
        self.text = text
        self.isCustom = isCustom
        self.editableUntil = editableUntil
    }

    enum CodingKeys: String, CodingKey {
        case text
        case localDate = "local_date"
        case isCustom = "is_custom"
        case editableUntil = "editable_until"
    }
}


