import SwiftUI

/// **How to play** — reached from the `[?]` beside every phase's menu (`RoundHeader`) and from
/// sign-in, before there is even a round.
///
/// Presented as a sheet, never a fourth `Route` (`Route.swift`: *"Adding a fourth case is a
/// product change, not a refactor"*) — `SearchSheet` already established the sheet as this app's
/// way of putting a screen over another one without extending the navigation path.
///
/// **No accent** (`CLAUDE.md` §2.5). Amber names *sealed* and ultramarine names *revealed* —
/// facts about what a round is doing right now. This page is true on every phase and before any
/// round has ever run, so giving it either colour would be exactly the decorative use the rule
/// forbids. Everything here is drawn in the neutral tiers, with the same apparatus
/// `SettingsScreen` and `RecordScreen` already use for a page that is *about* the app rather
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

    var stepsCard: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            step(1, title: "howto.step1.title", time: opensTime, body: "howto.step1.body")
            Rule()
            step(2, title: "howto.step2.title", time: revealTime, body: "howto.step2.body")
            Rule()
            step(
                3, title: "howto.step3.title", time: Copy.string("howto.step3.time"),
                body: "howto.step3.body"
            )
            Rule()
            step(4, title: "howto.step4.title", time: scoresTime, body: "howto.step4.body")
        }
        .cardSurface()
    }

    /// One step: a numeral, a title, the clock time it happens at, and the one line of what it
    /// is. The time is set in the mono face — `docs/07` §3 reserves it for *"countdown digits,
    /// percentages, scores, counts"*, and a clock reading is the same kind of fact.
    private func step(
        _ number: Int,
        title: LocalizedStringKey,
        time: String,
        body: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Text(verbatim: "\(number)")
                .typeStyle(.numberM)
                .foregroundStyle(Palette.inkFaint)
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
