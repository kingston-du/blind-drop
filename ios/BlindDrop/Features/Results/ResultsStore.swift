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

    /// The group's all-time lists (`docs/08` §7.3). Its own `LoadState` rather than a field on
    /// the round's, because the two are different routes with different lifetimes: the answers
    /// are one night and never change again, the standings are the whole group and move every
    /// night. A failure in one must not blank the other.
    private(set) var standings: LoadState<StandingsDTO> = .idle

    /// The round these answers belong to. Also the key the once-per-round name-resolve is
    /// remembered under (`docs/09` §4).
    let roundID: String

    /// The group's name and timezone, once loaded — everything the share card needs that is not
    /// already on `ResultsDTO`. Best-effort: a failure here just means no share card, the same
    /// silent degradation `RoundContext.calendar` never has to consider because it is loaded
    /// already. Not surfaced as its own `LoadState` for the same reason — nothing on screen
    /// reads this except `shareEntry`, so there is nothing for a spinner or an error banner to
    /// show about it.
    private(set) var group: GroupDTO?

    private let api: APIClient
    /// Only `standings` needs a circle — `results(roundID:)` resolves its own group server-side
    /// (`docs/04` §4) — but both loads start together, so a circle that cannot be resolved must
    /// not hold up the answers (`E19-01`).
    private let circles: CircleStore
    /// Built once, in `init`, and kept for the life of this store — the same one visit's worth
    /// of temporary files `ResultsHost`'s own `renderer` used to be (`docs/10` §5). This store is
    /// itself `@State`-scoped to one visit at every call site, so it is the right thing to own
    /// the renderer now that both `RoundScreen` and `RecordScreen`'s history path need one.
    private let renderer: ShareRenderer

    init(api: APIClient, roundID: String, circles: CircleStore, artworkLoader: any ArtworkLoading = ArtworkLoader()) {
        self.api = api
        self.roundID = roundID
        self.circles = circles
        self.renderer = ShareRenderer(loader: artworkLoader)
    }

    /// Loads the answers.
    ///
    /// A failed refresh keeps what is on screen (`LoadState.apply` → `.stale`), which matters
    /// more here than on most screens: results do not change after they land, so yesterday's
    /// render of *this* round is not stale in any sense the user cares about, and blanking it
    /// because a foreground refetch timed out would be the app throwing away a correct screen.
    /// All three routes concurrently, because they are independent GETs and the screen needs all
    /// of them: three serial round trips at ten at night on cellular is a spinner nobody asked
    /// for.
    func load() async {
        if state.value == nil { state = .loading }
        if standings.value == nil { standings = .loading }

        async let answers = result(of: .results(roundID: roundID))
        async let groupID = circles.resolveActiveID()

        state.apply(await answers)
        if let groupID = await groupID {
            async let standingsResult = result(of: Endpoint<StandingsDTO>.standings(groupID))
            async let groupResult = result(of: Endpoint<GroupDTO>.group(groupID))
            standings.apply(await standingsResult)
            // Best-effort, same as `RecordStore.load()`: a failed fetch here just leaves `group`
            // as it was, which means no share card rather than a screen that failed to load.
            if case let .success(value) = await groupResult { group = value }
        } else {
            standings.apply(.failure(circles.state.error ?? .unreadable))
        }
    }

    /// Deletes any share-card files this visit's renderer wrote (`docs/10` §5: *"the temporary
    /// file is deleted after the share sheet dismisses"* — and, same section, on leaving the
    /// results whether or not a share sheet ever opened). Call from the host's `.onDisappear`.
    func discardShareRender() {
        renderer.discard()
    }

    /// `APIClient.send` throws `APIError` and nothing else — a typed `throws`, so there is no
    /// second `catch` here for an error that cannot arrive.
    private func result<R: Decodable & Sendable>(of endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do {
            return .success(try await api.send(endpoint))
        } catch {
            return .failure(error)
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
            standings: standings.value,
            tonightTopEar: state.value?.tonightTopEar ?? [],
            namedCards: resolve?.namedCards,
            markedCards: resolve?.markedCards,
            barredCards: resolve?.barredCards,
            share: shareEntry
        )
    }

    /// The share card's ingredients, once the answers and the group have both landed.
    ///
    /// `nil` until then, which is also what makes the button appear with the content rather than
    /// ahead of it — there is no moment where **Share tonight** offers a card of nothing. And
    /// `nil` for good on a round that never scores, per `docs/10` §5: *"nothing about a round
    /// that is not `scored` is ever renderable"* — a `ResultsStore` only ever exists because the
    /// server already said `scored`, so that rule is a property of when this type exists at all.
    private var shareEntry: ShareEntry? {
        guard let results = state.value,
              let group,
              let date = GroupCalendar(timezone: group.timezone).shareDate(localDate: results.localDate)
        else { return nil }

        return ShareEntry(
            content: ShareCardContent(results: results, groupName: group.name, date: date),
            renderer: renderer
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
