import Foundation

/// What a screen knows about the thing it is showing (`docs/13` §5 rule 3, §7).
///
/// `stale` is the case that has to exist. The app keeps nothing on disk (`docs/13` §7: a local
/// cache of game state is a correctness hazard, not a feature), so the only cache is the value
/// a screen is already holding — and when a foreground refetch fails, that value is still the
/// most honest thing on the phone. Without this case a screen has two bad options: throw away
/// a good render because a refresh failed, or show it as if nothing happened.
///
/// The copy is `docs/11` `error.offline.stale` — *"Showing what we had. This may be out of
/// date."* — and it is shown **with** the data, never instead of it.
enum LoadState<Value: Sendable>: Sendable {
    /// Nothing has been asked for yet.
    case idle
    /// The first load is in flight. There is nothing to show, and the screen says so with a
    /// placeholder rather than a guess (`docs/13` §5 rule 3).
    case loading
    case loaded(Value)
    /// Failed with nothing to fall back on.
    case failed(APIError)
    /// A refresh failed, and this is what we had.
    case stale(Value, APIError)

    /// The value, from either case that has one.
    var value: Value? {
        switch self {
        case let .loaded(value), let .stale(value, _): value
        case .idle, .loading, .failed: nil
        }
    }

    /// The error, from either case that has one.
    var error: APIError? {
        switch self {
        case let .failed(error), let .stale(_, error): error
        case .idle, .loading, .loaded: nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    /// Applies a fresh result, keeping what is already on screen when the refresh fails.
    ///
    /// This is the one place the `stale` transition is written. A screen calling it cannot
    /// forget the case, which is the point of putting it here rather than in each store.
    mutating func apply(_ result: Result<Value, APIError>) {
        switch result {
        case let .success(value):
            self = .loaded(value)
        case let .failure(error):
            self = value.map { .stale($0, error) } ?? .failed(error)
        }
    }
}

extension LoadState: Equatable where Value: Equatable {}
