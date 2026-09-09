import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// Every component of `docs/07` §5 across `docs/12` §8's matrix — `{SE, 15 Pro Max}` ×
/// `{large, accessibility1, accessibility5}`, sixty goldens.
///
/// Neither axis is arbitrary. `.large` is the default nobody's layout breaks at;
/// `.accessibility1` is where `docs/12` §1 requires side-by-side layouts to **reflow to
/// stacked**, so it is the size at which a `ViewThatFits` that never fires shows up; and
/// `.accessibility5` on an SE's 375pt is the worst case in the app — the combination `docs/12`
/// §1 says to test explicitly, where *"nothing truncates and nothing overlaps"* either holds or
/// visibly does not. The 15 Pro Max catches the opposite failure: a layout that only looked
/// right because it was cramped.
@MainActor
@Suite struct ComponentSnapshots {

    // MARK: - The ten components

    @Test(arguments: devices, sizes) func primaryButton(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "PrimaryButton", device, size) {
            VStack(spacing: Space.lg) {
                PrimaryButton("submit.action", accent: .sealed) {}
                PrimaryButton("reveal.action", accent: .revealed) {}
                PrimaryButton("reveal.action", accent: .revealed, isEnabled: false) {}
            }
        }
    }

    @Test(arguments: devices, sizes) func secondaryButton(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "SecondaryButton", device, size) {
            VStack(alignment: .leading, spacing: Space.lg) {
                SecondaryButton("sealed.replace") {}
                SecondaryButton("sealed.replace", isEnabled: false) {}
            }
        }
    }

    @Test(arguments: devices, sizes) func trackRow(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "TrackRow", device, size) {
            VStack(spacing: 0) {
                TrackRow(track: .ribs, preview: .init(isPlaying: false) {}) {}
                TrackRow(track: .motionSickness, preview: .init(isPlaying: true) {}) {}
                TrackRow(track: .longTitle) {}
            }
        }
    }

    @Test(arguments: devices, sizes) func flightCard(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "FlightCard", device, size) {
            VStack(spacing: Space.lg) {
                FlightCard(
                    number: 4,
                    track: .motionSickness,
                    accent: .revealed,
                    assignment: .unguessed,
                    preview: .init(isPlaying: false) {},
                    chooseGuess: {}
                )
                FlightCard(
                    number: 11,
                    track: .ribs,
                    accent: .revealed,
                    assignment: .guessed(name: "Cal"),
                    chooseGuess: {}
                )
                FlightCard(number: 7, track: .ribs, accent: .revealed, assignment: .mine)
                // The answer card (`E26-01`): `assignment: .resolved` is the results screen's
                // shape, not the reveal's, and it is the one place a `preview:` on this
                // component was never exercised — `TrackRow`'s own goldens above cover the
                // control's two states, but not this component's `isAnswer` layout carrying one
                // at all. `.motionSickness` is deliberate: an ordinary two-word title that
                // narrows below `.accessibility1` (docs/12 §1's reflow) and was truncating to
                // "Motion…" before `.minimumScaleFactor(0.8)` — see the title comment above.
                FlightCard(
                    number: 4,
                    track: .motionSickness,
                    accent: .revealed,
                    assignment: .resolved(CardResolution(
                        owner: "Eli", correctCount: 1, eligibleCount: 7, myGuess: nil
                    )),
                    preview: .init(isPlaying: false) {}
                )
            }
        }
    }

    @Test(arguments: devices)
    func flightCardBeforeUnseal(_ device: SnapshotRenderer.Device) {
        verify(named: "FlightCard-sealed", device, .large) {
            FlightCard(
                number: 4,
                track: .motionSickness,
                accent: .revealed,
                assignment: .unguessed,
                unseal: UnsealPresentation(
                    phase: .sealed,
                    groupInitial: "H",
                    reducedMotion: false
                )
            )
        }
    }

    /// Hidden — the default (`docs/08` §4, `E22-01`): **Hold to peek** in place of the title and
    /// artist, the cover still down over the artwork.
    @Test(arguments: devices, sizes) func sealedCard(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "SealedCard", device, size) {
            SealedCard(track: .ribs, groupInitial: "H", remaining: "02:01:05")
        }
    }

    /// Peeking: a finger held down, the cover out of the way, the title and artist showing —
    /// `docs/08` §4's other state. `.large` and `.accessibility5` rather than the full matrix,
    /// since the hidden card above already covers the six-way grid and what a peek adds is the
    /// two-line title/artist block, whose worst case is the narrowest device at the largest type.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func sealedCardPeeking(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "SealedCard-peeking", device, size) {
            SealedCard(track: .ribs, groupInitial: "H", remaining: "02:01:05", isPeeking: true)
        }
    }

    @Test(arguments: devices, sizes) func nameChip(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "NameChip", device, size) {
            VStack(alignment: .leading, spacing: Space.sm) {
                NameChip(member: .cal, state: .unused) {}
                NameChip(member: .priya, state: .consumed(cardNumber: 3)) {}
                NameChip(member: .theo, state: .selected) {}
            }
        }
    }

    @Test(arguments: devices, sizes) func countdown(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "CountdownView", device, size) {
            CountdownFixture.view(remaining: 7265, size: size)
        }
    }

    @Test(arguments: devices, sizes) func statMeter(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "StatMeter", device, size) {
            VStack(alignment: .leading, spacing: Space.x3) {
                StatMeter(value: 0.86, band: ReadabilityBand(readability: 0.86))
                StatMeter(value: 0.14, band: ReadabilityBand(readability: 0.14))
            }
        }
    }

    @Test(arguments: devices, sizes) func artwork(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "ArtworkView", device, size) {
            HStack(alignment: .top, spacing: Space.lg) {
                ArtworkView(.ribs, size: Layout.Artwork.searchRow)
                ArtworkView(.ribs, size: Layout.Artwork.flightCard)
                // No template: the placeholder, which is the state a card in The Record can
                // legitimately reach when Apple's URL stops resolving.
                ArtworkView(template: nil, backgroundColor: "1d2b3a", size: Layout.Artwork.flightCard)
            }
        }
    }

    @Test(arguments: devices, sizes) func emptyState(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "EmptyState", device, size) {
            EmptyState(
                headline: "submit.headline",
                message: "search.empty",
                action: .init(title: "submit.action", accent: .sealed) {}
            )
        }
    }

    // MARK: -

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(of: content(), device: device, typeSize: size)
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Components",
            sourceLocation: sourceLocation
        )
    }
}

extension DynamicTypeSize {
    /// The name a golden file carries. Spelled out rather than derived from `String(describing:)`
    /// so that a Swift release renaming a case does not rename every file on disk.
    var snapshotName: String {
        switch self {
        case .xSmall: "xSmall"
        case .small: "small"
        case .medium: "medium"
        case .large: "large"
        case .xLarge: "xLarge"
        case .xxLarge: "xxLarge"
        case .xxxLarge: "xxxLarge"
        case .accessibility1: "accessibility1"
        case .accessibility2: "accessibility2"
        case .accessibility3: "accessibility3"
        case .accessibility4: "accessibility4"
        case .accessibility5: "accessibility5"
        @unknown default: "unknown"
        }
    }
}

// MARK: - Fixtures

/// A countdown wired to a frozen clock.
///
/// The clock is anchored with a fixed uptime reading and a fixed `server_now`, so the timer
/// resolves to the same digits on every run — and the view is handed a started timer, because
/// `ImageRenderer` does not run `.onAppear` and a timer nobody started reads `--:--:--`.
@MainActor
enum CountdownFixture {
    static let serverNow = Date(timeIntervalSince1970: 1_786_000_000)

    static func view(remaining: TimeInterval, size: DynamicTypeSize) -> some View {
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: serverNow)
        let timer = CountdownTimer(clock: clock)
        let deadline = serverNow.addingTimeInterval(remaining)
        timer.start(until: deadline, form: Typography.countdownForm(for: size))
        return CountdownView(timer: timer, deadline: deadline, accent: .sealed, announces: .reveal)
    }
}

extension TrackDTO {
    static let ribs = TrackDTO(
        trackKey: "isrc:NZUM71300123",
        isrc: "NZUM71300123",
        title: "Ribs",
        artist: "Lorde",
        album: "Pure Heroine",
        artworkURL: "https://example.test/{w}x{h}bb.jpg",
        artworkBackgroundColor: "1d2b3a",
        durationMilliseconds: 249_000,
        previewURL: URL(string: "https://example.test/ribs.m4a"),
        appleMusicID: "1440857781",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/ribs/1440857781")!,
        spotifyID: nil,
        spotifyURL: nil
    )

    static let motionSickness = TrackDTO(
        trackKey: "isrc:USUM71703861",
        isrc: "USUM71703861",
        title: "Motion Sickness",
        artist: "Phoebe Bridgers",
        album: "Stranger in the Alps",
        artworkURL: "https://example.test/{w}x{h}bb.jpg",
        artworkBackgroundColor: "3a2b1d",
        durationMilliseconds: 240_000,
        previewURL: URL(string: "https://example.test/motion.m4a"),
        appleMusicID: "1440857782",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/motion-sickness/1440857782")!,
        spotifyID: nil,
        spotifyURL: nil
    )

    /// Both links present — `CardCornerLinks`' worst case. Every other fixture here has
    /// `spotifyID: nil`, which never exercises the stacked two-line corner; this is the one
    /// that tells a stacked corner colliding with the seal stamp apart from one that does not.
    static let bothLinks = TrackDTO(
        trackKey: "isrc:USUM71300456",
        isrc: "USUM71300456",
        title: "Eenie Meenie",
        artist: "Sean Kingston & Justin Bieber",
        album: "Sean Kingston & Justin Bieber",
        artworkURL: "https://example.test/{w}x{h}bb.jpg",
        artworkBackgroundColor: "1d2b3a",
        durationMilliseconds: 194_000,
        previewURL: URL(string: "https://example.test/eenie.m4a"),
        appleMusicID: "1440857783",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/eenie-meenie/1440857783")!,
        spotifyID: "3a1lNhkSLSkpJE4MSHpDu9",
        spotifyURL: URL(string: "https://open.spotify.com/track/3a1lNhkSLSkpJE4MSHpDu9")!
    )

    /// The truncation case. A one-line row that grows with the text and truncates at its end is
    /// intact; a layout that overlaps at `.accessibility5` is not, and this is the fixture that
    /// tells them apart in a diff.
    static let longTitle = TrackDTO(
        trackKey: "am:1234567890",
        isrc: nil,
        title: "Everything Is Embarrassing (Extended Mix) [Remastered 2019]",
        artist: "Sky Ferreira with a very long collaborator credit",
        album: "Ghost",
        artworkURL: nil,
        artworkBackgroundColor: nil,
        durationMilliseconds: 300_000,
        previewURL: nil,
        appleMusicID: "1234567890",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/x/1234567890")!,
        spotifyID: nil,
        spotifyURL: nil
    )
}

extension MemberDTO {
    static let cal = MemberDTO(userID: "u1", displayName: "Cal")
    static let priya = MemberDTO(userID: "u2", displayName: "Priya")
    static let theo = MemberDTO(userID: "u3", displayName: "Theo")
}
