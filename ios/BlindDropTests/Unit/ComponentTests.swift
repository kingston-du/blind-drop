import SwiftUI
import Testing
@testable import BlindDrop

/// The parts of the component library that are rules rather than pixels.
///
/// A snapshot proves a layout did not move. It does not prove that the artwork URL asked for
/// the right number of pixels, that a band boundary falls on the same side as the server's, or
/// that a VoiceOver label carries the four facts `docs/12` §2 requires — those are assertions,
/// and `docs/15` §7 wants a passing test rather than a look at a picture.
@MainActor
@Suite struct ComponentRules {

    // MARK: - Artwork sizing (docs/06 §2.1)

    @Test func artworkSubstitutesBothPlaceholdersAtTheDisplayScale() throws {
        let url = try #require(ArtworkView.resolvedURL(
            template: "https://is1-ssl.mzstatic.com/image/thumb/x/{w}x{h}bb.jpg",
            points: 88,
            scale: 3
        ))
        // 88pt of reveal-card artwork on a 3× screen is 264px, and both axes are substituted.
        #expect(url.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/x/264x264bb.jpg")
    }

    @Test func artworkNeverAsksForMoreThanTwelveHundredPixels() throws {
        // 600pt of confirm card at 3× would be 1800px of album art over a phone network at 8pm.
        let url = try #require(ArtworkView.resolvedURL(template: "a/{w}x{h}.jpg", points: 600, scale: 3))
        #expect(url.absoluteString == "a/1200x1200.jpg")
    }

    @Test func artworkOfAtrackWithNoTemplateHasNoURL() {
        #expect(ArtworkView.resolvedURL(template: nil, points: 88, scale: 3) == nil)
        #expect(ArtworkView.resolvedURL(template: "", points: 88, scale: 3) == nil)
    }

    @Test(arguments: [
        (CGFloat(56), CGFloat(2), "112x112"),   // search row
        (CGFloat(320), CGFloat(1), "320x320"),  // reveal card, 1×
        (CGFloat(900), CGFloat(1), "900x900"),  // share card
    ])
    func artworkSizesFromTheContract(points: CGFloat, scale: CGFloat, expected: String) throws {
        let url = try #require(ArtworkView.resolvedURL(template: "a/{w}x{h}.jpg", points: points, scale: scale))
        #expect(url.absoluteString == "a/\(expected).jpg")
    }

    @Test func placeholderIsTheDominantColourAndNothingElse() {
        // `artwork_bg_color` is nullable in the contract, and unparseable is the same as absent:
        // a card with no dominant colour is a normal card, not a broken one.
        #expect(ArtworkView.placeholderColor(nil) == Color.clear)
        #expect(ArtworkView.placeholderColor("nope") == Color.clear)
        #expect(ArtworkView.placeholderColor("1d2b3a") == Color(hex: 0x1D2B3A).opacity(0.12))
        #expect(ArtworkView.placeholderColor("#1d2b3a") == Color(hex: 0x1D2B3A).opacity(0.12))
    }

    // MARK: - Readability bands (docs/02 §4.5, mirroring 0005_scoring.sql)

    @Test(arguments: [
        (1.0, ReadabilityBand.openBook),
        (0.80, .openBook),      // the boundary, inclusive — a `>` here demotes somebody silently
        (0.7999, .legible),
        (0.60, .legible),
        (0.5999, .mixedSignals),
        (0.40, .mixedSignals),
        (0.3999, .hardToPlace),
        (0.20, .hardToPlace),
        (0.1999, .unreadable),
        (0.0, .unreadable),
    ])
    func bandBoundariesMatchTheServer(value: Double, expected: ReadabilityBand) {
        #expect(ReadabilityBand(readability: value) == expected)
    }

    // MARK: - The accent is a parameter, not a lookup

    @Test func eachAccentPairsAFillWithSomethingLegibleOnIt() {
        // The two rows of the docs/07 §2 contrast table that a button depends on. The ratios
        // themselves are PaletteContrastTests' job; what is asserted here is that the component
        // library reaches for the right token, which is the part a refactor gets wrong.
        #expect(PhaseAccent.sealed.fill == Palette.amber)
        #expect(PhaseAccent.sealed.onFill == Color.white)
        #expect(PhaseAccent.revealed.fill == Palette.ultramarine)
        #expect(PhaseAccent.revealed.onFill == Color.white)
        // `amber` both fills and draws — it clears 3.0:1 on `surface`, so the mark tier and the
        // fill tier are the same token. `amberText` is still separate, because a *word* has to
        // clear 4.5 and this does not.
        #expect(PhaseAccent.sealed.mark == Palette.amber)
        #expect(PhaseAccent.sealed.text == Palette.amberText)
    }

    @Test(arguments: [
        (RoundState.open, PhaseAccent.sealed),
        (.voided, .sealed),      // nothing was revealed, so nothing is open
        (.revealed, .revealed),
        (.scored, .revealed),
    ])
    func phaseAccentFollowsTheRoundState(state: RoundState, expected: PhaseAccent) {
        #expect(PhaseAccent(state) == expected)
    }

    // MARK: - Touch targets (docs/12 §5)

    @Test func theControlsDrawnSmallerThanFortyFourDeclareItInOnePlace() {
        // Both are deliberately smaller than the minimum and both carry a 44pt contentShape —
        // `minimumTouchTarget()`, asserted here so the numbers cannot drift apart silently.
        #expect(Layout.previewControl < Layout.minimumTouchTarget)
        #expect(Layout.chipHeight < Layout.minimumTouchTarget)
        #expect(Layout.minimumTouchTarget == 44)
    }
}

/// `docs/12` §8: *"Card announces all four facts — unit test on the label builder against the
/// `a11y.card.*` formats."* Literally that.
@Suite struct AccessibilityCopyTests {

    @Test func everyKeyTheComponentsRenderResolves() {
        // A missing row returns the key itself, which renders as `a11y.card.mine` on a card and
        // is the one localisation bug that looks like a design decision.
        let keys = [
            "countdown.unknown", "countdown.coarse.hours", "countdown.coarse.minutes",
            "countdown.coarse.soon",
            "reveal.title", "reveal.subtitle", "reveal.countdown.label", "reveal.progress",
            "reveal.card.prompt", "reveal.card.mine", "reveal.action",
            "reveal.action.locked", "reveal.edit",
            "reveal.blocked.notsubmitter", "reveal.blocked.joinedlate", "reveal.blocked.canview",
            "a11y.rotor.songs", "a11y.rotor.song",
            "a11y.card", "a11y.card.guessed", "a11y.card.unguessed", "a11y.card.mine",
            "a11y.card.hint", "a11y.sealed", "a11y.countdown", "a11y.countdown.answers",
            "a11y.namechip", "a11y.namechip.unassigned", "a11y.namechip.assigned",
            "a11y.guess.assigned", "a11y.preview.play", "a11y.preview.stop",
            "a11y.track", "a11y.track.hint", "a11y.readability",
            "switcher.title", "switcher.state.drop", "switcher.state.sealed",
            "switcher.state.guess", "switcher.state.answers", "switcher.state.voided",
            "switcher.invites",
            "a11y.switcher.opener.hint", "a11y.switcher.opener.otherNeedsAction",
            "a11y.switcher.row", "a11y.switcher.row.hint", "a11y.switcher.attention",
            "howto.title", "howto.intro",
            "howto.step1.title", "howto.step1.body",
            "howto.step2.title", "howto.step2.body",
            "howto.step3.title", "howto.step3.time", "howto.step3.body",
            "howto.step4.title", "howto.step4.body",
            "howto.scoring.title", "howto.ear.title", "howto.ear.body",
            "howto.accuracy.title", "howto.accuracy.body",
            "results.accuracy.label", "results.accuracy.detail", "results.accuracy.none",
            "results.tonight.past.title", "results.tonight.scope", "results.tonight.correct",
            "results.tonight.a11y", "share.accuracy.label", "profile.history",
            "howto.read.title", "howto.read.body",
            "howto.notes.title", "howto.note.void", "howto.note.replace",
            "howto.note.watch", "howto.note.record",
        ]
        for key in keys {
            #expect(Copy.string(key) != key, "\(key) is not in Localizable.strings")
        }
        for band in ReadabilityBand.allCases {
            #expect(Copy.band(band) != "band.\(band.rawValue)")
        }
    }

    @Test func aGuessedCardAnnouncesNumberTitleArtistAndGuess() {
        let label = Copy.A11y.card(
            number: 3, title: "Ribs", artist: "Lorde", guess: .assigned(name: "Cal")
        )
        #expect(label == "No. 3. Ribs by Lorde. Guessed as Cal.")
    }

    @Test func anUnguessedCardSaysSoRatherThanSayingNothing() {
        let label = Copy.A11y.card(number: 3, title: "Ribs", artist: "Lorde", guess: .none)
        #expect(label == "No. 3. Ribs by Lorde. No guess yet.")
    }

    @Test func theCallersOwnCardIsNamedAsTheirs() {
        let label = Copy.A11y.card(number: 7, title: "Ribs", artist: "Lorde", guess: .mine)
        #expect(label == "No. 7. Ribs by Lorde. Your song.")
    }

    @Test func aCardInAroundTheCallerCannotGuessInAnnouncesThreeFactsAndNoFourth() {
        // A non-submitter's card has no guess, and inventing "no guess yet" for it would be
        // telling them they have a sheet to fill in (`docs/04` §4).
        let label = Copy.A11y.card(number: 1, title: "Ribs", artist: "Lorde", guess: .unavailable)
        #expect(label == "No. 1. Ribs by Lorde.")
    }

    @Test func aConsumedNameChipAnnouncesWhichCardItIsOn() {
        // docs/12 §3: opacity alone is not a status indicator.
        #expect(Copy.A11y.nameChip("Cal", assignedTo: 3) == "Cal. Assigned to No. 3")
        #expect(Copy.A11y.nameChip("Cal", assignedTo: nil) == "Cal. Unassigned")
        #expect(Copy.A11y.nameChipValue(assignedTo: 3) == "Assigned to No. 3")
        #expect(Copy.A11y.nameChipValue(assignedTo: nil) == "Unassigned")
    }

    @Test func theCountdownAnnouncesWhatItIsCountingTo() {
        let display = CountdownDisplay(remaining: 7265, form: .precise)
        #expect(Copy.A11y.countdown(display, until: .reveal) == "02:01:05 until reveal")
        #expect(Copy.A11y.countdown(display, until: .answers) == "02:01:05 until answers")
    }

    @Test func anUnanchoredCountdownSaysItDoesNotKnow() {
        // docs/13 §5 rule 3 — before the first response the app does not guess.
        #expect(Copy.countdown(.unknown) == "--:--:--")
        #expect(Copy.A11y.countdown(.unknown, until: .reveal) == "--:--:-- until reveal")
    }

    @Test func theCoarseFormUsesWordsRatherThanDigits() {
        #expect(Copy.countdown(CountdownDisplay(remaining: 10_800, form: .coarse)) == "3 hours")
        #expect(Copy.countdown(CountdownDisplay(remaining: 720, form: .coarse)) == "12 minutes")
        #expect(Copy.countdown(CountdownDisplay(remaining: 30, form: .coarse)) == "under a minute")
    }

    @Test func countCopyUsesThePluralDictionary() {
        #expect(Copy.countdown(CountdownDisplay(remaining: 3_600, form: .coarse)) == "1 hour")
        #expect(Copy.countdown(CountdownDisplay(remaining: 60, form: .coarse)) == "1 minute")
        #expect(Copy.format("reveal.subtitle", 1) == "1 song")
        #expect(Copy.format("reveal.subtitle", 8) == "8 songs")
        #expect(Copy.format("record.export.partial", 1, "Spotify")
                == "1 song isn't on Spotify. The rest are in.")
        #expect(Copy.format("share.headline.fallback", 1, 1) == "1 song, 1 guess")
        #expect(Copy.format("share.headline.fallback", 8, 42) == "8 songs, 42 guesses")
    }

    @Test func theReadabilityMeterAnnouncesAPercentageAndABand() {
        #expect(Copy.A11y.readability(percent: 86, band: .openBook) == "Readability 86 percent. Clear.")
    }

    @Test func theSealedCardAnnouncesTheSongAndWhenItOpens() {
        let label = Copy.A11y.sealed(title: "Ribs", artist: "Lorde", remaining: "02:01:05")
        #expect(label == "Your song is sealed. Ribs by Lorde. Reveal in 02:01:05.")
    }

    @Test func nothingInTheAccessibilityCopyCountsParticipation() {
        // docs/12 §2: the blind window applies to VoiceOver too. No label may carry a count of
        // submissions or a member's submitted status. The submit-phase labels are the sealed
        // card and the countdown, and neither takes a number that could be one.
        let sealed = Copy.A11y.sealed(title: "Ribs", artist: "Lorde", remaining: "02:01:05")
        #expect(!sealed.contains("of"))
        let countdown = Copy.A11y.countdown(CountdownDisplay(remaining: 60, form: .precise), until: .reveal)
        #expect(!countdown.contains("of"))
    }

    // MARK: - The switcher (`E19-02`)

    @Test func aSwitcherRowAnnouncesNameThenState() {
        let label = Copy.A11y.switcherRow(name: "The Cove", state: "Sealed", needsAction: false)
        #expect(label == "The Cove. Sealed.")
    }

    /// The third sentence is the VoiceOver channel for the row's small mark — appended, not a
    /// third placeholder, so a circle that does not need attention never carries a silent
    /// "false" through the format.
    @Test func aSwitcherRowThatNeedsActionAddsAThirdSentence() {
        let label = Copy.A11y.switcherRow(name: "The Cove", state: "Drop a song", needsAction: true)
        #expect(label == "The Cove. Drop a song. Wants your attention.")
    }

    @Test func theHeaderOpenerIsJustTheGroupNameWhenNothingElseNeedsIt() {
        #expect(Copy.A11y.switcherOpener(groupName: "The Cove", otherNeedsAction: false) == "The Cove")
    }

    @Test func theHeaderOpenerNamesAnotherCircleWantingAttention() {
        let label = Copy.A11y.switcherOpener(groupName: "The Cove", otherNeedsAction: true)
        #expect(label == "The Cove Another group wants your attention.")
    }
}
