import SwiftUI

/// The open round, before the caller has dropped anything: **the search screen itself**.
///
/// There is no lobby in front of it. A screen whose only content is a headline and a button
/// that opens the real screen is a tap charged for nothing, and the round is on a clock — the
/// field is up and focused the moment this appears, so the first thing somebody can do is the
/// thing they came to do.
///
/// The clock lives in the header badge (`RoundHeader`) rather than in the column, because it is
/// the only thing here that changes while nobody is touching the screen, and a ticking hero
/// countdown over a search field is a countdown competing with the typing.
///
/// Nothing on this screen counts anybody. No submitted total, no *waiting on*, no avatars — the
/// only shared fact is the clock, which everybody already has (`CLAUDE.md` §2.1).
struct SubmitScreen: View {
    let context: RoundContext
    let store: SubmitStore
    let player: PreviewPlayer
    let timer: CountdownTimer
    /// What the countdown counts to — the reveal, or the next opening during the dark hours.
    /// Chosen by `RoundContext.deadline(openState:)` against the **server's** clock, never here.
    let deadline: Date
    /// Whether the round has opened yet (`docs/08` §2, the dark-hours state).
    ///
    /// **A `Bool` because by the time it gets here it is settled**, not because there are only
    /// two possibilities. There are three — `RoundContext.OpenState` — and the third,
    /// *"the clock has no anchor and the app does not know"*, is resolved by `RoundScreen`
    /// before this screen is built: it holds the last answer the clock gave across the refetch
    /// that follows every return to the foreground, and does not construct this view at all
    /// while it has none. Which is what makes `.onAppear` below safe to raise a keyboard from.
    /// Pushing the three cases down here instead would put the same `if` on every phase screen
    /// and get it wrong on one of them.
    let isBeforeOpen: Bool
    /// Tonight's cue, when there is one.
    ///
    /// **This screen draws its own**, which is why `RoundScreen` withholds the shared
    /// `CueBanner` for this one phase. Everywhere else the cue is a fact about the round and
    /// rides above the phase screen as a line; here it is the brief, and it belongs in the
    /// column between the subhead that sets up the question and the field that answers it. Two
    /// renderings of one fact, and exactly one of them on screen at a time — see `CueCard`.
    let cue: CueDTO?
    /// **Last night's** cue, when the dark hours have a finished round behind them.
    ///
    /// The one thing on this screen that is not about the round it was built from. During the
    /// dark hours `context.round` is the *coming* night's — see `RoundContext.OpenState` — so
    /// `cue` up there is a brief nobody has answered yet, and the screen saying *"Tonight's
    /// round is done."* would be handing it out hours early. This is the cue that screen is
    /// actually talking about, and the server only sends it in that window
    /// (`docs/18-CUES.md` §7). `nil` on a circle's first night, and the card is simply absent.
    let previousCue: CueDTO?
    /// Push last night's results. `nil` outside the dark hours, and inside them when the night
    /// behind these hours has no results to show — a circle's first night, or a voided one.
    ///
    /// A closure rather than an id, because *where* a push lands is the round's business, not
    /// this screen's — the same reason `choose` hands a track upward instead of presenting the
    /// confirm step itself.
    var showLastNightsResults: (() -> Void)? = nil
    /// A chosen song goes to the confirm step, which the round presents.
    let choose: (TrackDTO) -> Void

    /// Amber, decided once at the top of the screen and handed down (`CLAUDE.md` §2.5).
    private let accent = PhaseAccent.sealed

    @FocusState private var isFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        column
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The round is on a clock, so the field is up before anybody has to reach for it —
            // but only over a round that is actually taking songs. This is the line that spent
            // a round trip raising a keyboard over the dark hours on every app open, and it is
            // fixed above rather than here: `isBeforeOpen` is now settled before it arrives.
            .onAppear { if !isBeforeOpen { isFieldFocused = true } }
            .onDisappear { player.stop() }
    }

    /// The screen's column, which the snapshots render directly.
    var snapshotContent: some View { column }

    @ViewBuilder private var column: some View {
        if isBeforeOpen {
            closed
        } else {
            SongSearch(
                store: store,
                player: player,
                accent: accent,
                isFieldFocused: $isFieldFocused,
                choose: choose,
                header: { browsing in prompt(browsing: browsing) },
                footer: { footer },
                // **This column has to fit between the round's chrome and the keyboard, and
                // the two numbers below are how it does.** Overflowing that band is not a
                // clipped screen — UIKit makes the difference up by lifting the whole window,
                // chrome included, and the lift only goes away once results arrive and the
                // subhead and cue card step aside. That is a pinned header that jumps thirteen
                // points the moment somebody stops typing (owner, 2026-09-07).
                //
                // **The two numbers are not the same knob, and that is what makes both
                // answerable** (owner, 2026-09-10). `blockSpacing` is how dense the block reads;
                // `topGapCap` is how far it travels when the keyboard arrives. Squeezing the
                // spacing to buy fitting room, as `itemGap` did, pays for one with the other.
                //
                // `blockGap` is the app's rhythm and this screen wanted it, like every other
                // column — but it does not have the height for it. At 32 the column overflowed
                // the band between the chrome and the keyboard and the header lifted again,
                // which is the whole thing `E43` was fixed to stop (owner, 2026-09-10).
                //
                // `xxl` is one step down the ramp and the smallest one there is: 28 is not a
                // token, so 24 is the least this can give up. It returns 32 points across the
                // four gaps, and another 8 come from the cue card's own padding, which steps
                // down with it so the card keeps even air — see `prompt(browsing:)`. Forty
                // points, for a deficit that measured around eight.
                //
                // **The cap is a ceiling, not a position.** This gap and the open one under the
                // block are both flexible, so they split whatever the column has left over: with
                // the keyboard down this one takes its full ceiling, and as the keyboard comes up
                // the leftover shrinks and this gap gives up half of the loss, continuously, to
                // zero at the limit. The block therefore rises by exactly what the keyboard costs
                // and no more, and nothing here has to know whether a keyboard is up.
                //
                // **So the ceiling sets the resting position and nothing else** (owner,
                // 2026-09-10), which is the useful consequence: with the keyboard up the
                // leftover is around thirty points and half of that is well under any ceiling
                // worth setting, so the ceiling is not what is binding there. Raise it and the
                // keyboard-up screen does not move at all; only the screen at rest comes down,
                // out of a bottom gap that had a third of a page in it and nothing to say.
                //
                // `x5` rather than the 24 that stopped the lift: 56 at rest, which is where the
                // block wants to sit under the badge row, and the same place as before once the
                // keyboard is up. The travel is longer for it — about forty points — and that is
                // bought deliberately, unlike the hard forty-eight a focus flag briefly snapped
                // through here before the flexible pair was left to do it continuously.
                //
                // The floor under this is roughly the keyboard-up leftover: set the ceiling
                // below half of that and it starts binding in both states again, which is when
                // moving it would start moving the keyboard-up block too.
                blockSpacing: Space.xxl,
                topGapCap: Space.x5
            )
        }
    }

    // MARK: - Open

    /// *"Today's song."* and, while there is nothing under it yet, the one line of rules.
    ///
    /// **`E26-03`: the subhead steps aside once there are rows to show.** At `.accessibility5`
    /// the headline (capped, `docs/12` §1) plus an uncapped subhead plus the field — stacked
    /// under the round's own chrome, above a keyboard that is already up — left no room for a
    /// single result row on iPhone 17; reproduced as zero rows visible while typing. The subhead
    /// has done its job by the time a result exists to look at, so it is what gives the room
    /// back rather than the headline (`docs/08` §2's *"headline and field at the top of the
    /// screen"* while searching) or the field (still has to be read to keep typing in).
    ///
    /// The cue card is the second thing in this block and answers the same question differently
    /// — see `showsSubhead(browsing:)` for which of the two yields, and when.
    private func prompt(browsing: Bool) -> some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("submit.headline")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if showsSubhead(browsing: browsing) {
                // `bodyM`, not `bodyL`: with the cue card directly beneath it at `displayS`,
                // a 17pt subhead and a 24pt cue read as two headings arguing. Dropping the
                // subhead a step puts the three lines in order — headline, the aside, the brief.
                Text(verbatim: Copy.format("submit.subhead", context.revealTime))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // The cue steps aside while browsing, for the reason the subhead does: this is a
            // keyboard-up screen and the rows need the room (`E26-03`). It is the brief for the
            // search that has now started, and it has been read by the time the first result
            // exists — whereas a result nobody can see has not been read at all. It does *not*
            // step aside at accessibility sizes, though; there the subhead goes instead, because
            // between the tutorial and the brief the brief is the one with something to say.
            if !browsing, let cue {
                // **`Space.md` on top of the stack's own `itemGap`, to make twenty-four** — the
                // same gap `SongSearch` puts *below* the card on its way to the field, because
                // this is the one element in the column with a drawn edge on both sides, and
                // unequal air around it reads as the card having slipped upward (owner,
                // 2026-09-10). Written as the padding that closes the difference rather than as
                // the gap outright, since the stack's own `itemGap` is already paid.
                //
                // **It was 32 either side for a day and the column could not afford it.** The
                // header lifted again — `E43`'s bug, back — so both gaps came down one step of
                // the ramp together, which is the least they can move and still land on tokens:
                // there is nothing at 28. This padding gives up 8 and `blockSpacing` gives up 32
                // across its four gaps, and the pair stay equal, which was the point of the
                // padding in the first place. Move one of these and move the other.
                CueCard(cue: cue)
                    .padding(.top, Space.md)
                    .transition(.opacity)
            }
        }
        // Same duration as `SongSearch`'s own browsing-state transition (`SongSearch.swift`'s
        // `body`), which this fade rides alongside — a mismatched duration would have the
        // subhead finish fading a beat before the layout around it settles.
        .animation(.easeInOut(duration: 0.22), value: browsing)
    }

    /// Whether *"Nobody sees it until 8:00 PM."* — the circle's own hour, never the 20:00
    /// default — is drawn.
    ///
    /// Two reasons it is not. The first is `E26-03`'s: once there are results, the subhead has
    /// done its job and the rows need the room. The second is the cue card's. At accessibility
    /// sizes the headline, an uncapped two-line subhead, the card and the field — stacked under
    /// the round's own chrome, above a keyboard that is already up — are taller than the screen,
    /// and something above the fold has to give. It is the subhead rather than the card because
    /// the subhead is the tutorial and the card is tonight's actual instruction: a reader who
    /// loses the cue is guessing at the round, and a reader who loses the subhead has lost a
    /// sentence the reveal will teach them anyway.
    ///
    /// **It does not step aside for a cue at ordinary sizes** (owner, 2026-09-07). A cued night
    /// is the common night, and the line it would cost is the one that says what the app is
    /// for. The room the cue card needs comes out of the gaps instead — see `blockSpacing` and
    /// `topGapCap` at the call site.
    private func showsSubhead(browsing: Bool) -> Bool {
        !browsing && !dynamicTypeSize.isAccessibilitySize
    }

    /// What sits under the field while nothing has been searched for: the nudge if the reveal is
    /// close, and the fact that makes the whole game work.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            // `docs/08` §2: under two hours the nudge appears, in `amberText`, and **nothing
            // else changes**. It is an in-interface nudge and deliberately not the push — the
            // push is `docs/05` §3's, goes only to non-droppers, and says the same thing because
            // there is only one true thing to say.
            if showsNudge {
                Text("submit.nudge")
                    .typeStyle(.bodyM)
                    .foregroundStyle(accent.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Text("submit.blind")
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The dark hours

    /// Between the answers and tomorrow's opening there is nothing to search for, so the screen
    /// says what it is waiting for and counts to it.
    private var closed: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            Spacer(minLength: Space.none)
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                Text("submit.closed.headline")
                    .typeStyle(.displayL)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: Copy.format("submit.closed.subhead", context.opensTime))
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The dark hours have no field for a cue to brief, and the round they belong to is
            // the *coming* one — so the card here names the night that just ended rather than
            // the one whose cue is still sealed. `RoundScreen` draws no banner for this phase,
            // so this is the only cue on screen, and there is none at all until a circle has a
            // finished round behind it.
            if let previousCue {
                CueCard(
                    cue: previousCue,
                    label: "round.cue.card.last.label",
                    labelColor: Palette.inkDim
                )
            }
            countdown
            Spacer(minLength: Space.none)
            // The way into the night the headline is about. These hours are the only phase with
            // nothing to do — a headline, a card and a clock — and until this existed the screen
            // announced that a round had finished and gave no way to see what happened in it;
            // the only route back was the header menu, The Record, and the night at the top of
            // it, which is the one you were already looking at.
            //
            // **`OutlineButton`, which is the neutral one.** Results are ultramarine and this
            // screen is amber, and two accents on one screen is the rule's violation
            // (`CLAUDE.md` §2.5) — so this cannot be a `PrimaryButton` in the phase colour of
            // where it goes. The outline carries no accent at all, which is also the right
            // weight: it is the only action on the screen, so a text link at 3 a.m. would be
            // easy to miss, but the countdown above it is still the subject and a filled button
            // would out-shout it.
            //
            // **Below the countdown, against the bottom.** Directly under the cue card — where
            // it started — an outlined button and `CueCard` are two white rounded rectangles of
            // near-identical weight stacked on each other, and the screen reads as two cards
            // rather than as content plus an action. The Spacer settles it: content at the top,
            // the one action at the bottom, which is exactly the arrangement `SealedScreen`
            // already uses for **Replace**.
            //
            // It does not replace the cue card. The cue is content — what was asked last night,
            // readable without going anywhere — and this is a route; and either can be present
            // without the other, which is why they are two `if`s and not one.
            if let showLastNightsResults {
                OutlineButton("submit.closed.results", action: showLastNightsResults)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.xxl)
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("submit.closed.countdown.label")
            CountdownView(
                timer: timer,
                deadline: deadline,
                accent: accent,
                announces: .reveal
            )
        }
        // The countdown announces itself in full (`a11y.countdown`); the label above it is part
        // of that sentence rather than a second stop.
        .accessibilityElement(children: .combine)
    }

    /// Under two hours to the reveal (`docs/08` §2).
    ///
    /// Read off the **countdown that is already ticking** rather than from a second clock. Two
    /// things fall out of that: the line appears the second the visible countdown crosses two
    /// hours rather than at the next refetch, and there is no `Date()` anywhere near it
    /// (`docs/13` §5 rule 1).
    private var showsNudge: Bool {
        guard !isBeforeOpen, let remaining = timer.display.secondsRemaining else { return false }
        return remaining < Self.nudgeThreshold
    }

    /// Two hours, in seconds. The same threshold `docs/05` §3 enqueues the push at.
    static let nudgeThreshold = 2 * 60 * 60
}
