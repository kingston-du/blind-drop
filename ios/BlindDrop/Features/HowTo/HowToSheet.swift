import SwiftUI

/// **How to play** — reached from the `[?]` beside every phase's menu (`RoundHeader`) and from
/// sign-in, before there is even a round.
///
/// Presented as a sheet, never a fourth `Route` (`Route.swift`: *"Adding a fourth case is a
/// product change, not a refactor"*) — `SearchSheet` already established the sheet as this app's
/// way of putting a screen over another one without extending the navigation path.
///
/// **This page is the legend** — the second exception to `CLAUDE.md` §2.5, named there by the
/// owner alongside the reveal transition.
///
/// The rule it is an exception to forbids two things: an accent used decoratively, and both
/// accents on one screen. Neither ban is about what happens here. The four steps are not four
/// topics that happen to be numbered — they **are** the four phases of a round, in order. Step 1
/// is the blind window, and step 1 is the only step drawn in amber; steps 2, 3 and 4 are what
/// happens once the information is out, and all three are ultramarine. The colour is saying
/// exactly what it says everywhere else in the app — *hidden* or *open* — with the one
/// difference that here the reader sees both at once and can therefore learn which is which.
/// Everywhere else, the colour is a fact about the round. Here it is the key to that fact, and a
/// key with the colours left out is not a quieter key, it is a blank one.
///
/// That is also why the accent is taken from `PhaseAccent.mark` and not from `Palette`. The
/// numerals are the same tier at the same `numberM` size as `FlightCard`'s card number: the
/// amber beside *Drop a song* is literally the amber of a sealed card, and the ultramarine
/// beside *The reveal* is literally the ultramarine that replaces it. A legend drawn in colours
/// only approximately those of the thing it explains teaches nothing, so this page reaches for
/// the same vocabulary the phase screens do rather than for a hex that resembles it.
///
/// **Nothing else here is accented, and the exception does not travel.** It is granted to a page
/// whose subject is the colour language itself; a page that merely *mentions* a phase does not
/// inherit it. The scoring and Good-to-know cards stay in the neutral tiers, with the same
/// apparatus `SettingsScreen` and `RecordScreen` use for a page that is *about* the app rather
/// than *of* a round: `SectionLabel`s, `Rule`s, `cardSurface()`.
struct HowToSheet: View {
    /// The hour a round seals — `docs/02` §1's `reveal_hour` — so the times on this page are the
    /// **group's** real schedule and not the copy deck's placeholder ones. Defaults to the group
    /// default (`RevealHour.default`, 20:00) for the one place this sheet opens before there is a
    /// group to read a real hour from: `SignInScreen`.
    var revealHour: Int = RevealHour.default
    let close: () -> Void

    private var opensTime: String {
        RevealHour.formatted(RevealHour.opensHour(revealHour: revealHour))
    }
    private var revealTime: String { RevealHour.formatted(revealHour) }
    private var scoresTime: String {
        RevealHour.formatted(RevealHour.scoresHour(revealHour: revealHour))
    }

    var body: some View {
        ScrollView {
            column
                .padding(.horizontal, Layout.screenInset)
                .padding(.vertical, Layout.blockGap)
        }
        .background(Palette.paper)
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// The column the sheet scrolls, exposed bare for the snapshot suite. `ImageRenderer`
    /// silently drops everything inside a `ScrollView` rather than clipping it, so every snapshot
    /// in this app points at a screen's undressed content and never at `body`.
    var snapshotContent: some View { column }

    private var column: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            closeRow
            intro
            stepsCard
            scoringCard
            notesCard
        }
    }

    // MARK: - Header

    private var closeRow: some View {
        HStack {
            Spacer(minLength: Space.none)
            CloseButton(action: close)
        }
    }

    /// Not `private` — the snapshot suite renders each block separately at `.accessibility5`
    /// (`docs/12` §8), because the **whole** page at that size is over 9,800px tall on an SE and
    /// the encoder cannot write a PNG that long (`SnapshotRenderer`'s note on `pngData`). A block
    /// this suite can reach on its own is one the "nothing truncates, nothing overlaps" check
    /// still covers; a golden of the full page just cannot be one image at that size.
    var intro: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            SectionLabel("onboarding.title")
            Text("howto.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("howto.intro")
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The four steps

    /// The four steps, and the accents that make this page a legend rather than an explainer.
    ///
    /// Step 1 is `.sealed` because dropping a song *is* the blind window. Steps 2, 3 and 4 are
    /// `.revealed` because all three happen after the information is out — the reveal, the guess
    /// made against it, and the scores read off it. That is the whole colour language of the app
    /// stated once, in order, on one page.
    var stepsCard: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            step(1, .sealed, title: "howto.step1.title", time: opensTime,
                 body: "howto.step1.body")
            Rule()
            step(2, .revealed, title: "howto.step2.title", time: revealTime,
                 body: "howto.step2.body")
            Rule()
            step(
                3, .revealed, title: "howto.step3.title", time: Copy.string("howto.step3.time"),
                body: "howto.step3.body"
            )
            Rule()
            step(4, .revealed, title: "howto.step4.title", time: scoresTime,
                 body: "howto.step4.body")
        }
        // The spine sits at the leading edge and the steps clear it by the same gap that
        // separates a numeral from its own text, so the numeral column reads as a column.
        .padding(.leading, Space.md)
        .background(alignment: .leading) { Spine() }
        .cardSurface()
    }

    /// The hairline down the left of the numeral column.
    ///
    /// Four numbered blocks separated by rules read as a list of four things. The same four with
    /// an unbroken line down their left read as **one** thing with four stops on it, which is
    /// what a round is — and the difference matters most on the step the reader is not currently
    /// living in, because a sequence is the only thing on this page that says the amber step and
    /// the ultramarine ones are the same day.
    ///
    /// Deliberately **neutral**: `edge` at one device pixel, the same weight and family of line
    /// the card draws around itself and `Rule` draws across it. The accent on this page belongs
    /// to the four phases; the spine is not a phase, it is the thread they hang on, and colouring
    /// it would be the decorative use `CLAUDE.md` §2.5 still forbids.
    ///
    /// A `View` rather than a computed property on `HowToSheet`, for the same reason `Rule` is
    /// one: `@Environment` only resolves on a view that has been installed in a tree, and the
    /// snapshot suite reaches `stepsCard` directly on a bare `HowToSheet`. Read from there, the
    /// display scale would silently answer 1 and the golden would carry a 1pt spine that no
    /// device draws.
    private struct Spine: View {
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Rectangle()
                .fill(Palette.edge)
                .frame(width: Stroke.hairline(atScale: displayScale))
                .accessibilityHidden(true)
        }
    }

    /// One step: a numeral, a title, the clock time it happens at, and the one line of what it
    /// is. The time is set in the mono face — `docs/07` §3 reserves it for *"countdown digits,
    /// percentages, scores, counts"*, and a clock reading is the same kind of fact.
    ///
    /// The numeral takes `accent.mark`, the drawing tier — the same tier and the same `numberM`
    /// style `FlightCard` sets its card number in, which is the point: this numeral is a sample
    /// of that one. `mark` clears the 3.0 bar a graphic-scale element has to meet on `surface`
    /// (amber 4.24:1, ultramarine 8.98:1) at every Dynamic Type size the display face resolves
    /// to; `PaletteContrastTests.theLegendNumeralsClearTheBarAtTheSizeTheyAreDrawn` asserts both
    /// halves of that sentence rather than leaving the size half to a reader's eye.
    private func step(
        _ number: Int,
        _ accent: PhaseAccent,
        title: LocalizedStringKey,
        time: String,
        body: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Text(verbatim: "\(number)")
                .typeStyle(.numberM)
                .foregroundStyle(accent.mark)
                .frame(minWidth: Space.xl, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: time)
                    .typeStyle(.monoS)
                    .foregroundStyle(Palette.inkDim)
                Text(body)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xxs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Scoring

    /// **Neutral, and it stays neutral.** The legend exception above buys the steps an accent
    /// because the steps are the phases; it buys this card nothing, because `Ear` and
    /// `Readability` are not phases and are not ranked against each other. `docs/16` makes them
    /// unranked by design — two different things a round can tell you about a person, neither of
    /// which is the better score to have. Put ultramarine on one of them and the page starts
    /// answering a question the game deliberately refuses to answer: *which one am I supposed to
    /// be winning?*
    var scoringCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("howto.scoring.title")
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                term("howto.ear.title", body: "howto.ear.body")
                Rule()
                term("howto.read.title", body: "howto.read.body")
            }
            .cardSurface()
        }
    }

    private func term(_ title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
            Text(body)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Good to know

    var notesCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("howto.notes.title")
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                note("howto.note.void")
                Rule()
                note("howto.note.replace")
                Rule()
                note("howto.note.watch")
                Rule()
                note("howto.note.record")
            }
            .cardSurface()
        }
    }

    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
