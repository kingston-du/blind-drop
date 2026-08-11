import Testing

/// Snapshot testing is hand-rolled against golden PNGs in `__Snapshots__/` — no third-party
/// snapshot library, because the app has zero dependencies (docs/13 §1, docs/15 §3).
/// The harness itself is E08-07.
@Suite struct SnapshotHarness {
    @Test func harnessTargetBuilds() {
        #expect(Bool(true))
    }
}
