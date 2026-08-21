import SwiftUI
import Testing
@testable import BlindDrop

private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E24-01`. The circle's roster, ranked by all-time Ear — `GroupDetailView` is the value both the
/// live `GroupScreen` and these goldens draw, so a golden is a picture of exactly what the store
/// would have produced (`RecordSnapshotTests` makes the same split for its own store-backed
/// screen).
///
/// Three cases, because they are the three ways this layout can fail: a circle too new to rank
/// (thin history, honest rather than rounded), a small circle ranked normally, and a twelve-member
/// circle carrying a tied rank — the case `docs/12` §8 names explicitly for "nothing truncates
/// and nothing overlaps".
@MainActor
@Suite struct GroupSnapshotTests {

    @Test(arguments: devices, sizes)
    func threeMembersThinHistory(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Group-three-thin", device, size) {
            GroupFixture.content(group: GroupFixture.threeMembers, standings: GroupFixture.thin)
        }
    }

    @Test(arguments: devices, sizes)
    func threeMembersRanked(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Group-three-ranked", device, size) {
            GroupFixture.content(group: GroupFixture.threeMembers, standings: GroupFixture.threeRanked)
        }
    }

    /// Twelve members and a tied rank — the case that would renumber if a row ever enumerated
    /// its own index instead of printing `rank` (`StandingsTests.aTieSharesARankAndTheNextRankSkips`
    /// is the same rule, asserted on the type; this is the same rule, drawn).
    @Test(arguments: devices, sizes)
    func twelveMembersWithATie(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        // At 3×, the wide accessibility-five case is over ImageIO's simulator PNG limit. The
        // fixed raster cap preserves its layout at a representable scale.
        verify(named: "Group-twelve-tied", device, size, maximumPixelCount: 7_000_000) {
            GroupFixture.content(group: GroupFixture.twelveMembers, standings: GroupFixture.twelveRanked)
        }
    }

    /// A non-admin sees no admin section at all — the leaderboard is the whole screen.
    @Test(arguments: devices, sizes)
    func nonAdminHasNoAdminSection(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Group-non-admin", device, size) {
            GroupFixture.content(
                group: GroupFixture.threeMembers(isAdmin: false), standings: GroupFixture.threeRanked
            )
        }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        maximumPixelCount: Int? = nil,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(
            of: content(), device: device, typeSize: size, maximumPixelCount: maximumPixelCount
        )
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Group",
            sourceLocation: sourceLocation
        )
    }
}

@MainActor
enum GroupFixture {

    static func content(group: GroupDTO, standings: StandingsDTO) -> some View {
        let isThinHistory = standings.roundsPlayed < GroupStore.thinHistoryThreshold
        let rankedIDs = Set(standings.bestEar.map(\.userID))
        return GroupDetailView(
            group: group,
            bestEar: standings.bestEar,
            readabilityByUserID: Dictionary(
                uniqueKeysWithValues: standings.readability.map { ($0.userID, $0) }
            ),
            unrankedMembers: isThinHistory
                ? group.members
                : group.members.filter { !rankedIDs.contains($0.userID) },
            isThinHistory: isThinHistory,
            currentUserID: "u_ana",
            select: { _ in },
            rendersForSnapshot: true
        )
    }

    // MARK: - Groups

    static let threeMembers = threeMembers(isAdmin: true)

    static func threeMembers(isAdmin: Bool) -> GroupDTO {
        decode(GroupDTO.self, """
        {"id":"g_three","name":"Late Night Radio","timezone":"America/New_York",
         "reveal_hour":20,"invite_code":"AB12CD","is_admin":\(isAdmin),
         "members":[
           {"user_id":"u_ana","display_name":"Ana","role":"admin"},
           {"user_id":"u_ben","display_name":"Ben","role":"member"},
           {"user_id":"u_cal","display_name":"Cal","role":"member"}]}
        """)
    }

    static let twelveMembers: GroupDTO = {
        let names = ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jaz", "Kit", "Lux"]
        let members = names.enumerated().map { index, name in
            #"{"user_id":"u_\#(index)","display_name":"\#(name)","role":"\#(index == 0 ? "admin" : "member")"}"#
        }.joined(separator: ",")
        return decode(GroupDTO.self, """
        {"id":"g_twelve","name":"Sunday Crew","timezone":"America/New_York",
         "reveal_hour":20,"invite_code":"XY99ZZ","is_admin":true,
         "members":[\(members)]}
        """)
    }()

    // MARK: - Standings

    /// Three rounds — below `GroupStore.thinHistoryThreshold` — so the leaderboard shows the
    /// honest state instead of a ranked percentage.
    static let thin = decode(StandingsDTO.self, """
    {"rounds_played":3,
     "best_ear":[
       {"rank":1,"user_id":"u_ana","display_name":"Ana","ear_all_time":0.67,"ear_correct_total":2}],
     "readability":[]}
    """)

    static let threeRanked = decode(StandingsDTO.self, """
    {"rounds_played":10,
     "best_ear":[
       {"rank":1,"user_id":"u_cal","display_name":"Cal","ear_all_time":0.79,"ear_correct_total":19},
       {"rank":2,"user_id":"u_ana","display_name":"Ana","ear_all_time":0.55,"ear_correct_total":13},
       {"rank":3,"user_id":"u_ben","display_name":"Ben","ear_all_time":0.30,"ear_correct_total":7}],
     "readability":[
       {"user_id":"u_ana","display_name":"Ana","readability_all_time":0.83,"band":"open_book"},
       {"user_id":"u_ben","display_name":"Ben","readability_all_time":0.41,"band":"mixed_signals"},
       {"user_id":"u_cal","display_name":"Cal","readability_all_time":0.12,"band":"unreadable"}]}
    """)

    /// Twelve members, fourteen rounds, and a tie at second place — the two people on `0.68`
    /// share rank 2 and nobody is rank 3, the same shape `StandingsTests` pins at the DTO level.
    /// Its deliberately empty readability list makes every rendered standing row exercise the
    /// unavailable *"Read —"* form.
    static let twelveRanked: StandingsDTO = {
        // Sorted descending by rate before ranking — competition ranking (ties share a rank,
        // the next rank skips) only means what it says when it is computed over an order that
        // is already the order the numbers describe.
        let bestEar = [
            ("u_2", "Cal", 0.79, 77), ("u_0", "Ana", 0.68, 67), ("u_7", "Hal", 0.68, 67),
            ("u_8", "Ivy", 0.61, 60), ("u_5", "Fay", 0.55, 54), ("u_9", "Jaz", 0.52, 51),
            ("u_10", "Kit", 0.47, 46), ("u_1", "Ben", 0.44, 43), ("u_3", "Dee", 0.31, 30),
            ("u_11", "Lux", 0.22, 21), ("u_6", "Gus", 0.18, 18),
        ]
        var rank = 0
        var lastRate: Double?
        let rows = bestEar.enumerated().map { index, entry -> String in
            let (id, name, rate, correct) = entry
            if rate != lastRate { rank = index + 1 }
            lastRate = rate
            return #"{"rank":\#(rank),"user_id":"\#(id)","display_name":"\#(name)","ear_all_time":\#(rate),"ear_correct_total":\#(correct)}"#
        }.joined(separator: ",")
        return decode(StandingsDTO.self, #"{"rounds_played":14,"best_ear":[\#(rows)],"readability":[]}"#)
    }()

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        try! JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }
}
