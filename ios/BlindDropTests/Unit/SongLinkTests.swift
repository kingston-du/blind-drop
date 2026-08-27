import Foundation
import Testing
@testable import BlindDrop

/// The paste path's parser (`docs/06` §4, `docs/14` §7).
///
/// Its job is not to decide whether a song exists — the server does that — but to decide whether a
/// string is a **link at all**, which is what separates the copy deck's two paste errors and what
/// keeps an arbitrary string from becoming a request.
@Suite struct SongLinkTests {

    /// The forms `docs/06` §4 lists, each in the shape a real share sheet produces.
    @Test(arguments: [
        "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
        "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU?si=abc123",
        "https://open.spotify.com/intl-de/track/2QjOHCTQ1JF3zJyfWY7EMU",
        "spotify:track:2QjOHCTQ1JF3zJyfWY7EMU",
        "https://music.apple.com/us/song/ribs/1440818664",
        "https://music.apple.com/us/album/pure-heroine/1440818661?i=1440818664",
        "https://geo.music.apple.com/us/song/ribs/1440818664",
    ])
    func everyShareLinkParses(_ raw: String) throws {
        let link = try #require(SongLink(raw), "\(raw) should be a song link")
        // All of them travel in `spotify_url`, which is the field the server runs its full link
        // parser over — *"half of them will paste an Apple one"* (`_shared/music/resolve.ts`).
        guard case .spotifyURL = link.input else {
            Issue.record("\(raw) should be sent as a link")
            return
        }
    }

    /// A bare ISRC is its own field, because it has no scheme and no host to be checked against.
    @Test func abareIsrcIsItsOwnField() throws {
        let link = try #require(SongLink("usum7-1311296"))
        #expect(link == .isrc("USUM71311296"), "uppercased and de-hyphenated (`docs/06` §3)")
        guard case let .isrc(value) = link.input else {
            Issue.record("an ISRC should be sent as one")
            return
        }
        #expect(value == "USUM71311296")
    }

    /// **Nothing else becomes a request** (`docs/14` §7). A host we do not know is not a song link,
    /// whatever it looks like — the allowlist is the same one the server keeps.
    @Test(arguments: [
        "have you heard the new lorde",
        "",
        "   ",
        "https://example.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
        "https://open.spotify.evil.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
        "file:///etc/passwd",
        "javascript:alert(1)",
        "spotify:album:2QjOHCTQ1JF3zJyfWY7EMU",
        "TOOSHORT",
        "NOTANISRC12X",
    ])
    func anythingElseIsNotALink(_ raw: String) {
        #expect(SongLink(raw) == nil, "\(raw) is not a song link")
    }

    /// An ISRC is two letters, three alphanumerics, then seven digits. *"CAN SOMEBODY HELP"* is
    /// twelve characters too, which is why the shape is checked rather than the length.
    @Test func theIsrcShapeIsCheckedRatherThanTheLength() {
        #expect(SongLink.isrc(from: "USUM71311296") == "USUM71311296")
        #expect(SongLink.isrc(from: "US-UM7-13-11296") == "USUM71311296")
        #expect(SongLink.isrc(from: "USUM7131129") == nil, "eleven characters")
        #expect(SongLink.isrc(from: "12UM71311296") == nil, "digits where the country goes")
        #expect(SongLink.isrc(from: "USUM7131129X") == nil, "a letter where the designation goes")
    }

    /// Whitespace around a pasted link is what a share sheet actually produces.
    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(SongLink("  https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU \n") != nil)
    }

    /// `E29-03`: the reveal/guessing-phase card exposes the same Apple Music/Spotify menu the
    /// answer card and The Record rows already do. `FlightCard` is a view and its reveal branch is
    /// not directly instantiable from a unit test, so the invariant is pinned against the source —
    /// the `RoundInsetTests` pattern. Two facts: the `flightRow` branch draws `linksMenu`, and the
    /// VoiceOver re-exposure gates on the shared `hasLinks` condition rather than the old
    /// `isAnswer` gate, which would have left a reveal card's links reachable by touch and by
    /// nobody swiping.
    @Test func everyCardStateExposesTheSameLinkMenu() throws {
        let source = try source("DesignSystem/Components/FlightCard.swift")
        let flightRow = try #require(flightRowSource(source))
        #expect(flightRow.contains("linksMenu"), "the reveal flight row must draw the link menu")
        // The shared gate is what makes the menu and the VoiceOver re-exposure agree on one fact.
        #expect(source.contains("if hasLinks {"), "the links gate on the shared hasLinks condition")
    }

    private func source(_ path: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
            .appending(path: "BlindDrop/\(path)")
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// The `flightRow` computed property's body, from its declaration to the next property after
    /// it (`answerCard`). Source-scoped so the assertion is about *this* branch drawing the menu,
    /// not merely the file containing the symbol somewhere.
    private func flightRowSource(_ source: String) -> String? {
        guard let start = source.range(of: "private var flightRow: some View {"),
              let end = source.range(
                  of: "private var answerCard: some View {",
                  range: start.upperBound..<source.endIndex
              )
        else { return nil }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
