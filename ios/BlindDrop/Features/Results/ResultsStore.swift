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

    /// Card number → the caller's own mark, as it is **on screen** (`docs/19` §8.3).
    ///
    /// Optimistic: a tap moves this immediately and the write goes out behind it, because a tap
    /// that waited on a round trip would feel broken on a train. `serverMarks` is what the last
    /// payload said, and the difference between the two is what `reactions(for:)` adjusts the
    /// room's counts by — the server's counts include the caller's own mark, so a filled heart
    /// beside a number that did not move is a visible lie.
    private(set) var marks: [Int: ReactionKind] = [:]

    /// What the last loaded payload said the caller's marks were — the baseline the counts on
    /// that payload were computed with.
    private var serverMarks: [Int: ReactionKind] = [:]

    /// A failed mark write, as a copy key. Cleared by the next tap.
    ///
    /// Nothing draws it, and that is the same choice `RevealStore` made: the **revert** is the
    /// feedback — a mark that goes back to what the server has is a person seeing their tap not
    /// take — and a banner over the answers would be a second, louder statement of the same
    /// fact on a screen whose whole job is to be read. It is held because a store that silently
    /// swallows a failure is a store no test can ask about.
    private(set) var reactionErrorKey: String?

    /// One chained task per card, so two taps on one card cannot land out of order, and a
    /// generation per card so a finishing write can tell whether it is still the current one.
    /// The same apparatus `RevealStore` uses, and for the same two reasons.
    private var reactionWrites: [Int: Task<Void, Never>] = [:]
    private var reactionGeneration: [Int: Int] = [:]

    /// The circle this round belongs to, learned during `load()`.
    ///
    /// The write route is circle-scoped and resolves the round itself — *tonight's* round, by
    /// the circle's local date (`docs/19` §7, guard 2). There is deliberately no round id in it:
    /// a night reached through The Record has no write path at all, which is the structural half
    /// of "reactions close with the round" (`docs/19` §3).
    private var groupID: String?

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
        adoptMarks()
        if let groupID = await groupID {
            self.groupID = groupID
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

    // MARK: - Marks (E46-03, docs/19 §8.3)

    /// Takes the caller's own marks off a freshly loaded payload.
    ///
    /// **A card with a write in flight keeps what is on screen.** A refresh that landed between
    /// the tap and the response would otherwise put the server's older mark back over the one the
    /// person is looking at — the same window `RevealStore.adopt(reactions:)` guards, and the
    /// same answer.
    private func adoptMarks() {
        guard let cards = state.value?.cards else { return }
        serverMarks = cards.reduce(into: [:]) { $0[$1.cardNumber] = $1.myReaction }
        for card in cards where reactionWrites[card.cardNumber] == nil {
            marks[card.cardNumber] = card.myReaction
        }
    }

    /// The counts and the caller's own mark for one card, with any un-landed tap folded in.
    func reactions(for card: ResultCardDTO) -> ReactionCountsRow.Model {
        let mine = marks[card.cardNumber]
        return ReactionCountsRow.Model(
            counts: card.reactions.adjusted(from: serverMarks[card.cardNumber], to: mine),
            mine: mine
        )
    }

    /// Places, changes or clears the caller's mark on one card. `kind: nil` clears — the row
    /// passes it when the chosen mark is tapped again, so a second tap is the undo.
    ///
    /// **This is the only screen that can mark the caller's own card** (`docs/19` §4): the quick
    /// pass skips it, so there is nothing here that special-cases whose card it is. Nothing here
    /// consults whether the caller submitted either — a mark is scored by nothing, and the
    /// server has no submitter check on that route.
    func mark(_ kind: ReactionKind?, on cardNumber: Int) {
        guard cards.contains(where: { $0.cardNumber == cardNumber }) else { return }
        guard marks[cardNumber] != kind else { return }
        marks[cardNumber] = kind
        reactionErrorKey = nil
        announcement = Copy.A11y.reactionPlaced(cardNumber: cardNumber, kind: kind)
        sendMark(kind, on: cardNumber)
    }

    /// The last thing worth saying out loud, posted by the screen as an `.announcement` and then
    /// cleared (`docs/12` §2) — a mark is placed by a tap on a control that does not move, and
    /// nothing changes state in silence.
    private(set) var announcement: String?

    /// Named for `RevealStore.consumeAnnouncement()`, which does the same job for the same
    /// reason: the screen posts it and clears it, so the store stays free of UIKit and an
    /// announcement that stayed set cannot fire again on the next unrelated redraw.
    func consumeAnnouncement() { announcement = nil }

    private func sendMark(_ kind: ReactionKind?, on cardNumber: Int) {
        guard let groupID else { return }
        let previous = reactionWrites[cardNumber]
        let generation = (reactionGeneration[cardNumber] ?? 0) + 1
        reactionGeneration[cardNumber] = generation
        reactionWrites[cardNumber] = Task { [weak self] in
            // Chained, not cancelled: the earlier request may already have reached the server,
            // so letting it finish and then overwriting it is the only ordering that ends with
            // what the person last tapped.
            _ = await previous?.value
            guard let self else { return }
            let outcome = await self.result(
                of: .saveReaction(groupID, cardNumber: cardNumber, kind: kind)
            )
            switch outcome {
            case .success:
                self.finishMark(on: cardNumber, generation: generation)
            case let .failure(error):
                self.failMark(on: cardNumber, generation: generation, error: error)
            }
        }
    }

    /// A write landed. It releases the card and **changes nothing else**.
    ///
    /// The obvious-looking line here — *the server now holds this mark, so make it the
    /// baseline* — is wrong, and a simulator pass is what found it. `serverMarks` is not "what
    /// the server holds"; it is **the mark the loaded payload's counts were computed with**, and
    /// a write does not reload the payload. Moving it made `adjusted(from:to:)` a no-op a moment
    /// after the tap, so the count visibly snapped back to the stale number beside a mark that
    /// had stayed put: *Interesting* filled, and still saying 1. The baseline moves when a new
    /// payload arrives, in `adoptMarks()`, and nowhere else.
    ///
    /// Only the current write releases the card: two taps make two tasks, and the first
    /// finishing does not mean the second has been sent.
    private func finishMark(on cardNumber: Int, generation: Int) {
        guard reactionGeneration[cardNumber] == generation else { return }
        reactionWrites.removeValue(forKey: cardNumber)
    }

    /// A failed write puts the mark, **and the count with it**, back to what the server last
    /// confirmed. A mark that stayed lit after a failure would be a claim the person made and
    /// nobody recorded, and there is no later write to carry it — the next tap sends only its
    /// own card.
    private func failMark(on cardNumber: Int, generation: Int, error: APIError) {
        reactionErrorKey = error.copyKey
        // A superseded write's failure says nothing about the mark on screen: a later tap has
        // already replaced what it was trying to store.
        guard reactionGeneration[cardNumber] == generation else { return }
        marks[cardNumber] = serverMarks[cardNumber]
        reactionWrites.removeValue(forKey: cardNumber)
    }

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
            cue: state.value?.cue,
            namedCards: resolve?.namedCards,
            markedCards: resolve?.markedCards,
            barredCards: resolve?.barredCards,
            share: shareEntry,
            reactions: cards.reduce(into: [:]) { $0[$1.cardNumber] = reactions(for: $1) }
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
