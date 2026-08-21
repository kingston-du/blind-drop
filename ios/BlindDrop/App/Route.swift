import Foundation

/// The typed navigation path (`docs/13` §4, `docs/08` intro).
///
/// Four pushed destinations, and that is the whole list. The modal — Search — is deliberately
/// **not** here: `docs/08` §3 presents it as a sheet from Submit, with Confirm pushed inside
/// the sheet's own stack, so it never enters the root path. And there is **no tab bar**
/// (`docs/08` intro, `docs/13` §4 and §9).
///
/// Adding a case is a product change, not a refactor. `CaseIterable` is here so that
/// claim is a failing test rather than a comment nobody reads.
enum Route: Hashable, Sendable, CaseIterable {
    /// The Record — pushed, always reachable (`docs/08` §8).
    case record
    /// The active group roster — names only, with no participation state.
    case group
    /// Profile, account and legal settings.
    case settings
    /// Circle-scoped relationships from scored rounds only.
    case insights
}
