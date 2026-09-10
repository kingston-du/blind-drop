import SwiftUI
import Testing
@testable import BlindDrop

/// `E21-01`. `GroupDetailView` takes plain values rather than a live `GroupStore`, so these
/// goldens exercise the same admin/member split a person actually sees without a network — the
/// same reasoning `CircleSwitcherSheet`'s own content function is built around.
@MainActor
@Suite struct GroupScreenSnapshotTests {

    @Test func rosterRolesDecodeFromTheGroupResponse() throws {
        let decoded = try group(isAdmin: true)
        #expect(decoded.members.first?.isAdmin == true)
        #expect(decoded.members.dropFirst().allSatisfy { !$0.isAdmin })
    }

    private func group(
        isAdmin: Bool, revealHour: Int = 20, memberCount: Int = 3, cueCadence: Int = 2,
        revealEffectiveFrom: String? = nil, nextCue: String? = nil
    ) throws -> GroupDTO {
        let allMembers = [
            ("u_ana", "Ana", "admin"),
            ("u_ben", "Ben", "member"),
            ("u_cal", "Cal", "member"),
        ]
        let members = allMembers.prefix(memberCount).map {
            #"{"user_id":"\#($0.0)","display_name":"\#($0.1)","role":"\#($0.2)"}"#
        }.joined(separator: ",")
        let json = """
        {
          "id": "g_1",
          "name": "The Cove",
          "timezone": "America/New_York",
          "reveal_hour": \(revealHour),
          "invite_code": "K7MQ2X",
          "is_admin": \(isAdmin),
          "cue_cadence": \(cueCadence),
          "reveal_effective_from": \(revealEffectiveFrom.map { #""\#($0)""# } ?? "null"),
          \(nextCue.map { #""next_cue":{"local_date":"2026-08-20","text":"\#($0)","is_custom":true,"editable_until":"2026-08-20T14:00:00Z"},"# } ?? "")
          "members": [\(members)]
        }
        """
        // `JSONDecoder.api`, not a bare one: `next_cue.editable_until` is a `Date`, and only
        // the app's own decoder carries the `.iso8601` strategy the wire format needs. A bare
        // decoder expects a Double there and throws before the view is ever built.
        return try JSONDecoder.api.decode(GroupDTO.self, from: Data(json.utf8))
    }

    /// The next round's cue, editable (`docs/18-CUES.md` §11.6, `E43`).
    ///
    /// `serverNow` is what decides editable-versus-locked — `CLAUDE.md` §2.2, so the row asks
    /// the server clock rather than `Date()`. Pinned an hour before the fixture's
    /// `editable_until` so this golden is the live state and cannot drift into the locked one
    /// as the wall clock moves.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func nextCueEditable(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(
            group: try group(isAdmin: true, nextCue: "A song you hate"),
            serverNow: Date(timeIntervalSince1970: 1_787_230_800),
            currentUserID: "u_ana",
            rendersForSnapshot: true
        )
        verify(named: "Group-admin-nextcue", device, size) { view }
    }

    /// The same row once the round has opened: no chevron, and a line saying why. The clock is
    /// past `editable_until`, which is the whole difference.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func nextCueLocked(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(
            group: try group(isAdmin: true, nextCue: "A song you hate"),
            serverNow: Date(timeIntervalSince1970: 1_787_238_000),
            currentUserID: "u_ana",
            rendersForSnapshot: true
        )
        verify(named: "Group-admin-nextcue-locked", device, size) { view }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func asAdmin(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(group: try group(isAdmin: true), currentUserID: "u_ana", rendersForSnapshot: true)
        verify(named: "Group-admin", device, size) { view }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func asMember(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(group: try group(isAdmin: false), currentUserID: "u_ben", rendersForSnapshot: true)
        verify(named: "Group-member", device, size) { view }
    }

    /// The reveal-hour section states precisely when a just-made change lands (`docs/03` §4)
    /// rather than leaving the question open.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func revealHourEffectiveDate(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(
            group: try group(isAdmin: true, revealHour: 19, revealEffectiveFrom: "2026-08-20"),
            currentUserID: "u_ana",
            rendersForSnapshot: true
        )
        verify(named: "Group-admin-revealhour-effective", device, size) { view }
    }

    /// The cue-cadence row states precisely when a just-made change lands (`docs/18-CUES.md` §10),
    /// the same "from tomorrow" honesty the reveal-hour section already states — a cadence change
    /// rewrites only rounds that have not yet opened.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func cueCadenceEffectiveDate(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(
            group: try group(isAdmin: true, cueCadence: 1),
            cueEffectiveFrom: "2026-08-20",
            currentUserID: "u_ana",
            rendersForSnapshot: true
        )
        verify(named: "Group-admin-cuecadence-effective", device, size) { view }
    }

    /// The last-admin refusal (`E21-01`'s open question) — unreachable through this app's own
    /// UI today, but the copy must still render plainly if the server ever sends it.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func lastAdminError(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(group: try group(isAdmin: true), errorKey: "error.lastadmin", currentUserID: "u_ana", rendersForSnapshot: true)
        verify(named: "Group-admin-lastadmin-error", device, size) { view }
    }

    /// One member, one row — the smallest roster a circle can have left in it, and the case most
    /// likely to make the leave button and the empty space around it look wrong.
    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func soleMember(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let view = GroupDetailView(group: try group(isAdmin: true, memberCount: 1), currentUserID: "u_ana", rendersForSnapshot: true)
        verify(named: "Group-admin-sole-member", device, size) { view }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(
            of: content(),
            device: device,
            typeSize: size
        )
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Group",
            sourceLocation: sourceLocation
        )
    }
}
