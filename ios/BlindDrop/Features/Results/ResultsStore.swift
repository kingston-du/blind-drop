import Foundation

/// Owns the night's answers (`docs/13` §2).
///
/// A second store rather than a branch of `RoundStore`, because the results are a **second
/// route**: `GET /rounds/current` returns a `scored` round carrying the base keys and nothing
/// else, and `GET /rounds/{id}/results` returns the answers. `docs/04` §4 splits them on purpose
/// — it keeps the launch call small, it lets a push deep-link straight into a night, and it is
/// what makes the same screen reachable from The Record for a round three weeks old (`E13-01`).
/// The round id is therefore a parameter, not something read off "today".
///
/// It holds no opinion about the phase. A results screen only ever exists because the server
/// said `scored`, and asking for the results of a round that is not would earn a `WRONG_PHASE`
/// the screen renders like any other error (`CLAUDE.md` §2.2).
@Observable @MainActor
final class ResultsStore {

    private(set) var state: LoadState<ResultsDTO> = .idle

    /// The round these answers belong to. Also the key the once-per-round name-resolve is
    /// remembered under (`docs/09` §4).
    let roundID: String

    private let api: APIClient

    init(api: APIClient, roundID: String) {
        self.api = api
        self.roundID = roundID
    }

    /// Loads the answers.
    ///
    /// A failed refresh keeps what is on screen (`LoadState.apply` → `.stale`), which matters
    /// more here than on most screens: results do not change after they land, so yesterday's
    /// render of *this* round is not stale in any sense the user cares about, and blanking it
    /// because a foreground refetch timed out would be the app throwing away a correct screen.
    func load() async {
        if state.value == nil { state = .loading }
        // `APIClient.send` throws `APIError` and nothing else — a typed `throws`, so there is
        // no second `catch` here for an error that cannot arrive.
        do {
            state.apply(.success(try await api.send(.results(roundID: roundID))))
        } catch {
            state.apply(.failure(error))
        }
    }

    /// The cards, in the server's order — which is `card_no`, the shuffle the whole group sees
    /// (`E03-04`). Not re-sorted here for the same reason `RevealScreen` does not re-sort: the
    /// numbering is the game's spine and the client does not hold a second opinion about it.
    var cards: [ResultCardDTO] { state.value?.cards ?? [] }

    /// What `ResultsScreen` draws, with the arrival the animation has reached folded in.
    ///
    /// - Parameter resolve: `nil` before the sequence has been armed — which is every runloop
    ///   between the screen appearing and the answers landing. A settled state is the right
    ///   answer there: with no cards yet there is nothing to hold back.
    func viewState(resolve: ResolveAnimation?) -> ResultsViewState {
        ResultsViewState(
            cards: cards,
            me: state.value?.me,
            namedCards: resolve?.namedCards,
            markedCards: resolve?.markedCards
        )
    }
}

extension ResultCardDTO {
    /// What `FlightCard` draws once the answers are out.
    ///
    /// The mapping is here rather than in the view so that the one judgement in it — a `nil`
    /// `my_guess` means *there is no mark*, whether the caller owned the card, left it blank, or
    /// could not guess at all — is made once, in a file a test can reach, instead of inside a
    /// `switch` in a `ForEach`.
    var resolution: CardResolution {
        CardResolution(
            owner: owner.displayName,
            correctCount: correctGuessCount,
            eligibleCount: eligibleGuesserCount,
            myGuess: myGuess.map {
                CardResolution.MyGuess(name: $0.displayName, isCorrect: $0.isCorrect)
            }
        )
    }
}
